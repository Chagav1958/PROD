import sqlite3, json, sys
sys.path.insert(0, r"C:\AIS\AI\Prod\scripts\ais_catalog_mcp")
from server import get_db
conn = get_db()

# Test get_object_metadata
row = conn.execute('SELECT * FROM object_metadata WHERE name = ?', ('u_report_list',)).fetchone()
if row:
    obj = dict(row)
    for f in ['tables', 'calls', 'sql_refs', 'pb_refs', 'srd_exprs', 'srd_dyn_sql', 'srd_valid', 'srd_masks', 'srd_computed', 'srd_filters', 'linked_tables']:
        if obj.get(f):
            try: obj[f] = json.loads(obj[f])
            except: pass
    print('get_object_metadata: OK')
    print('  name:', obj['name'])
    print('  kind:', obj['kind'])
    print('  src:', obj['src'])
    print('  obj_type:', obj['obj_type'])
    print('  tags:', obj['tags'])
    print('  pb_refs count:', len(obj['pb_refs']))
    print('  sql_refs count:', len(obj['sql_refs']))

# Test check_cross_project_impact
rows = conn.execute('SELECT project_name, tag FROM project_tags WHERE object_name = ?', ('reestr',)).fetchall()
print('check_cross_project_impact reestr:', [dict(r) for r in rows])

# Test search_codebase
rows = conn.execute("SELECT name, kind, src, obj_type, lib FROM object_metadata WHERE name LIKE ? LIMIT 3", ('%report%',)).fetchall()
print('search_codebase report:', [{'name':r[0],'kind':r[1],'src':r[2],'type':r[3],'lib':r[4]} for r in rows])

# Stats
print('Stats - objects:', conn.execute('SELECT COUNT(*) FROM object_metadata').fetchone()[0])
print('Stats - knowledge:', conn.execute('SELECT COUNT(*) FROM knowledge').fetchone()[0])
print('ais-catalog-mcp tools: VERIFIED')