import sys
sys.path.insert(0, r"C:\AIS\AI\Prod\scripts\ais_catalog_mcp")
from server import init_db, load_catalog_to_db
init_db()
load_catalog_to_db()
import sqlite3
conn = sqlite3.connect(r"C:\AIS\AI\Prod\scripts\ais_catalog_mcp\knowledge.db")
print("objects:", conn.execute("SELECT COUNT(*) FROM object_metadata").fetchone()[0])
print("rules:", conn.execute("SELECT COUNT(*) FROM business_rules").fetchone()[0])
print("tags:", conn.execute("SELECT COUNT(*) FROM project_tags").fetchone()[0])
conn.close()