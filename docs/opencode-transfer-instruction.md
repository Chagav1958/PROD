# Инструкция переноса OpenCode на другой ПК

## 1. Установка OpenCode

### Windows (рекомендуется WSL, но можно и natively)

```bash
# Через npm (нужен Node.js 18+)
npm install -g opencode-ai

# Или через Scoop
scoop install opencode

# Или через Chocolatey
choco install opencode
```

### Проверка установки

```bash
opencode --version
```

---

## 2. Бесплатные LLM провайдеры (OpenCode Zen)

OpenCode Zen предоставляет бесплатные модели (rotating, time-limited):

| Модель | Model ID | Контекст | Описание |
|--------|----------|----------|----------|
| DeepSeek V4 Flash | `zen/deepseek-v4-flash-free` | 1M | Быстрая, большая |
| MiMo V2.5 | `zen/mimo-v2.5-free` | 1M | Быстрая |
| Nemotron 3 Ultra | `zen/nemotron-3-ultra-free` | 1M | Мощная |
| Hy3 Preview | `zen/hy3-preview-free` | 256K | Preview |
| North Mini Code | `zen/north-mini-code-free` | 256K | Кодинг |
| Big Pickle | `zen/big-pickle` | N/A | Stealth |

### Настройка OpenCode Zen

1. Зарегистрируйтесь на https://opencode.ai/auth
2. Добавьте биллинг (для бесплатных моделей ключ всё равно нужен)
3. Скопируйте API key
4. В OpenCode TUI: `/connect` → выберите "OpenCode Zen" → вставьте ключ
5. `/models` — увидите список доступных моделей

### Конфигурация в opencode.jsonc

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "zen/deepseek-v4-flash-free",
  "small_model": "zen/mimo-v2.5-free",
  "provider": {
    "opencode": {
      "name": "OpenCode Zen (бесплатные)",
      "whitelist": [
        "deepseek-v4-flash-free",
        "mimo-v2.5-free",
        "nemotron-3-ultra-free",
        "hy3-preview-free",
        "north-mini-code-free",
        "big-pickle"
      ]
    }
  }
}
```

> **Примечание:** Бесплатные модели ротируются — иногда могут быть недоступны.
> Для стабильной работы используйте `opencode-go` ($10/мес) или `routerai`.

---

## 3. MCP серверы

### 3.1 rules-mcp (правила проекта)

**Зависимости:**
- Python 3.11+
- fastmcp>=3.0.0

**Установка:**

```bash
# Клонировать/скопировать папку rules-mcp
# Создать venv
cd C:\AIS\AI\rules-mcp
python -m venv venv
venv\Scripts\activate
pip install fastmcp>=3.0.0
```

**Структура:**
```
rules-mcp/
├── pyproject.toml
├── run.py
└── rules_mcp/
    └── server.py
```

**Запуск:**
```bash
python C:\AIS\AI\rules-mcp\run.py
```

**Переменные окружения:**
- `AIS_PROD_ROOT` — путь к корню проекта (default: `C:\AIS\AI\Prod`)
- `AIS_RULES_ROOT` — путь к rules-mcp (default: `C:\AIS\AI\rules-mcp`)

### 3.2 knowledge (база знаний)

**Зависимости:**
- Python 3.12+
- mcp>=1.0.0

**Установка:**

```bash
cd C:\AIS\AI\Prod\scripts\knowledge_mcp
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

**Структура:**
```
knowledge_mcp/
├── .venv/
├── knowledge.db          # БД (переносить с собой!)
├── lib/
├── requirements.txt
├── run_server.bat
└── server.py
```

**Запуск:**
```bash
python -u C:\AIS\AI\Prod\scripts\knowledge_mcp\server.py
```

**Важно:** Файл `knowledge.db` содержит все накопленные знания. Переносите его на новый ПК!

---

## 4. Конфигурация opencode.jsonc

### Проектная конфигурация (`C:\AIS\AI\Prod\opencode.jsonc`)

Копируйте весь файл. Он содержит:
- Провайдеры (routerai, anthropic, openai, deepseek, yandex)
- MCP серверы (atlassian, sybase-docs, rules-mcp, knowledge)
- Плагины

### Пользовательская конфигурация (`~/.config/opencode/opencode.jsonc`)

Содержит:
- Ollama (локальные модели)
- Базовые настройки

### ВАЖНО: Формат MCP в opencode.jsonc

OpenCode использует ключ `mcp`, а **НЕ** `mcpServers` (это формат Claude Desktop).

**Правильно:**
```json
{
  "mcp": {
    "rules-mcp": { ... },
    "knowledge": { ... }
  }
}
```

**НЕПРАВИЛЬНО (вызовет ConfigInvalidError):**
```json
{
  "mcpServers": {
    "rules-mcp": { ... }
  }
}
```

Если при запуске ошибка `Unrecognized key: mcpServers` — замените `mcpServers` на `mcp`.

### Ключевые файлы для копирования

```
C:\AIS\AI\Prod\
├── opencode.jsonc                    # Проектная конфигурация
├── AGENTS.md                         # Правила проекта
├── .opencode/                        # Правила и плагины
│   ├── *.mdc                         # Правила (автозагрузка)
│   └── plugins/                      # Плагины
├── rules/                            # Сокращения, changelog
│   ├── abbreviations.md
│   └── changelog.md
├── scripts\
│   └── knowledge_mcp\                # MCP knowledge
│       ├── server.py
│       ├── knowledge.db              # ← ВАЖНО: переносить!
│       └── requirements.txt
├── sybase-docs-mcp\                  # MCP Sybase docs
└── rules-mcp\                        # MCP rules
    ├── run.py
    └── rules_mcp\server.py
```

---

## 5. Пошаговый перенос

### На старом ПК

1. Убедитесь, что все MCP серверы остановлены
2. Скопируйте всю папку `C:\AIS\AI\Prod\` (или её ключевые части)
3. Скопируйте `C:\AIS\AI\rules-mcp\`
4. Скопируйте `C:\Users\vchaga\.config\opencode\`
5. Экспортируйте API ключи (или запомните их)

### На новом ПК

1. Установите Python 3.12+ и Node.js 18+
2. Установите OpenCode: `npm install -g opencode-ai`
3. Скопируйте проект в `C:\AIS\AI\Prod\`
4. Создайте venv для MCP серверов:
   ```bash
   # rules-mcp
   cd C:\AIS\AI\rules-mcp
   python -m venv venv
   venv\Scripts\activate
   pip install fastmcp>=3.0.0

   # knowledge
   cd C:\AIS\AI\Prod\scripts\knowledge_mcp
   python -m venv .venv
   .venv\Scripts\activate
   pip install -r requirements.txt

   # sybase-docs-mcp (если нужен)
   cd C:\AIS\AI\sybase-docs-mcp
   python -m venv venv
   venv\Scripts\activate
   pip install -e .
   ```
5. Настройте провайдеры: `/connect` → OpenCode Zen → вставьте ключ
6. Проверьте: `/models` — увидите бесплатные модели
7. Запустите OpenCode в папке проекта: `cd C:\AIS\AI\Prod && opencode`

---

## 6. Альтернатива: Ollama (полностью локально, бесплатно)

Если не хотите использовать облачные API:

```bash
# Установите Ollama: https://ollama.com
ollama pull qwen2.5-coder:32b
ollama pull qwen2.5-coder:14b
ollama pull deepseek-coder-v2:16b
```

Конфигурация в `~/.config/opencode/opencode.jsonc`:
```json
{
  "model": "ollama/qwen2.5-coder:32b",
  "small_model": "ollama/qwen2.5-coder:7b",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen2.5-coder:32b": {
          "name": "Qwen 2.5 Coder 32B (local)",
          "limit": { "context": 32768, "output": 8192 }
        }
      }
    }
  }
}
```

> **Требуется:** GPU с 16+ GB VRAM для 32B моделей.

---

## 7. Проверка работы

1. Запустите OpenCode: `opencode`
2. Проверьте MCP: в чате спросите "покажи сокращение ДО"
3. Проверьте知识: "найди в базе знаний исправление бага"
4. Проверьте модель: `/models` — выберите бесплатную модель
5. Протестируйте: "создай простой SQL запрос"

---

## Частые проблемы

| Проблема | Решение |
|----------|---------|
| MCP не загружается | Проверьте путь к Python в `opencode.jsonc` → `command[0]` |
| Нет бесплатных моделей | Зарегистрируйтесь на opencode.ai/auth, добавьте биллинг |
| Ollama не отвечает | `ollama serve` → проверьте http://localhost:11434 |
| Кракозябры в выводе | PowerShell 5.1: не используйте `-NoProfile` |
| Python 3.12 не найден | Установите с https://python.org, добавьте в PATH |
