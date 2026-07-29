// Плагин: интеграция Claude Code как инструмента OpenCode
// Вызывает claude CLI (-p неинтерактивный режим) для PowerBuilder/SQL задач
// Требует: claude auth login (OAuth) или ANTHROPIC_API_KEY

export const ClaudeCodePlugin = async (ctx) => {
  return {
    tool: {
      claude_pb: {
        description: "Вызвать Claude Code для анализа/рефакторинга объекта PowerBuilder (.sr*)",
        args: {
          task: {
            description: "Что сделать: analyse (анализ), refactor (рефакторинг), compare (сравнение), generate (генерация кода)",
            type: "string",
            required: ["task"]
          },
          file: {
            description: "Путь к файлу .sr* для обработки",
            type: "string",
            required: ["file"]
          },
          context: {
            description: "Дополнительный контекст/инструкция для Claude",
            type: "string"
          }
        },
        async execute(args) {
          const { execSync } = await import("child_process");
          const prompt = buildPBPrompt(args.task, args.file, args.context);
          try {
            const result = execSync(`claude -p "${prompt.replace(/"/g, '\\"')}" --model sonnet --output-format text --add-dir "C:\\AIS\\AI\\Prod"`, {
              timeout: 120000,
              encoding: 'utf8',
              maxBuffer: 10 * 1024 * 1024
            });
            return result.stdout || result;
          } catch (e) {
            return `Ошибка Claude Code: ${e.stderr || e.message}`;
          }
        }
      },
      claude_sql: {
        description: "Вызвать Claude Code для анализа SQL (Sybase ASE хранимые процедуры)",
        args: {
          task: {
            description: "Что сделать: analyse (анализ), fix (исправить), explain (объяснить), review (code review)",
            type: "string",
            required: ["task"]
          },
          file: {
            description: "Путь к .sql файлу",
            type: "string",
            required: ["file"]
          },
          context: {
            description: "Дополнительный контекст",
            type: "string"
          }
        },
        async execute(args) {
          const { execSync } = await import("child_process");
          const prompt = buildSQLPrompt(args.task, args.file, args.context);
          try {
            const result = execSync(`claude -p "${prompt.replace(/"/g, '\\"')}" --model sonnet --output-format text`, {
              timeout: 120000,
              encoding: 'utf8',
              maxBuffer: 10 * 1024 * 1024
            });
            return result.stdout || result;
          } catch (e) {
            return `Ошибка Claude Code: ${e.stderr || e.message}`;
          }
        }
      }
    }
  }
}

function buildPBPrompt(task, file, context) {
  const prompts = {
    analyse: `Проанализируй объект PowerBuilder в файле ${file}. Опиши: 1) Назначение объекта 2) Ключевые функции/события 3) Зависимости 4) Потенциальные проблемы. ${context || ''}`,
    refactor: `Выполни рефакторинг объекта PowerBuilder в файле ${file}. ${context || 'Улучши читаемость, убери дублирование, оптимизируй SQL-запросы внутри PowerScript.'}`,
    compare: `Сравни объект PowerBuilder ${file} с эталонной версией. Найди отличия и опиши их влияние. ${context || ''}`,
    generate: `Сгенерируй код PowerBuilder для ${file} на основе требований: ${context || ''}`
  };
  return prompts[task] || `Обработай файл PowerBuilder ${file}. ${context || ''}`;
}

function buildSQLPrompt(task, file, context) {
  const prompts = {
    analyse: `Проанализируй SQL-процедуру (Sybase ASE 15.5) в файле ${file}. Опиши: 1) Что делает процедура 2) Используемые таблицы 3) План выполнения 4) Возможные оптимизации. ${context || ''}`,
    fix: `Исправь ошибки в SQL-процедуре Sybase ASE 15.5 в файле ${file}. ${context || 'Проверь синтаксис, корректность JOIN, обработку NULL.'}`,
    explain: `Объясни логику работы SQL-процедуры Sybase ASE в файле ${file}. ${context || 'Опиши пошагово алгоритм.'}`,
    review: `Выполни code review SQL-процедуры Sybase ASE 15.5 в файле ${file}. ${context || 'Проверь: именование, транзакции, блокировки, производительность.'}`
  };
  return prompts[task] || `Обработай SQL-файл Sybase ASE ${file}. ${context || ''}`;
}
