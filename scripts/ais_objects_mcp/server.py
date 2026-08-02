"""
MCP-сервер каталога объектов AIS (PB + SQL)
Хранит объекты, связи, анализ, свойства. Различает Main и Current (Production / Sandbox).
"""
import sqlite3
import json
import os
import sys
import hashlib
from datetime import datetime
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "objects.db")

# Корни объектов
PB_MAIN = r"C:\AIS\AI\Prod\PB_Main"
PB_CURRENT = r"C:\AIS\AI\Prod\PB_Current"
BD_MAIN = r"C:\AIS\AI\Prod\BD\galaxy\golden"
BD_CURRENT = r"C:\AIS\AI\Prod\BD\dev_golden\golden"


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db():
    conn = get_db()

    conn.execute("""
        CREATE TABLE IF NOT EXISTS objects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            src TEXT NOT NULL,
            obj_type TEXT,
            lib TEXT,
            file_path TEXT,
            file_size INTEGER,
            file_sha256 TEXT,
            file_modified TEXT,
            created_at TEXT NOT NULL,
            UNIQUE(name, kind, src)
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_objs_name ON objects(name)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_objs_kind_src ON objects(kind, src)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_objs_lib ON objects(lib)")

    conn.execute("""
        CREATE TABLE IF NOT EXISTS object_properties (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            object_id INTEGER NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
            key TEXT NOT NULL,
            value TEXT,
            updated_at TEXT NOT NULL,
            UNIQUE(object_id, key)
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS object_analyses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            object_id INTEGER NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
            text TEXT NOT NULL,
            tags TEXT DEFAULT '',
            created_at TEXT NOT NULL
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_analyses_obj ON object_analyses(object_id)")

    conn.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS analyses_fts USING fts5(
            text, tags, content=object_analyses, content_rowid=id
        )
    """)

    conn.execute("""
        CREATE TRIGGER IF NOT EXISTS analyses_ai AFTER INSERT ON object_analyses BEGIN
            INSERT INTO analyses_fts(rowid, text, tags) VALUES (new.id, new.text, new.tags);
        END
    """)
    conn.execute("""
        CREATE TRIGGER IF NOT EXISTS analyses_ad AFTER DELETE ON object_analyses BEGIN
            INSERT INTO analyses_fts(analyses_fts, rowid, text, tags) VALUES('delete', old.id, old.text, old.tags);
        END
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS object_dependencies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_object TEXT NOT NULL,
            from_src TEXT NOT NULL,
            to_object TEXT NOT NULL,
            dep_type TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(from_object, from_src, to_object, dep_type)
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_deps_from ON object_dependencies(from_object, from_src)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_deps_to ON object_dependencies(to_object)")

    conn.execute("""
        CREATE TABLE IF NOT EXISTS object_comparisons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            src1 TEXT NOT NULL,
            src2 TEXT NOT NULL,
            file1_path TEXT,
            file1_size INTEGER,
            file1_sha256 TEXT,
            file2_path TEXT,
            file2_size INTEGER,
            file2_sha256 TEXT,
            diff_lines TEXT,
            is_identical INTEGER,
            created_at TEXT NOT NULL
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_comp_name ON object_comparisons(name)")

    conn.commit()
    conn.close()


init_db()
server = Server("ais-objects-mcp")

# ============================================================
# Помощники
# ============================================================

SRC_MAP = {
    "main": {"pb": PB_MAIN, "sql": BD_MAIN, "label": "Production (galaxy)"},
    "current": {"pb": PB_CURRENT, "sql": BD_CURRENT, "label": "Sandbox (dev_golden)"},
}

PB_EXTS = {".srw": "Window", ".sru": "UserObject", ".srd": "DataWindow", ".srs": "Structure"}
SQL_DIRS = {"Procedure", "Functions", "Tables", "Triggers", "Views", "Indexes", "PK", "FK", "Grants"}


def _resolve_path(name, kind, src):
    if kind.upper() == "PB":
        for lib in os.listdir(SRC_MAP[src]["pb"] if src in SRC_MAP else PB_CURRENT):
            lib_path = os.path.join(SRC_MAP.get(src, {}).get("pb", PB_CURRENT), lib)
            if not os.path.isdir(lib_path):
                continue
            for ext in PB_EXTS:
                fpath = os.path.join(lib_path, name + ext)
                if os.path.isfile(fpath):
                    return fpath, lib, PB_EXTS[ext]
    else:
        base = SRC_MAP.get(src, {}).get("sql", BD_CURRENT)
        for d in SQL_DIRS:
            dpath = os.path.join(base, d)
            if not os.path.isdir(dpath):
                continue
            fpath = os.path.join(dpath, name + ".sql")
            if os.path.isfile(fpath):
                return fpath, d, "SQL"
    return None, None, None


def _file_info(path):
    if not path or not os.path.isfile(path):
        return None, None, None
    st = os.stat(path)
    size = st.st_size
    mtime = datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
    with open(path, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()[:16]
    return size, sha, mtime


def _import_pb(src):
    base = SRC_MAP[src]["pb"]
    if not os.path.isdir(base):
        return 0
    conn = get_db()
    count = 0
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    for lib in os.listdir(base):
        lib_path = os.path.join(base, lib)
        if not os.path.isdir(lib_path):
            continue
        for fname in os.listdir(lib_path):
            name, ext = os.path.splitext(fname)
            if ext not in PB_EXTS:
                continue
            fpath = os.path.join(lib_path, fname)
            size, sha, mtime = _file_info(fpath)
            try:
                conn.execute("""
                    INSERT OR REPLACE INTO objects (name, kind, src, obj_type, lib, file_path, file_size, file_sha256, file_modified, created_at)
                    VALUES (?, 'PB', ?, ?, ?, ?, ?, ?, ?, ?)
                """, (name, src, PB_EXTS[ext], lib, fpath, size, sha, mtime, now))
                count += 1
            except:
                pass
    conn.commit()
    conn.close()
    return count


def _import_sql(src):
    base = SRC_MAP[src]["sql"]
    if not os.path.isdir(base):
        return 0
    conn = get_db()
    count = 0
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    for d in SQL_DIRS:
        dpath = os.path.join(base, d)
        if not os.path.isdir(dpath):
            continue
        for fname in os.listdir(dpath):
            if not fname.endswith(".sql"):
                continue
            name = fname[:-4]
            fpath = os.path.join(dpath, fname)
            size, sha, mtime = _file_info(fpath)
            try:
                conn.execute("""
                    INSERT OR REPLACE INTO objects (name, kind, src, obj_type, lib, file_path, file_size, file_sha256, file_modified, created_at)
                    VALUES (?, 'SQL', ?, ?, ?, ?, ?, ?, ?, ?)
                """, (name, src, d, d, fpath, size, sha, mtime, now))
                count += 1
            except:
                pass
    conn.commit()
    conn.close()
    return count


# ============================================================
# Инструменты
# ============================================================

@server.list_tools()
async def handle_list_tools():
    return [
        Tool(name="import_objects", description="Импорт объектов PB/SQL из файловой системы в каталог. PB: из PB_Main/PB_Current. SQL: из BD/galaxy/golden или BD/dev_golden/golden.",
             inputSchema={"type": "object", "properties": {
                 "src": {"type": "string", "description": "Источник: 'main' (Production) или 'current' (Sandbox)"},
                 "kind": {"type": "string", "description": "'PB', 'SQL', или не указано = оба"}
             }, "required": ["src"]}),

        Tool(name="list_objects", description="Список объектов с фильтрацией по библиотеке, типу, источнику.",
             inputSchema={"type": "object", "properties": {
                 "lib": {"type": "string", "description": "Имя библиотеки (напр. 'golden_subject'), или каталог SQL"},
                 "kind": {"type": "string", "description": "'PB' или 'SQL'"},
                 "src": {"type": "string", "description": "'main' или 'current'"},
                 "obj_type": {"type": "string", "description": "Тип: Window, UserObject, DataWindow, Structure, Procedure, Function, Trigger, View, Table"},
                 "limit": {"type": "integer", "description": "Максимум результатов (по умолчанию 100)", "default": 100}
             }, "required": []}),

        Tool(name="get_object", description="Полная информация об объекте: свойства, анализы, зависимости.",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string", "description": "Имя объекта"},
                 "kind": {"type": "string", "description": "'PB' или 'SQL' (опционально)"},
                 "src": {"type": "string", "description": "'main' или 'current' (опционально)"}
             }, "required": ["name"]}),

        Tool(name="set_property", description="Установить свойство объекта (описание, статус, назначение, заметки).",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string", "description": "Имя объекта"},
                 "src": {"type": "string", "description": "'main' или 'current'"},
                 "key": {"type": "string", "description": "Ключ: description, status, purpose, notes, tested_by, reviewed_by"},
                 "value": {"type": "string", "description": "Значение свойства"}
             }, "required": ["name", "src", "key", "value"]}),

        Tool(name="save_analysis", description="Сохранить анализ объекта (привязывается к объекту, FTS-поиск).",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string", "description": "Имя объекта"},
                 "src": {"type": "string", "description": "'main' или 'current'"},
                 "text": {"type": "string", "description": "Текст анализа"},
                 "tags": {"type": "string", "description": "Теги через запятую"}
             }, "required": ["name", "src", "text"]}),

        Tool(name="get_analyses", description="Получить все анализы объекта.",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string", "description": "Имя объекта"},
                 "src": {"type": "string", "description": "'main' или 'current'"}
             }, "required": ["name", "src"]}),

        Tool(name="search_analyses", description="Полнотекстовый поиск по анализам (FTS5).",
             inputSchema={"type": "object", "properties": {
                 "query": {"type": "string", "description": "Поисковый запрос"},
                 "limit": {"type": "integer", "description": "Максимум результатов", "default": 10}
             }, "required": ["query"]}),

        Tool(name="add_dependency", description="Добавить связь между объектами.",
             inputSchema={"type": "object", "properties": {
                 "from_object": {"type": "string", "description": "Исходный объект"},
                 "from_src": {"type": "string", "description": "'main' или 'current'"},
                 "to_object": {"type": "string", "description": "Целевой объект"},
                 "dep_type": {"type": "string", "description": "Тип: calls (PB→PB), sql_ref (PB→SQL), pb_ref (SQL→PB)"}
             }, "required": ["from_object", "from_src", "to_object", "dep_type"]}),

        Tool(name="find_dependencies", description="Граф зависимостей: кто вызывает объект / кого вызывает объект.",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string", "description": "Имя исходного объекта"},
                 "src": {"type": "string", "description": "'main' или 'current'"},
                 "direction": {"type": "string", "description": "'forward' (кого вызывает), 'reverse' (кто вызывает), 'both'", "default": "both"},
                 "depth": {"type": "integer", "description": "Глубина обхода (1-3)", "default": 1}
             }, "required": ["name", "src"]}),

        Tool(name="compare_objects", description="Сравнить объект Main vs Current (Production vs Sandbox).",
             inputSchema={"type": "object", "properties": {
                 "name": {"type": "string", "description": "Имя объекта"},
                 "kind": {"type": "string", "description": "'PB' или 'SQL'"}
             }, "required": ["name", "kind"]}),

        Tool(name="search_objects", description="Поиск объектов по имени, библиотеке, типу.",
             inputSchema={"type": "object", "properties": {
                 "query": {"type": "string", "description": "Поисковый запрос"},
                 "limit": {"type": "integer", "description": "Максимум результатов", "default": 20}
             }, "required": ["query"]}),

        Tool(name="object_stats", description="Статистика каталога объектов.",
             inputSchema={"type": "object", "properties": {}, "required": []}),
    ]


@server.call_tool()
async def handle_call_tool(name: str, arguments: dict):
    conn = get_db()
    try:
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # ---- import_objects ----
        if name == "import_objects":
            src = arguments.get("src")
            kind = arguments.get("kind", "")
            if src not in ("main", "current"):
                return [TextContent(type="text", text=json.dumps({"error": "src должен быть 'main' или 'current'"}, ensure_ascii=False))]
            n_pb, n_sql = 0, 0
            if not kind or kind.upper() == "PB":
                n_pb = _import_pb(src)
            if not kind or kind.upper() == "SQL":
                n_sql = _import_sql(src)
            return [TextContent(type="text", text=json.dumps({
                "status": "ok", "src": src, "pb_imported": n_pb, "sql_imported": n_sql,
                "message": f"Импортировано PB: {n_pb}, SQL: {n_sql}"
            }, ensure_ascii=False))]

        # ---- list_objects ----
        elif name == "list_objects":
            lib = arguments.get("lib")
            kind = arguments.get("kind")
            src = arguments.get("src")
            obj_type = arguments.get("obj_type")
            limit = arguments.get("limit", 100)
            query = "SELECT * FROM objects WHERE 1=1"
            params = []
            if lib:
                query += " AND lib = ?"
                params.append(lib)
            if kind:
                query += " AND kind = ?"
                params.append(kind)
            if src:
                query += " AND src = ?"
                params.append(src)
            if obj_type:
                query += " AND obj_type = ?"
                params.append(obj_type)
            query += " ORDER BY name LIMIT ?"
            params.append(limit)
            rows = conn.execute(query, params).fetchall()
            results = [dict(r) for r in rows]
            return [TextContent(type="text", text=json.dumps({"count": len(results), "objects": results}, ensure_ascii=False))]

        # ---- get_object ----
        elif name == "get_object":
            obj_name = arguments["name"]
            kind = arguments.get("kind")
            src = arguments.get("src")
            q = "SELECT * FROM objects WHERE name = ?"
            p = [obj_name]
            if kind:
                q += " AND kind = ?"
                p.append(kind)
            if src:
                q += " AND src = ?"
                p.append(src)
            rows = conn.execute(q + " ORDER BY src", p).fetchall()
            if not rows:
                return [TextContent(type="text", text=json.dumps({"error": "Объект не найден", "name": obj_name}, ensure_ascii=False))]
            result = {"objects": []}
            for row in rows:
                oid = row["id"]
                props = conn.execute("SELECT key, value FROM object_properties WHERE object_id = ?", (oid,)).fetchall()
                deps_out = conn.execute("SELECT to_object, dep_type FROM object_dependencies WHERE from_object = ? AND from_src = ?", (row["name"], row["src"])).fetchall()
                deps_in = conn.execute("SELECT from_object, dep_type FROM object_dependencies WHERE to_object = ?", (row["name"],)).fetchall()
                analyses = conn.execute("SELECT id, text, tags, created_at FROM object_analyses WHERE object_id = ? ORDER BY created_at DESC", (oid,)).fetchall()
                obj = dict(row)
                obj["properties"] = [dict(p) for p in props]
                obj["deps_out"] = [dict(d) for d in deps_out]
                obj["deps_in"] = [dict(d) for d in deps_in]
                obj["analyses"] = [dict(a) for a in analyses]
                result["objects"].append(obj)
            return [TextContent(type="text", text=json.dumps(result, ensure_ascii=False))]

        # ---- set_property ----
        elif name == "set_property":
            obj_name = arguments["name"]
            src = arguments["src"]
            key = arguments["key"]
            value = arguments["value"]
            row = conn.execute("SELECT id FROM objects WHERE name = ? AND src = ?", (obj_name, src)).fetchone()
            if not row:
                return [TextContent(type="text", text=json.dumps({"error": f"Объект не найден: {obj_name} ({src})"}, ensure_ascii=False))]
            oid = row["id"]
            conn.execute("""
                INSERT OR REPLACE INTO object_properties (object_id, key, value, updated_at) VALUES (?, ?, ?, ?)
            """, (oid, key, value, now))
            conn.commit()
            return [TextContent(type="text", text=json.dumps({"status": "ok", "object": obj_name, "key": key, "value": value}, ensure_ascii=False))]

        # ---- save_analysis ----
        elif name == "save_analysis":
            obj_name = arguments["name"]
            src = arguments["src"]
            text = arguments["text"]
            tags = arguments.get("tags", "")
            row = conn.execute("SELECT id FROM objects WHERE name = ? AND src = ?", (obj_name, src)).fetchone()
            if not row:
                return [TextContent(type="text", text=json.dumps({"error": f"Объект не найден: {obj_name} ({src})"}, ensure_ascii=False))]
            oid = row["id"]
            c = conn.execute("INSERT INTO object_analyses (object_id, text, tags, created_at) VALUES (?, ?, ?, ?)", (oid, text, tags, now))
            conn.commit()
            return [TextContent(type="text", text=json.dumps({"status": "ok", "id": c.lastrowid, "object": obj_name, "src": src}, ensure_ascii=False))]

        # ---- get_analyses ----
        elif name == "get_analyses":
            obj_name = arguments["name"]
            src = arguments["src"]
            row = conn.execute("SELECT id FROM objects WHERE name = ? AND src = ?", (obj_name, src)).fetchone()
            if not row:
                return [TextContent(type="text", text=json.dumps({"error": f"Объект не найден: {obj_name} ({src})"}, ensure_ascii=False))]
            rows = conn.execute("SELECT * FROM object_analyses WHERE object_id = ? ORDER BY created_at DESC", (row["id"],)).fetchall()
            return [TextContent(type="text", text=json.dumps({
                "object": obj_name, "src": src, "count": len(rows), "analyses": [dict(r) for r in rows]
            }, ensure_ascii=False))]

        # ---- search_analyses ----
        elif name == "search_analyses":
            query = arguments["query"]
            limit = arguments.get("limit", 10)
            try:
                rows = conn.execute(
                    "SELECT a.id, a.text, a.tags, a.created_at, o.name, o.src "
                    "FROM object_analyses a JOIN analyses_fts fts ON a.id = fts.rowid "
                    "JOIN objects o ON o.id = a.object_id "
                    "WHERE analyses_fts MATCH ? ORDER BY rank LIMIT ?",
                    (query, limit)
                ).fetchall()
            except:
                rows = conn.execute(
                    "SELECT a.id, a.text, a.tags, a.created_at, o.name, o.src "
                    "FROM object_analyses a JOIN objects o ON o.id = a.object_id "
                    "WHERE a.text LIKE ? OR a.tags LIKE ? "
                    "ORDER BY a.created_at DESC LIMIT ?",
                    (f"%{query}%", f"%{query}%", limit)
                ).fetchall()
            return [TextContent(type="text", text=json.dumps({
                "query": query, "count": len(rows), "results": [dict(r) for r in rows]
            }, ensure_ascii=False))]

        # ---- add_dependency ----
        elif name == "add_dependency":
            fo = arguments["from_object"]
            fs = arguments["from_src"]
            to = arguments["to_object"]
            dt = arguments["dep_type"]
            if dt not in ("calls", "sql_ref", "pb_ref"):
                return [TextContent(type="text", text=json.dumps({"error": "dep_type must be: calls, sql_ref, pb_ref"}, ensure_ascii=False))]
            try:
                conn.execute("INSERT INTO object_dependencies (from_object, from_src, to_object, dep_type, created_at) VALUES (?, ?, ?, ?, ?)",
                             (fo, fs, to, dt, now))
                conn.commit()
                return [TextContent(type="text", text=json.dumps({"status": "ok", "from": fo, "to": to, "type": dt}, ensure_ascii=False))]
            except sqlite3.IntegrityError:
                return [TextContent(type="text", text=json.dumps({"status": "duplicate", "message": "Связь уже существует"}, ensure_ascii=False))]

        # ---- find_dependencies ----
        elif name == "find_dependencies":
            obj_name = arguments["name"]
            src = arguments["src"]
            direction = arguments.get("direction", "both")
            depth = arguments.get("depth", 1)
            result = {"start": obj_name, "src": src, "direction": direction, "depth": depth, "deps": []}
            if direction in ("forward", "both"):
                fwd = conn.execute("SELECT to_object, dep_type FROM object_dependencies WHERE from_object = ? AND from_src = ?", (obj_name, src)).fetchall()
                result["forward"] = [dict(r) for r in fwd]
            if direction in ("reverse", "both"):
                rev = conn.execute("SELECT from_object, dep_type FROM object_dependencies WHERE to_object = ?", (obj_name,)).fetchall()
                result["reverse"] = [dict(r) for r in rev]
            return [TextContent(type="text", text=json.dumps(result, ensure_ascii=False))]

        # ---- compare_objects ----
        elif name == "compare_objects":
            obj_name = arguments["name"]
            kind = arguments["kind"].upper()

            def _read_file(fpath):
                if not fpath or not os.path.isfile(fpath):
                    return None
                with open(fpath, "rb") as f:
                    return f.read()

            f1, lib1, t1 = _resolve_path(obj_name, kind, "main")
            f2, lib2, t2 = _resolve_path(obj_name, kind, "current")
            if not f1 and not f2:
                return [TextContent(type="text", text=json.dumps({"error": f"Объект не найден ни в Main, ни в Current: {obj_name}"}, ensure_ascii=False))]

            s1 = os.path.getsize(f1) if f1 else 0
            s2 = os.path.getsize(f2) if f2 else 0
            b1 = _read_file(f1)
            b2 = _read_file(f2)
            h1 = hashlib.sha256(b1).hexdigest()[:16] if b1 else ""
            h2 = hashlib.sha256(b2).hexdigest()[:16] if b2 else ""
            identical = (h1 == h2 and h1 != "")

            diff_lines = []
            if not identical and b1 and b2:
                t1_lines = b1.decode("utf-8", errors="replace").splitlines()
                t2_lines = b2.decode("utf-8", errors="replace").splitlines()
                for i, (l1, l2) in enumerate(zip(t1_lines, t2_lines)):
                    if l1 != l2:
                        diff_lines.append({"line": i + 1, "main": l1[:200], "current": l2[:200]})
                if len(t1_lines) != len(t2_lines):
                    diff_lines.append({"line": "N/A", "main_lines": len(t1_lines), "current_lines": len(t2_lines)})

            conn.execute("""INSERT INTO object_comparisons
                (name, kind, src1, src2, file1_path, file1_size, file1_sha256, file2_path, file2_size, file2_sha256, diff_lines, is_identical, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (obj_name, kind, "main", "current", f1, s1, h1, f2, s2, h2, json.dumps(diff_lines[:200]), 1 if identical else 0, now))
            conn.commit()

            return [TextContent(type="text", text=json.dumps({
                "name": obj_name, "kind": kind,
                "main": {"path": f1, "size": s1, "sha256": h1, "lib": lib1} if f1 else None,
                "current": {"path": f2, "size": s2, "sha256": h2, "lib": lib2} if f2 else None,
                "identical": identical,
                "diff_count": len(diff_lines),
                "diffs": diff_lines[:30]
            }, ensure_ascii=False))]

        # ---- search_objects ----
        elif name == "search_objects":
            query = arguments["query"]
            limit = arguments.get("limit", 20)
            rows = conn.execute(
                "SELECT * FROM objects WHERE name LIKE ? OR lib LIKE ? OR obj_type LIKE ? ORDER BY name LIMIT ?",
                (f"%{query}%", f"%{query}%", f"%{query}%", limit)
            ).fetchall()
            return [TextContent(type="text", text=json.dumps({
                "query": query, "count": len(rows), "objects": [dict(r) for r in rows]
            }, ensure_ascii=False))]

        # ---- object_stats ----
        elif name == "object_stats":
            total = conn.execute("SELECT COUNT(*) FROM objects").fetchone()[0]
            by_kind = conn.execute("SELECT kind, COUNT(*) as cnt FROM objects GROUP BY kind").fetchall()
            by_src = conn.execute("SELECT src, COUNT(*) as cnt FROM objects GROUP BY src").fetchall()
            by_lib = conn.execute("SELECT lib, kind, COUNT(*) as cnt FROM objects GROUP BY lib, kind ORDER BY cnt DESC LIMIT 40").fetchall()
            analyses_cnt = conn.execute("SELECT COUNT(*) FROM object_analyses").fetchone()[0]
            deps_cnt = conn.execute("SELECT COUNT(*) FROM object_dependencies").fetchone()[0]
            comps_cnt = conn.execute("SELECT COUNT(*) FROM object_comparisons").fetchone()[0]
            return [TextContent(type="text", text=json.dumps({
                "total_objects": total,
                "by_kind": [dict(r) for r in by_kind],
                "by_src": [dict(r) for r in by_src],
                "by_lib": [dict(r) for r in by_lib],
                "analyses": analyses_cnt,
                "dependencies": deps_cnt,
                "comparisons": comps_cnt,
            }, ensure_ascii=False))]

        else:
            return [TextContent(type="text", text=json.dumps({"error": f"Неизвестный инструмент: {name}"}, ensure_ascii=False))]

    finally:
        conn.close()


async def main():
    async with stdio_server() as (read_stream, write_stream):
        init_options = server.create_initialization_options()
        await server.run(read_stream, write_stream, init_options)

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
