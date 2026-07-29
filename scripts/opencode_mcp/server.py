"""
MCP-сервер операционных знаний OpenCode (SQLite + FTS5)
Только личные операционные знания: багфиксы, решения, договорённости.
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
    conn.commit()
    conn.close()

init_db()

server = Server("opencode-mcp")

@server.list_tools()
async def handle_list_tools():
    return [
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
            name="list_recent",
            description="Показать последние сохранённые знания.",
            inputSchema={
                "type": "object",
                "properties": {
                    "limit": {"type": "integer", "description": "Количество", "default": 10}
                },
                "required": []
            }
        ),
        Tool(
            name="get_knowledge",
            description="Получить запись по ID.",
            inputSchema={
                "type": "object",
                "properties": {
                    "id": {"type": "integer", "description": "ID записи"}
                },
                "required": ["id"]
            }
        ),
        Tool(
            name="delete_knowledge",
            description="Удалить запись по ID.",
            inputSchema={
                "type": "object",
                "properties": {
                    "id": {"type": "integer", "description": "ID записи для удаления"}
                },
                "required": ["id"]
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
        if name == "save_knowledge":
            text = arguments.get("text", "")
            tags = arguments.get("tags", "")
            now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            cursor = conn.execute("INSERT INTO knowledge (text, tags, created_at) VALUES (?, ?, ?)", (text, tags, now))
            conn.commit()
            return [TextContent(type="text", text=json.dumps({"status": "ok", "id": cursor.lastrowid, "message": "Знание сохранено"}, ensure_ascii=False))]

        elif name == "search_knowledge":
            query = arguments.get("query", "")
            limit = arguments.get("limit", 5)
            try:
                rows = conn.execute(
                    """SELECT k.id, k.text, k.tags, k.created_at
                       FROM knowledge k JOIN knowledge_fts fts ON k.id = fts.rowid
                       WHERE knowledge_fts MATCH ? ORDER BY rank LIMIT ?""",
                    (query, limit)
                ).fetchall()
            except:
                rows = conn.execute(
                    "SELECT id, text, tags, created_at FROM knowledge WHERE text LIKE ? OR tags LIKE ? ORDER BY created_at DESC LIMIT ?",
                    (f"%{query}%", f"%{query}%", limit)
                ).fetchall()
            return [TextContent(type="text", text=json.dumps({"query": query, "count": len(rows), "results": [dict(r) for r in rows]}, ensure_ascii=False))]

        elif name == "list_recent":
            limit = arguments.get("limit", 10)
            rows = conn.execute("SELECT id, text, tags, created_at FROM knowledge ORDER BY created_at DESC LIMIT ?", (limit,)).fetchall()
            return [TextContent(type="text", text=json.dumps({"count": len(rows), "results": [dict(r) for r in rows]}, ensure_ascii=False))]

        elif name == "get_knowledge":
            id_ = arguments["id"]
            row = conn.execute("SELECT id, text, tags, created_at FROM knowledge WHERE id = ?", (id_,)).fetchone()
            if row:
                return [TextContent(type="text", text=json.dumps(dict(row), ensure_ascii=False))]
            return [TextContent(type="text", text=json.dumps({"error": "Не найдено"}, ensure_ascii=False))]

        elif name == "delete_knowledge":
            id_ = arguments["id"]
            conn.execute("DELETE FROM knowledge WHERE id = ?", (id_,))
            conn.commit()
            return [TextContent(type="text", text=json.dumps({"status": "ok", "message": f"Запись #{id_} удалена"}, ensure_ascii=False))]

        elif name == "knowledge_stats":
            total = conn.execute("SELECT COUNT(*) FROM knowledge").fetchone()[0]
            latest = conn.execute("SELECT created_at FROM knowledge ORDER BY created_at DESC LIMIT 1").fetchone()
            return [TextContent(type="text", text=json.dumps({"total": total, "latest": latest["created_at"] if latest else None, "db_path": DB_PATH}, ensure_ascii=False))]

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