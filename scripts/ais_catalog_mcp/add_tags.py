import sqlite3
conn = sqlite3.connect(r"C:\AIS\AI\Prod\scripts\ais_catalog_mcp\knowledge.db")
conn.execute("INSERT INTO project_tags (object_name, project_name, tag) VALUES (?, ?, ?)", ("u_report_list", "AIS", "AIS_CORE"))
conn.execute("INSERT INTO project_tags (object_name, project_name, tag) VALUES (?, ?, ?)", ("docs", "AIS", "SHARED_AIS"))
conn.execute("INSERT INTO project_tags (object_name, project_name, tag) VALUES (?, ?, ?)", ("reestr", "Buhgalteria", "GLOBAL_DB"))
conn.execute("INSERT INTO project_tags (object_name, project_name, tag) VALUES (?, ?, ?)", ("reestr", "AIS", "SHARED_AIS"))
conn.execute("UPDATE object_metadata SET tags = ? WHERE name = ?", ("AIS_CORE", "u_report_list"))
conn.execute("UPDATE object_metadata SET tags = ? WHERE name = ?", ("SHARED_AIS", "docs"))
conn.execute("UPDATE object_metadata SET tags = ? WHERE name = ?", ("GLOBAL_DB", "reestr"))
conn.commit()
print("Tags added:", conn.execute("SELECT COUNT(*) FROM project_tags").fetchone()[0])
rows = conn.execute("SELECT name, tags FROM object_metadata WHERE tags != ''").fetchall()
for r in rows:
    print(r)