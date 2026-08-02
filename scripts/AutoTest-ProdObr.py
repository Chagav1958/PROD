# AutoTest-ProdObr.py — Полный цикл ПРОДОБР (Python, без GUI, без AV-триггеров)
import sys, os, re, subprocess, datetime, time

PROJ_ROOT   = r"C:\AIS\AI\Prod"
TASKS_ROOT  = os.path.join(PROJ_ROOT, "tasks")
ANALYZE     = os.path.join(PROJ_ROOT, "scripts", "analyze_batch.py")
PYTHON      = os.path.join(PROJ_ROOT, "scripts", "ais_objects_mcp", ".venv", "Scripts", "python.exe")
JOURNAL     = os.path.join(os.environ.get("TEMP", "."), f"prodobr_journal_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

errors = []; passed = []; failed = []

def log(level, msg):
    line = f"[{datetime.datetime.now().strftime('%H:%M:%S.%f')[:12]}] [{level}] {msg}"
    print(line)
    try:
        with open(JOURNAL, "a", encoding="utf-8") as f: f.write(line + "\n")
    except: pass

log("INFO", "=== PRODOBR AUTOTEST v2 (Python) ===")

# --- Найти задачу ---
task = None
pending = os.path.join(PROJ_ROOT, "rules", "pending-tasks.md")
if os.path.isfile(pending):
    with open(pending, encoding="utf-8") as f:
        m = re.search(r'###\s+(\S+?)\s+[—–-].*?Статус:\*\*\s*\[[~x]\]', f.read(), re.DOTALL)
    if m:
        task = {"name": m.group(1), "folder": os.path.join(TASKS_ROOT, m.group(1))}
if not task:
    for d in os.listdir(TASKS_ROOT):
        plan = os.path.join(TASKS_ROOT, d, "ПЛАН_РЕАЛИЗАЦИИ.txt")
        if os.path.isfile(plan):
            with open(plan, encoding="utf-8") as f:
                if "[~]" in f.read():
                    task = {"name": d, "folder": os.path.join(TASKS_ROOT, d)}; break
if not task:
    log("ERROR", "NO_TASK"); sys.exit(1)
log("INFO", f"Task: {task['name']}")

# --- Определить необработанные библиотеки ---
# Спрашиваем SQLite напрямую
sys.path.insert(0, os.path.join(PROJ_ROOT, "scripts", "ais_objects_mcp"))
from server import get_db
db = get_db()

# Все PB-библиотеки (current)
all_libs = [r[0] for r in db.execute(
    "SELECT DISTINCT lib FROM objects WHERE kind='PB' AND src='current' AND lib != '' ORDER BY lib"
).fetchall()]

# Определяем, у каких библиотек есть необработанные объекты (без авто-анализа)
pending_libs = []
for lib in all_libs:
    total = db.execute("SELECT count(*) FROM objects WHERE kind='PB' AND src='current' AND lib=?", (lib,)).fetchone()[0]
    done  = db.execute(
        "SELECT count(DISTINCT o.id) FROM objects o JOIN object_analyses a ON a.object_id=o.id WHERE o.kind='PB' AND o.src='current' AND o.lib=? AND a.tags LIKE '%auto_analysis%'",
        (lib,)
    ).fetchone()[0]
    if done < total:
        pending_libs.append((lib, total, done))
    else:
        passed.append((lib, f"{done}/{total}"))

log("INFO", f"Pending PB libs: {len(pending_libs)} of {len(all_libs)}")

# Также SQL-объекты
sql_pending = False
for cat in ["Procedure", "Functions", "Triggers", "Views", "Tables", "PK", "FK", "Grants", "Indexes"]:
    total = db.execute("SELECT count(*) FROM objects WHERE kind='SQL' AND src='current' AND lib=?", (cat,)).fetchone()[0]
    done  = db.execute(
        "SELECT count(DISTINCT o.id) FROM objects o JOIN object_analyses a ON a.object_id=o.id WHERE o.kind='SQL' AND o.src='current' AND o.lib=? AND a.tags LIKE '%auto_analysis%'",
        (cat,)
    ).fetchone()[0]
    if done < total:
        sql_pending = True; pending_libs.append((f"SQL:{cat}", total, done))
    else:
        passed.append((f"SQL:{cat}", f"{done}/{total}"))

db.close()

if not pending_libs:
    log("INFO", "=== ALL DONE! Nothing to process ===")
    sys.exit(0)

# --- Обработать все библиотеки в цикле ---
max_iterations = 20
iteration = 0
while pending_libs and iteration < max_iterations:
    iteration += 1
    log("INFO", f"=== Iteration {iteration}/{max_iterations}: {len(pending_libs)} libs pending ===")
    next_batch = []
    for lib_name, total, done in pending_libs:
        remaining = total - done
        if remaining <= 0:
            passed.append((lib_name, f"{done}/{total}"))
            continue
        
        log("INFO", f"--- {lib_name}: {remaining}/{total} remaining ---")
        
        if lib_name.startswith("SQL:"):
            kind = "SQL"; cat = lib_name.split(":")[1]
            cmd  = [PYTHON, ANALYZE, "--kind", "SQL", "--lib", cat, "--limit", "100"]
        else:
            kind = "PB"; cmd = [PYTHON, ANALYZE, "--kind", "PB", "--lib", lib_name, "--limit", str(min(remaining, 100)), "--offset", str(done)]
        
        log("INFO", f"  CMD: {' '.join(cmd)}")
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            for line in res.stdout.split("\n"):
                if "Processed:" in line:
                    m = re.search(r'Processed:\s+(\d+)', line)
                    if m: log("INFO", f"  {line.strip()}")
            
            db2 = get_db()
            new_done = db2.execute(
                "SELECT count(DISTINCT o.id) FROM objects o JOIN object_analyses a ON a.object_id=o.id WHERE o.kind=? AND o.src='current' AND o.lib=? AND a.tags LIKE '%auto_analysis%'",
                (kind, lib_name if kind == "PB" else cat)
            ).fetchone()[0]
            db2.close()
            
            if res.returncode == 0:
                delta = new_done - done
                log("INFO", f"  OK: {lib_name} -> {new_done}/{total} (+{delta})")
                if new_done < total:
                    next_batch.append((lib_name, total, new_done))
                else:
                    passed.append((lib_name, f"{new_done}/{total}"))
            else:
                log("ERROR", f"  FAIL: {lib_name} exit={res.returncode}")
                failed.append(lib_name)
                for line in res.stderr.split("\n")[:3]:
                    if line.strip(): log("ERROR", f"    {line.strip()}")
        except subprocess.TimeoutExpired:
            log("ERROR", f"  TIMEOUT: {lib_name}")
            failed.append(lib_name)
        except Exception as e:
            log("ERROR", f"  EXCEPTION: {lib_name} -> {e}")
            failed.append(lib_name)
    
    pending_libs = next_batch

# --- Итог ---
log("INFO", "=" * 50)
log("INFO", f"PASSED:  {len(passed)}")
log("INFO", f"FAILED:  {len(failed)}")
for p in passed:
    log("INFO", f"  [OK] {p[0]}: {p[1]}")
for f in failed:
    log("ERROR", f"  [FAIL] {f}")

report_path = os.path.join(os.environ.get("TEMP", "."), f"prodobr_autotest_report_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.txt")
with open(report_path, "w", encoding="utf-8") as rf:
    rf.write(f"PRODOBR AUTOTEST v2 REPORT\n{'='*50}\nDate: {datetime.datetime.now()}\nTask: {task['name']}\nPassed: {len(passed)}\nFailed: {len(failed)}\nJournal: {JOURNAL}\n")
    rf.write("\nPASSED:\n")
    for p in passed: rf.write(f"  [OK] {p[0]}: {p[1]}\n")
    rf.write("\nFAILED:\n")
    for f in failed: rf.write(f"  [FAIL] {f}\n")

log("INFO", f"Report: {report_path}")
print(f"\nReport: {report_path}")
sys.exit(1 if failed else 0)
