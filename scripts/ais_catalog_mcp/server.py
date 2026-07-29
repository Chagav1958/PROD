"""
MCP-сервер каталога AIS (SQLite + FTS5)
Каталог объектов PB/SQL, бизнес-правила, теги проектов.
"""
import sqlite3
import json
import os
import sys
from datetime import datetime
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "knowledge.db")
CATALOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "rules", "object_catalog.jsonl")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn

def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS knowledge (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            tags TEXT DEFAULT '',
            created_at TEXT NOT NULL
        )
    """)
    conn.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(
            text, tags, content=knowledge, content_rowid=id
        )
    """)
    conn.execute("""
        CREATE TRIGGER IF NOT EXISTS knowledge_ai AFTER INSERT ON knowledge BEGIN
            INSERT INTO knowledge_fts(rowid, text, tags) VALUES (new.id, new.text, new.tags);
        END
    """)
    conn.execute("""
        CREATE TRIGGER IF NOT EXISTS knowledge_ad AFTER DELETE ON knowledge BEGIN
            INSERT INTO knowledge_fts(knowledge_fts, rowid, text, tags) VALUES('delete', old.id, old.text, old.tags);
        END
    """)
    conn.execute("""
        CREATE TRIGGER IF NOT EXISTS knowledge_au AFTER UPDATE ON knowledge BEGIN
            INSERT INTO knowledge_fts(knowledge_fts, rowid, text, tags) VALUES('delete', old.id, old.text, old.tags);
            INSERT INTO knowledge_fts(rowid, text, tags) VALUES (new.id, new.text, new.tags);
        END
    """)
    
    # --- Таблицы каталога и бизнес-правил ---
    conn.execute("""
        CREATE TABLE IF NOT EXISTS object_metadata (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            src TEXT NOT NULL,
            obj_type TEXT,
            lib TEXT,
            file_path TEXT,
            tags TEXT DEFAULT '',
            tables TEXT,
            calls TEXT,
            sql_refs TEXT,
            pb_refs TEXT,
            srd_exprs TEXT,
            srd_dyn_sql TEXT,
            srd_valid TEXT,
            srd_masks TEXT,
            srd_computed TEXT,
            srd_filters TEXT,
            linked_tables TEXT,
            created_at TEXT NOT NULL
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_obj_name ON object_metadata(name)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_obj_kind_src ON object_metadata(kind, src)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_obj_tags ON object_metadata(tags)")
    
    conn.execute("""
        CREATE TABLE IF NOT EXISTS business_rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            process_name TEXT NOT NULL,
            target_table TEXT NOT NULL,
            condition TEXT,
            source_tables TEXT,
            description TEXT,
            related_pb_objects TEXT,
            yaml_rule TEXT,
            tags TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_br_process ON business_rules(process_name)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_br_table ON business_rules(target_table)")
    
    conn.execute("""
        CREATE TABLE IF NOT EXISTS project_tags (
            object_name TEXT NOT NULL,
            project_name TEXT NOT NULL,
            tag TEXT NOT NULL,
            PRIMARY KEY (object_name, project_name, tag)
        )
    """)
    
    conn.commit()
    conn.close()

def load_catalog_to_db():
    """Загружает JSONL-каталог в object_metadata (если пусто)."""
    if not os.path.exists(CATALOG_PATH):
        return
    conn = get_db()
    count = conn.execute("SELECT COUNT(*) FROM object_metadata").fetchone()[0]
    if count > 0:
        conn.close()
        return
    print(f"Загрузка каталога из {CATALOG_PATH}...")
    inserted = 0
    with open(CATALOG_PATH, 'r', encoding='utf-8-sig') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                conn.execute("""
                    INSERT INTO object_metadata (
                        name, kind, src, obj_type, lib, file_path,
                        tables, calls, sql_refs, pb_refs,
                        srd_exprs, srd_dyn_sql, srd_valid, srd_masks,
                        srd_computed, srd_filters, linked_tables,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    obj.get('name'),
                    obj.get('kind'),
                    obj.get('src'),
                    obj.get('objType'),
                    obj.get('lib'),
                    obj.get('file'),
                    json.dumps(obj.get('tables', [])),
                    json.dumps(obj.get('calls', [])),
                    json.dumps(obj.get('sqlRefs', [])),
                    json.dumps(obj.get('pbRefs', [])),
                    json.dumps(obj.get('srdExprs', [])),
                    json.dumps(obj.get('srdDynSQL', [])),
                    json.dumps(obj.get('srdValid', [])),
                    json.dumps(obj.get('srdMasks', [])),
                    json.dumps(obj.get('srdComputed', [])),
                    json.dumps(obj.get('srdFilters', [])),
                    json.dumps(obj.get('linkedTables', [])),
                    datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                ))
                inserted += 1
            except Exception as e:
                print(f"Ошибка загрузки объекта: {e}")
    conn.commit()
    conn.close()
    print(f"Загружено объектов в БД: {inserted}")

def parse_json_field(value):
    if not value:
        return []
    try:
        return json.loads(value)
    except:
        return []

def parse_obj_row(row):
    """Парсит JSON-поля объекта."""
    obj = dict(row)
    for field in ['tables', 'calls', 'sql_refs', 'pb_refs', 'srd_exprs', 'srd_dyn_sql', 'srd_valid', 'srd_masks', 'srd_computed', 'srd_filters', 'linked_tables']:
        if obj.get(field):
            try:
                obj[field] = json.loads(obj[field])
            except:
                obj[field] = []
    return obj

init_db()
load_catalog_to_db()

server = Server("ais-catalog-mcp")

@server.list_tools()
async def handle_list_tools():
    return [
        Tool(
            name="get_object_metadata",
            description="Возвращает структуру PB/SQL объекта, его зависимости и теги (AIS_CORE, SHARED_AIS, GLOBAL_DB).",
            inputSchema={
                "type": "object",
                "properties": {
                    "object_name": {"type": "string", "description": "Имя объекта (точное совпадение)"},
                    "src": {"type": "string", "description": "Источник: 'current' или 'main' (опционально)"},
                    "kind": {"type": "string", "description": "Тип: 'PB' или 'SQL' (опционально)"}
                },
                "required": ["object_name"]
            }
        ),
        Tool(
            name="get_business_rules",
            description="Возвращает зафиксированные правила дополнения данных для процесса или таблицы.",
            inputSchema={
                "type": "object",
                "properties": {
                    "process_or_table": {"type": "string", "description": "Название процесса или целевой таблицы"}
                },
                "required": ["process_or_table"]
            }
        ),
        Tool(
            name="find_dependencies",
            description="Возвращает граф вызовов: какие окна вызывают какие функции, какие функции дергают какие SQL. Поддерживает глубину обхода.",
            inputSchema={
                "type": "object",
                "properties": {
                    "object_name": {"type": "string", "description": "Имя стартового объекта"},
                    "depth": {"type": "integer", "description": "Глубина обхода графа (по умолчанию 2)", "default": 2},
                    "direction": {"type": "string", "description": "'forward' (кто вызываемые) или 'reverse' (кто вызывает) или 'both'", "default": "forward"}
                },
                "required": ["object_name"]
            }
        ),
        Tool(
            name="search_codebase",
            description="Семантический поиск по коду (через каталог + FTS knowledge), если в БД нет готового ответа.",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Поисковый запрос (имя таблицы, процедуры, бизнес-термин)"},
                    "limit": {"type": "integer", "description": "Максимум результатов", "default": 10}
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="check_cross_project_impact",
            description="Проверяет, используется ли объект в других проектах (через project_tags). Предупреждает о SHARED_AIS/GLOBAL_DB.",
            inputSchema={
                "type": "object",
                "properties": {
                    "object_name": {"type": "string", "description": "Имя таблицы или объекта"},
                    "project": {"type": "string", "description": "Текущий проект (напр. 'AIS')"}
                },
                "required": ["object_name", "project"]
            }
        ),
        Tool(
            name="add_business_rule",
            description="Добавить/обновить бизнес-правило (для Этапа 2). Формат YAML для LLM.",
            inputSchema={
                "type": "object",
                "properties": {
                    "process_name": {"type": "string", "description": "Название процесса"},
                    "target_table": {"type": "string", "description": "Целевая таблица"},
                    "condition": {"type": "string", "description": "Условие (триггер/характеристика)"},
                    "source_tables": {"type": "string", "description": "JSON массив дополняющих таблиц"},
                    "description": {"type": "string", "description": "Описание логики"},
                    "related_pb_objects": {"type": "string", "description": "JSON массив связанных PB-объектов"},
                    "yaml_rule": {"type": "string", "description": "Правило в YAML для LLM"},
                    "tags": {"type": "string", "description": "Теги для поиска"}
                },
                "required": ["process_name", "target_table"]
            }
        ),
        Tool(
            name="tag_object",
            description="Проставить тег проекта объекту (AIS_CORE, SHARED_AIS, GLOBAL_DB).",
            inputSchema={
                "type": "object",
                "properties": {
                    "object_name": {"type": "string", "description": "Имя объекта"},
                    "project": {"type": "string", "description": "Проект (AIS, Buhgalteria, CRM...)"},
                    "tag": {"type": "string", "description": "Тег: AIS_CORE, SHARED_AIS, GLOBAL_DB"}
                },
                "required": ["object_name", "project", "tag"]
            }
        ),
        Tool(
            name="save_knowledge",
            description="Сохранить знание/опыт в базу.",
            inputSchema={
                "type": "object",
                "properties": {
                    "text": {"type": "string", "description": "Текст знания"},
                    "tags": {"type": "string", "description": "Теги через запятую"}
                },
                "required": ["text"]
            }
        ),
        Tool(
            name="search_knowledge",
            description="Найти знания по запросу.",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Поисковый запрос"},
                    "limit": {"type": "integer", "description": "Максимум результатов", "default": 5}
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="knowledge_stats",
            description="Статистика базы знаний.",
            inputSchema={"type": "object", "properties": {}, "required": []}
        )
    ]

@server.call_tool()
async def handle_call_tool(name: str, arguments: dict):
    conn = get_db()
    try:
        if name == "get_object_metadata":
            object_name = arguments.get("object_name")
            src = arguments.get("src")
            kind = arguments.get("kind")
            query = "SELECT * FROM object_metadata WHERE name = ?"
            params = [object_name]
            if src:
                query += " AND src = ?"
                params.append(src)
            if kind:
                query += " AND kind = ?"
                params.append(kind)
            row = conn.execute(query, params).fetchone()
            if not row:
                return [TextContent(type="text", text=json.dumps({"error": "Объект не найден"}, ensure_ascii=False))]
            obj = parse_obj_row(row)
            return [TextContent(type="text", text=json.dumps(obj, ensure_ascii=False))]

        elif name == "get_business_rules":
            process_or_table = arguments.get("process_or_table")
            rows = conn.execute(
                """SELECT * FROM business_rules 
                   WHERE process_name LIKE ? OR target_table LIKE ?
                   ORDER BY updated_at DESC""",
                (f"%{process_or_table}%", f"%{process_or_table}%")
            ).fetchall()
            results = []
            for r in rows:
                rule = dict(r)
                for field in ['source_tables', 'related_pb_objects']:
                    if rule.get(field):
                        try: rule[field] = json.loads(rule[field])
                        except: rule[field] = []
                results.append(rule)
            return [TextContent(type="text", text=json.dumps({
                "query": process_or_table, "count": len(results), "rules": results
            }, ensure_ascii=False))]

        elif name == "find_dependencies":
            object_name = arguments.get("object_name")
            depth = arguments.get("depth", 2)
            direction = arguments.get("direction", "forward")
            
            visited = set()
            results = []
            
            def get_forward_deps(obj_name, current_depth):
                if current_depth > depth or obj_name in visited:
                    return []
                visited.add(obj_name)
                res = []
                row = conn.execute("SELECT calls, sql_refs, pb_refs FROM object_metadata WHERE name = ?", (obj_name,)).fetchone()
                if row:
                    obj = dict(row)
                    for field in ['calls', 'sql_refs', 'pb_refs']:
                        items = parse_json_field(obj.get(field))
                        for item in items:
                            if item not in visited:
                                res.append({"object": item, "depth": 1, "direction": "forward"})
                                if depth > 1:
                                    # Recursive would need more complex logic, skip for now
                                    pass
                return res
            
            def get_reverse_deps(obj_name, current_depth):
                if current_depth > depth or obj_name in visited:
                    return []
                visited.add(obj_name)
                res = []
                rows = conn.execute(
                    "SELECT name, kind, calls, sql_refs, pb_refs FROM object_metadata WHERE calls LIKE ? OR sql_refs LIKE ? OR pb_refs LIKE ?",
                    (f'%"{object_name}"%', f'%"{object_name}"%', f'%"{object_name}"%')
                ).fetchall()
                for row in rows:
                    obj = dict(row)
                    res.append({"object": parse_obj_row(row), "depth": 1, "direction": "reverse"})
                return res
            
            results = []
            if direction in ('forward', 'both'):
                results.extend(get_forward_deps(object_name, 1))
            if direction in ('reverse', 'both'):
                results.extend(get_reverse_deps(object_name, 1))
            
            return [TextContent(type="text", text=json.dumps({
                "start": object_name, "depth": depth, "direction": direction,
                "count": len(results), "graph": results
            }, ensure_ascii=False))]

        elif name == "search_codebase":
            query = arguments.get("query", "")
            limit = arguments.get("limit", 10)
            rows = conn.execute(
                """SELECT name, kind, src, obj_type, lib, tags, tables, calls, sql_refs, pb_refs
                   FROM object_metadata
                   WHERE name LIKE ? OR lib LIKE ? OR tags LIKE ?
                   LIMIT ?""",
                (f"%{query}%", f"%{query}%", f"%{query}%", limit)
            ).fetchall()
            catalog_results = []
            for r in rows:
                obj = parse_obj_row(r)
                catalog_results.append(obj)
            try:
                krows = conn.execute(
                    """SELECT k.id, k.text, k.tags, k.created_at
                       FROM knowledge k JOIN knowledge_fts fts ON k.id = fts.rowid
                       WHERE knowledge_fts MATCH ? LIMIT ?""",
                    (query, 5)
                ).fetchall()
                knowledge_results = [dict(r) for r in krows]
            except:
                knowledge_results = []
            return [TextContent(type="text", text=json.dumps({
                "query": query,
                "catalog": catalog_results,
                "knowledge": knowledge_results
            }, ensure_ascii=False))]

        elif name == "check_cross_project_impact":
            object_name = arguments.get("object_name", "")
            project = arguments.get("project", "")
            rows = conn.execute(
                "SELECT project_name, tag FROM project_tags WHERE object_name = ?",
                (object_name,)
            ).fetchall()
            if not rows:
                return [TextContent(type="text", text=json.dumps({
                    "object": object_name, "project": project,
                    "status": "UNKNOWN", "message": "Теги не найдены. Используйте tag_object для разметки."
                }, ensure_ascii=False))]
            
            shared = [r for r in rows if r['tag'] in ('SHARED_AIS', 'GLOBAL_DB') and r['project_name'] != project]
            core = [r for r in rows if r['tag'] == 'AIS_CORE' and r['project_name'] != project]
            
            warnings = []
            if shared:
                warnings.append(f"ВНИМАНИЕ: Объект используется в других проектах: {', '.join(set(r['project_name'] for r in shared))} (теги: SHARED_AIS/GLOBAL_DB)")
            if core:
                warnings.append(f"ИНФО: Объект является AIS_CORE в проектах: {', '.join(set(r['project_name'] for r in core))}")
            
            return [TextContent(type="text", text=json.dumps({
                "object": object_name, "current_project": project,
                "tags": [dict(r) for r in rows],
                "warnings": warnings,
                "safe_to_modify": len(warnings) == 0
            }, ensure_ascii=False))]

        elif name == "add_business_rule":
            pn = arguments.get("process_name")
            tt = arguments.get("target_table")
            cond = arguments.get("condition", "")
            st = arguments.get("source_tables", "[]")
            desc = arguments.get("description", "")
            rpo = arguments.get("related_pb_objects", "[]")
            yaml_r = arguments.get("yaml_rule", "")
            tags = arguments.get("tags", "")
            now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            existing = conn.execute("SELECT id FROM business_rules WHERE process_name = ? AND target_table = ?", (pn, tt)).fetchone()
            if existing:
                conn.execute("""UPDATE business_rules SET
                    condition=?, source_tables=?, description=?, related_pb_objects=?, yaml_rule=?, tags=?, updated_at=?
                    WHERE id=?""", (arguments.get("condition", ""), arguments.get("source_tables", "[]"), desc, arguments.get("related_pb_objects", "[]"), arguments.get("yaml_rule", ""), arguments.get("tags", ""), now, existing['id']))
            else:
                conn.execute("""INSERT INTO business_rules
                    (process_name, target_table, condition, source_tables, description, related_pb_objects, yaml_rule, tags, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (pn, tt, cond, st, arguments.get("description", ""), arguments.get("related_pb_objects", "[]"), arguments.get("yaml_rule", ""), tags, now, now))
            conn.commit()
            return [TextContent(type="text", text=json.dumps({"status": "ok", "message": "Бизнес-правило сохранено"}, ensure_ascii=False))]

        elif name == "tag_object":
            obj = arguments.get("object_name")
            proj = arguments.get("project")
            tag = arguments.get("tag")
            if tag not in ('AIS_CORE', 'SHARED_AIS', 'GLOBAL_DB'):
                return [TextContent(type="text", text=json.dumps({"error": f"Недопустимый тег: {tag}. Допустимы: AIS_CORE, SHARED_AIS, GLOBAL_DB"}, ensure_ascii=False))]
            conn.execute("INSERT OR REPLACE INTO project_tags (object_name, project_name, tag) VALUES (?, ?, ?)", (obj, proj, tag))
            conn.execute("UPDATE object_metadata SET tags = ? WHERE name = ?", (tag, obj))
            conn.commit()
            return [TextContent(type="text", text=json.dumps({"status": "ok", "message": f"Тег {tag} установлен для {obj} в проекте {proj}"}, ensure_ascii=False))]

        elif name == "save_knowledge":
            text = arguments.get("text", "")
            tags = arguments.get("tags", "")
            now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            cursor = conn.execute("INSERT INTO knowledge (text, tags, created_at) VALUES (?, ?, ?)", (text, tags, now))
            conn.commit()
            new_id = cursor.lastrowid
            return [TextContent(type="text", text=json.dumps({
                "status": "ok", "id": new_id, "message": f"Знание #{new_id} сохранено"
            }, ensure_ascii=False))]

        elif name == "search_knowledge":
            query = arguments.get("query", "")
            limit = arguments.get("limit", 5)
            try:
                rows = conn.execute(
                    """SELECT k.id, k.text, k.tags, k.created_at
                       FROM knowledge k
                       JOIN knowledge_fts fts ON k.id = fts.rowid
                       WHERE knowledge_fts MATCH ?
                       ORDER BY rank LIMIT ?""",
                    (query, limit)
                ).fetchall()
            except:
                rows = conn.execute(
                    """SELECT id, text, tags, created_at FROM knowledge
                       WHERE text LIKE ? OR tags LIKE ?
                       ORDER BY created_at DESC LIMIT ?""",
                    (f"%{query}%", f"%{query}%", limit)
                ).fetchall()
            results = [dict(r) for r in rows]
            return [TextContent(type="text", text=json.dumps({
                "query": query, "count": len(results), "results": results
            }, ensure_ascii=False))]

        elif name == "knowledge_stats":
            total = conn.execute("SELECT COUNT(*) FROM object_metadata").fetchone()[0]
            br = conn.execute("SELECT COUNT(*) FROM business_rules").fetchone()[0]
            kg = conn.execute("SELECT COUNT(*) FROM knowledge").fetchone()[0]
            return [TextContent(type="text", text=json.dumps({
                "objects": total, "business_rules": br, "knowledge": kg
            }, ensure_ascii=False))]

        else:
            return [TextContent(type="text", text=json.dumps({"error": f"Неизвестный инструмент: {name}"}))]
    finally:
        conn.close()

async def main():
    async with stdio_server() as (read_stream, write_stream):
        init_options = server.create_initialization_options()
        await server.run(read_stream, write_stream, init_options)

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())