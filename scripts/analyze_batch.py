"""
analyze_batch.py — партийный анализ объектов PB/SQL.
Извлекает структурированную информацию из .sru/.srw/.srd/.sql файлов,
сохраняет в object_analyses + object_properties.
"""
import sys, os, re
sys.path.insert(0, r'C:\AIS\AI\Prod\scripts\ais_objects_mcp')
from server import get_db, PB_CURRENT, BD_CURRENT
from datetime import datetime

db = get_db()
now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

# ===== PB PARSER =====
re_extend = re.compile(r'\b(inherits|extends)\s+(\w+)', re.IGNORECASE)
re_func = re.compile(r'^\s*(public|protected|private)?\s*(subroutine|function|event)\s+(\w+)', re.IGNORECASE | re.MULTILINE)
re_event = re.compile(r'^\s*event\s+(\w+)', re.IGNORECASE | re.MULTILINE)
re_var = re.compile(r'^\s*(public|protected|private)?\s*\b(\w+)\s+([iIdDsSlLcC]\w+)\b', re.IGNORECASE | re.MULTILINE)
re_open = re.compile(r'\bopen(sheet|withparm)?\s*\(\s*([wWuU]\w+)', re.IGNORECASE)
re_dw_ref = re.compile(r'\bdataobject\s*=\s*["\'](d\w*)["\']', re.IGNORECASE)
re_uo_ref = re.compile(r'\btype\s+(\w+)\s+from\s+(\w+)', re.IGNORECASE)
re_sql_exec = re.compile(r'\bEXEC(UTE)?\s+(@\w+\s*=\s*)?\b(usp?\w+)', re.IGNORECASE)
re_sql_table = re.compile(r'\b(?:FROM|JOIN|INTO|UPDATE)\s+(\w+)', re.IGNORECASE)
re_jira = re.compile(r'(SYBASE|SUPRT)-\d+', re.IGNORECASE)

def analyze_pb(path, name, lib, obj_type):
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except:
        return None
    
    lines = content.split('\n')
    
    ancestors = set()
    for m in re_extend.finditer(content):
        ancestors.add(m.group(2).lower())
    
    functions = []
    events = []
    for m in re_func.finditer(content):
        func_type = m.group(2).lower() if m.group(2) else 'func'
        func_name = m.group(3)
        if func_type == 'event':
            events.append(func_name)
        else:
            functions.append(func_name)
    
    variables = set()
    for m in re_var.finditer(content):
        vtype = m.group(2)
        vname = m.group(3)
        if vtype.lower() not in ('event', 'subroutine', 'function', 'public', 'protected', 'private'):
            variables.add(f"{vtype} {vname}")
    
    sub_objects = set()
    for m in re_open.finditer(content):
        sub_objects.add(m.group(2).lower())
    for m in re_dw_ref.finditer(content):
        sub_objects.add(m.group(1).lower())
    for m in re_uo_ref.finditer(content):
        sub_objects.add(m.group(2).lower())
    
    sql_refs = set()
    for m in re_sql_exec.finditer(content):
        sql_refs.add(('proc', m.group(3).lower()))
    for m in re_sql_table.finditer(content):
        t = m.group(1).lower()
        if t not in ('sys', 'dual', 'select', 'open', 'close', 'declare', 'create', 'drop', 'alter', 'where', 'set', 'values', 'null', 'if', 'else', 'begin', 'end', 'print', 'return', 'convert', 'cast', 'isnull', 'case', 'when', 'then', 'not', 'like', 'between', 'exists', 'having', 'union', 'all', 'any', 'some', 'top', 'distinct', 'order', 'group', 'by', 'asc', 'desc', 'on', 'as', 'with', 'and', 'or', 'left', 'right', 'inner', 'outer', 'join', 'into', 'insert', 'update', 'delete'):
            sql_refs.add(('table', t))
    
    jira_refs = set()
    for m in re_jira.finditer(content):
        jira_refs.add(m.group(0).upper())
    
    # Build analysis text
    parts = []
    parts.append(f"{'='*70}")
    parts.append(f"ANALIZ OBJEKTA: {name}")
    parts.append(f"Tip: {obj_type}")
    parts.append(f"Biblioteka: {lib}")
    parts.append(f"Razmer: {len(content)} simvolov, {len(lines)} strok")
    parts.append(f"Analiz vipolnen: {now} (avto-analizator)")
    parts.append(f"{'='*70}")
    
    if ancestors:
        parts.append("\n[PREDKI]")
        for a in sorted(ancestors):
            a_row = db.execute("SELECT lib FROM objects WHERE name = ? AND kind = 'PB'", (a,)).fetchone()
            part = f"- {a}"
            if a_row:
                part += f" (biblioteka: {a_row['lib']})"
            parts.append(part)
    
    if sub_objects:
        parts.append("\n[SUBOBJEKTY]")
        for so in sorted(sub_objects):
            so_row = db.execute("SELECT obj_type, lib FROM objects WHERE name = ? AND kind = 'PB' ORDER BY src", (so,)).fetchone()
            part = f"- {so}"
            if so_row:
                part += f" (tip: {so_row['obj_type']}, biblioteka: {so_row['lib']})"
            parts.append(part)
    
    if functions:
        parts.append(f"\n[FUNKTSII] ({len(functions)} sht.)")
        for f in functions[:50]:
            parts.append(f"  - {f}")
        if len(functions) > 50:
            parts.append(f"  ... i eshchjo {len(functions)-50}")
    
    if events:
        parts.append(f"\n[EVENTS] ({len(events)} sht.)")
        for e in events:
            parts.append(f"  - {e}")
    
    if variables:
        parts.append(f"\n[PEREMENNYE] ({len(variables)} sht.)")
        for v in sorted(variables)[:30]:
            parts.append(f"  - {v}")
        if len(variables) > 30:
            parts.append(f"  ... i eshchjo {len(variables)-30}")
    
    if sql_refs:
        parts.append(f"\n[SQL-VZAIMODEJSTVIYA] ({len(sql_refs)} sht.)")
        for stype, sname in sorted(sql_refs):
            parts.append(f"  - {stype}: {sname}")
    
    if jira_refs:
        parts.append(f"\n[ZADACHI JIRA V KOMMENTARIYAH] ({len(jira_refs)} sht.)")
        for j in sorted(jira_refs):
            parts.append(f"  - {j}")
    
    # Dependencies from DB
    deps_out = db.execute("SELECT to_object, dep_type FROM object_dependencies WHERE from_object = ? AND from_src = 'current' LIMIT 30", (name,)).fetchall()
    if deps_out:
        parts.append(f"\n[SVYAZI: VIZIVAET] ({len(deps_out)} sht.)")
        for d in deps_out:
            parts.append(f"  - {d['to_object']} ({d['dep_type']})")
    
    deps_in = db.execute("SELECT from_object, dep_type FROM object_dependencies WHERE to_object = ? LIMIT 30", (name,)).fetchall()
    if deps_in:
        parts.append(f"\n[SVYAZI: VIZIVAETSYA IZ] ({len(deps_in)} sht.)")
        for d in deps_in:
            parts.append(f"  - {d['from_object']} ({d['dep_type']})")
    
    return '\n'.join(parts)


# ===== SQL PARSER =====
re_sql_proc = re.compile(r'CREATE\s+(PROC(EDURE)?|FUNC(TION)?|TRIGGER|VIEW)\s+(\w+)', re.IGNORECASE)
re_sql_param = re.compile(r'@(\w+)\s+(\w+(?:\s*\([^)]*\))?)\s*(?:=\s*([^,\n]+))?', re.IGNORECASE)
re_sql_call = re.compile(r'\bEXEC(UTE)?\s+(?:@\w+\s*=\s*)?\b(usp?\w+)', re.IGNORECASE)
re_sql_table2 = re.compile(r'\b(?:FROM|JOIN|INTO|INSERT\s+INTO|UPDATE)\s+(\w+)', re.IGNORECASE)

def analyze_sql(path, name, obj_type):
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except:
        return None
    
    lines = content.split('\n')
    
    params = []
    for m in re_sql_param.finditer(content[:5000]):
        pname = m.group(1)
        ptype = m.group(2).strip()
        pdef = m.group(3).strip() if m.group(3) else ''
        if pname.lower() not in ('txt', 'sqlstatus', 'rowcount', 'error', 'servername', 'dbname', 'procname', 'spid', 'cmd', 'tranchained', 'sqlcode', 'status', 'lang', 'trancount', 'dateformat', 'datefirst', 'curread', 'curwrite', 'version', 'maxnest', 'isolation', 'char_convert', 'textsize', 'stringsize', 'nestlevel', 'packet_err', 'capabilities', 'name', 'id', 'cnt', 'msg', 'action', 'uid', 'grantee', 'i', 'time', 'context'):
            params.append((pname, ptype, pdef))
    
    sub_procs = set()
    for m in re_sql_call.finditer(content):
        sub_procs.add(m.group(2).lower())
    
    tables = set()
    for m in re_sql_table2.finditer(content):
        t = m.group(1).lower()
        if len(t) > 2 and t not in ('sys', 'dual', 'select', 'open', 'close', 'declare', 'create', 'drop', 'alter', 'where', 'set', 'values', 'null', 'if', 'else', 'begin', 'end', 'print', 'return', 'convert', 'cast', 'isnull', 'case', 'when', 'then', 'not', 'like', 'between', 'exists', 'having', 'union', 'all', 'any', 'some', 'top', 'distinct', 'order', 'group', 'by', 'asc', 'desc', 'on', 'as', 'with', 'and', 'or', 'left', 'right', 'inner', 'outer', 'join', 'into', 'insert', 'delete', 'cascade', 'default', 'unique', 'check', 'primary', 'foreign', 'key', 'index', 'constraint', 'references', 'no', 'identity', 'cluster', 'nonclust', 'view'):
            tables.add(t)
    
    jira_refs = set()
    for m in re_jira.finditer(content):
        jira_refs.add(m.group(0).upper())
    
    parts = []
    parts.append(f"{'='*70}")
    parts.append(f"ANALIZ OBJEKTA: {name}")
    parts.append(f"Tip: {obj_type}")
    parts.append(f"Server: dev_golden")
    parts.append(f"Razmer: {len(content)} simvolov, {len(lines)} strok")
    parts.append(f"Analiz vipolnen: {now} (avto-analizator)")
    parts.append(f"{'='*70}")
    
    if params:
        parts.append(f"\n[PARAMETRY] ({len(params)} sht.)")
        for pname, ptype, pdef in params:
            pdef_str = f" = {pdef}" if pdef else ""
            parts.append(f"  - @{pname} {ptype}{pdef_str}")
    
    if tables:
        parts.append(f"\n[TABLITSY] ({len(tables)} sht.)")
        for t in sorted(tables):
            parts.append(f"  - {t}")
    
    if sub_procs:
        parts.append(f"\n[SUBOBJEKTY: VIZOVY PROCEDUR] ({len(sub_procs)} sht.)")
        for p in sorted(sub_procs):
            p_row = db.execute("SELECT obj_type FROM objects WHERE name = ? AND kind = 'SQL' LIMIT 1", (p,)).fetchone()
            ptype = p_row['obj_type'] if p_row else '?'
            parts.append(f"  - {p} ({ptype})")
    
    if jira_refs:
        parts.append(f"\n[ZADACHI JIRA V KOMMENTARIYAH] ({len(jira_refs)} sht.)")
        for j in sorted(jira_refs):
            parts.append(f"  - {j}")
    
    deps_out = db.execute("SELECT to_object, dep_type FROM object_dependencies WHERE from_object = ? AND from_src = 'current' LIMIT 30", (name,)).fetchall()
    if deps_out:
        parts.append(f"\n[SVYAZI: VIZIVAET] ({len(deps_out)} sht.)")
        for d in deps_out:
            parts.append(f"  - {d['to_object']} ({d['dep_type']})")
    
    deps_in = db.execute("SELECT from_object, dep_type FROM object_dependencies WHERE to_object = ? LIMIT 30", (name,)).fetchall()
    if deps_in:
        parts.append(f"\n[SVYAZI: VIZIVAETSYA IZ] ({len(deps_in)} sht.)")
        for d in deps_in:
            parts.append(f"  - {d['from_object']} ({d['dep_type']})")
    
    return '\n'.join(parts)


# ===== MAIN =====
def process_batch(kind, lib=None, limit=100, offset=0):
    query = """SELECT o.id, o.name, o.kind, o.src, o.obj_type, o.lib, o.file_path 
               FROM objects o 
               LEFT JOIN object_analyses a ON a.object_id = o.id AND a.tags LIKE '%auto_analysis%'
               WHERE o.kind = ? AND o.src = 'current' AND a.id IS NULL"""
    params = [kind]
    if lib:
        query += " AND o.lib = ?"
        params.append(lib)
    query += " ORDER BY o.obj_type, o.name LIMIT ?"
    params.append(limit)
    
    rows = db.execute(query, params).fetchall()
    print(f"Batch: {len(rows)} objects ({kind}, lib={lib}, offset={offset})")
    
    processed = 0
    for r in rows:
        name = r['name']
        path = r['file_path']
        obj_type = r['obj_type']
        obj_lib = r['lib']
        
        if kind == 'PB':
            text = analyze_pb(path, name, obj_lib, obj_type)
        else:
            text = analyze_sql(path, name, obj_type)
        
        if text:
            db.execute(
                "INSERT INTO object_analyses (object_id, text, tags, created_at) VALUES (?, ?, 'auto_analysis,batch', ?)",
                (r['id'], text, now)
            )
            processed += 1
    
    db.commit()
    return processed


if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--kind', default='PB', choices=['PB', 'SQL'])
    p.add_argument('--lib', default=None)
    p.add_argument('--limit', type=int, default=100)
    p.add_argument('--offset', type=int, default=0)
    args = p.parse_args()
    
    n = process_batch(args.kind, args.lib, args.limit, args.offset)
    print(f"Processed: {n}")
    db.close()
