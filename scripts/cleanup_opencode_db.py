import sqlite3
import os
import sys
import time
import shutil
from datetime import datetime, timedelta

sys.stdout.reconfigure(encoding='utf-8')

db_path = os.path.expanduser(r"~\.local\share\opencode\opencode.db")
db_wal = db_path + "-wal"
db_shm = db_path + "-shm"
backup_path = db_path + f".backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

print("=" * 60)
print("  Очистка старых сессий OpenCode + VACUUM")
print("=" * 60)

# 0. Check OpenCode is NOT running
import subprocess
result = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq OpenCode.exe'], capture_output=True, text=True)
if 'OpenCode.exe' in result.stdout:
    print("\n[ОШИБКА] OpenCode запущен! Закройте OpenCode перед запуском этого скрипта.")
    sys.exit(1)

print("\n[1/6] OpenCode не запущен — продолжаем.")

# 1. Backup the database
db_size_before = os.path.getsize(db_path) / 1024 / 1024
print(f"\n[2/6] Размер БД до очистки: {db_size_before:.2f} МБ")

print(f"       Создаём резервную копию: {backup_path}")
shutil.copy2(db_path, backup_path)
print(f"       Резервная копия создана ({os.path.getsize(backup_path) / 1024 / 1024:.2f} МБ)")

# 2. Connect and delete old sessions (older than 7 days)
conn = sqlite3.connect(db_path)
c = conn.cursor()

week_ago = int((time.time() - 7 * 86400) * 1000)

# Count before
c.execute("SELECT COUNT(*) FROM session")
total_before = c.fetchone()[0]
c.execute("SELECT COUNT(*) FROM session WHERE time_created < ?", (week_ago,))
old_count = c.fetchone()[0]
print(f"\n[3/6] Сессий всего: {total_before}, старше 7 дней: {old_count}")

# Get IDs of old sessions
c.execute("SELECT id FROM session WHERE time_created < ?", (week_ago,))
old_ids = [row[0] for row in c.fetchall()]

if old_ids:
    placeholders = ','.join('?' * len(old_ids))

    # Delete related records
    c.execute(f"DELETE FROM part WHERE session_id IN ({placeholders})", old_ids)
    parts_deleted = c.rowcount
    print(f"       Удалено parts: {parts_deleted}")

    c.execute(f"DELETE FROM message WHERE session_id IN ({placeholders})", old_ids)
    msgs_deleted = c.rowcount
    print(f"       Удалено messages: {msgs_deleted}")

    c.execute(f"DELETE FROM todo WHERE session_id IN ({placeholders})", old_ids)
    todos_deleted = c.rowcount
    print(f"       Удалено todos: {todos_deleted}")

    c.execute(f"DELETE FROM session_message WHERE session_id IN ({placeholders})", old_ids)
    sm_deleted = c.rowcount
    print(f"       Удалено session_messages: {sm_deleted}")

    c.execute(f"DELETE FROM session_input WHERE session_id IN ({placeholders})", old_ids)
    si_deleted = c.rowcount
    print(f"       Удалено session_inputs: {si_deleted}")

    c.execute(f"DELETE FROM session_context_epoch WHERE session_id IN ({placeholders})", old_ids)
    sce_deleted = c.rowcount
    print(f"       Удалено session_context_epochs: {sce_deleted}")

    c.execute(f"DELETE FROM session_share WHERE session_id IN ({placeholders})", old_ids)
    ss_deleted = c.rowcount
    print(f"       Удалено session_shares: {ss_deleted}")

    # Delete events for these sessions
    c.execute(f"DELETE FROM event WHERE aggregate_id IN ({placeholders})", old_ids)
    events_deleted = c.rowcount
    print(f"       Удалено events: {events_deleted}")

    # Finally delete sessions
    c.execute(f"DELETE FROM session WHERE id IN ({placeholders})", old_ids)
    sessions_deleted = c.rowcount
    print(f"       Удалено sessions: {sessions_deleted}")

    conn.commit()
    print(f"\n       Всего удалено {old_count} сессий и связанных записей.")
else:
    print("       Нет сессий старше 7 дней — пропускаем удаление.")

# 3. Also clean up orphaned tool-output files
tool_output_dir = os.path.expanduser(r"~\.local\share\opencode\tool-output")
if os.path.isdir(tool_output_dir):
    files = os.listdir(tool_output_dir)
    print(f"\n[4/6] Файлов в tool-output: {len(files)}")
    # Keep tool-output files (they may be referenced by remaining sessions)
    print("       Пропускаем (могут ссылаться на оставшиеся сессии).")
else:
    print(f"\n[4/6] Папка tool-output не найдена.")

# 4. VACUUM
print(f"\n[5/6] Выполняю VACUUM (может занять 1-2 минуты)...")
c.execute("VACUUM")
conn.commit()
print("       VACUUM завершён.")

# 5. Report results
c.execute("SELECT COUNT(*) FROM session")
total_after = c.fetchone()[0]
conn.close()

db_size_after = os.path.getsize(db_path) / 1024 / 1024
saved = db_size_before - db_size_after

print(f"\n[6/6] Результаты:")
print(f"  Сессий до:  {total_before}")
print(f"  Сессий после: {total_after}")
print(f"  Размер БД до:  {db_size_before:.2f} МБ")
print(f"  Размер БД после: {db_size_after:.2f} МБ")
print(f"  Экономия: {saved:.2f} МБ ({saved/1024:.2f} ГБ)")
print(f"\n  Резервная копия: {backup_path}")
print(f"\n  Готово! Можно запускать OpenCode.")

print("\n" + "=" * 60)
