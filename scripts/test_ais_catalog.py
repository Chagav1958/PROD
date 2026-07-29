import sqlite3, json
conn = sqlite3.connect(r"C:\AIS\AI\Prod\scripts\ais_catalog_mcp\knowledge.db")
conn.row_factory = sqlite3.Row

obj = conn.execute('SELECT * FROM object_metadata WHERE name = ?', ('u_report_list',)).fetchone()
print('u_report_list:', dict(obj) if obj else 'NOT FOUND')
if obj:
    for f in ['tables', 'calls', 'sql_refs', 'pb_refs']:
        if obj[f]:
            try:
                print('  ' + f + ':', json.loads(obj[f]))
            except:
                print('  ' + f + ':', obj[f])

rows = conn.execute("SELECT name, kind, src, obj_type, lib FROM object_metadata WHERE name LIKE ? LIMIT 5", ('%report%',)).fetchall()
print('Search report:', [dict(r) for r in rows])

obj = conn.execute('SELECT calls, sql_refs, pb_refs FROM object_metadata WHERE name = ?', ('u_report_list',)).fetchone()
if obj:
    for field in ['calls', 'sql_refs', 'pb_refs']:
        val = obj[field]
        if val:
            try:
                items = json.loads(val)
                print('  ' + field + ':', items[:10])
            except:
                pass