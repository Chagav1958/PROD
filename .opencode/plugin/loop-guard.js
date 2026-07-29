// Плагин: LoopGuard — обнаружение и предотвращение зацикливания
// Отслеживает повторяющиеся паттерны в ответах ассистента
// и при обнаружении цикла возвращает system-сообщение с предупреждением
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..', '..');

const tempDir = path.join(projectRoot, 'temp');
const historyFile = path.join(tempDir, 'loop_history.json');
const triggerFile = path.join(tempDir, 'loop_guard.trigger');
const warningFile = path.join(tempDir, 'loop_warning.json');

if (!fs.existsSync(tempDir)) {
  fs.mkdirSync(tempDir, { recursive: true });
}

// Регулярка для поиска путей файлов (Windows + относительные)
const filePathRegex = /[A-Za-z]:\\(?:[^\\\s]+\\)*[^\\\s:*?"<>|]+(?:\.[a-zA-Z0-9]+)?|\b(?:bin|scripts|config|docs|temp|tools|rules|archives)\\[^\s:]+/gi;

// Загружаем историю из файла (межсессионная персистентность)
let actionHistory = [];
try {
  if (fs.existsSync(historyFile)) {
    actionHistory = JSON.parse(fs.readFileSync(historyFile, 'utf-8'));
  }
} catch (e) { /* silent */ }

function saveHistory() {
  try {
    fs.writeFileSync(historyFile, JSON.stringify(actionHistory.slice(-25)), 'utf-8');
  } catch (e) { /* silent */ }
}

function extractFilePaths(text) {
  const matches = text.match(filePathRegex) || [];
  // Нормализуем: нижний регистр, убираем слеши в конце
  return [...new Set(matches.map(m => m.toLowerCase().replace(/[\\/]+$/g, '')))];
}

function extractToolNames(text) {
  const tools = [];
  if (/\b(?:edit|Edit)\b/.test(text)) tools.push('edit');
  if (/\bbash\b/.test(text)) tools.push('bash');
  if (/\bread\b/.test(text)) tools.push('read');
  if (/\bgrep\b/.test(text) || /\bglob\b/.test(text)) tools.push('search');
  if (/\bwrite\b/.test(text)) tools.push('write');
  return tools;
}

function detectLoop(history) {
  if (history.length < 6) return null;
  const recent = history.slice(-8);

  // 1. Один и тот же файл редактируется 3+ раз
  const allFiles = recent.flatMap(a => a.files);
  const fileCounts = {};
  allFiles.forEach(f => { fileCounts[f] = (fileCounts[f] || 0) + 1; });
  const topFiles = Object.entries(fileCounts)
    .filter(([_, count]) => count >= 3)
    .sort((a, b) => b[1] - a[1]);

  if (topFiles.length > 0) {
    const [file, count] = topFiles[0];
    return {
      type: 'file_edit_loop',
      detail: file,
      count,
      message: `Файл "${file}" изменён/упомянут ${count} раз(а) за ${recent.length} последних действий`
    };
  }

  // 2. Чередование edit→bash→edit→bash (паттерн "фикс-тест")
  const toolSeqs = recent.map(a => a.tools.join(',')).filter(t => t);
  if (toolSeqs.length >= 4) {
    let alternationCount = 0;
    for (let i = 1; i < toolSeqs.length; i++) {
      if ((toolSeqs[i-1].includes('edit') && toolSeqs[i].includes('bash')) ||
          (toolSeqs[i-1].includes('bash') && toolSeqs[i].includes('edit'))) {
        alternationCount++;
      }
    }
    if (alternationCount >= 3) {
      return {
        type: 'tool_alternation_loop',
        detail: 'edit↔bash',
        count: alternationCount,
        message: `Чередование edit↔bash обнаружено ${alternationCount} раз(а) за ${recent.length} действий`
      };
    }
  }

  // 3. Один и тот же инструмент вызывается 4+ раз подряд без других
  const lastTools = recent.slice(-4).map(a => a.tools.join(',')).filter(t => t);
  if (lastTools.length === 4) {
    const unique = [...new Set(lastTools)];
    if (unique.length === 1 && unique[0] !== '') {
      return {
        type: 'single_tool_loop',
        detail: unique[0],
        count: 4,
        message: `Инструмент "${unique[0]}" вызван 4+ раз(а) подряд`
      };
    }
  }

  return null;
}

export default async () => {
  // Очищаем триггер при старте
  try { fs.unlinkSync(triggerFile); } catch (e) { /* silent */ }

  return {
    'chat.message': async (input) => {
      if (!input) return;
      const role = input.role || '';
      const content = input.content || '';

      // Сбрасываем триггер при пользовательском сообщении
      if (role === 'user') {
        try { fs.unlinkSync(triggerFile); } catch (e) { /* silent */ }
        return;
      }

      // Анализируем ответ ассистента
      if (role === 'assistant' && content.trim()) {
        const files = extractFilePaths(content);
        const tools = extractToolNames(content);

        actionHistory.push({
          ts: Date.now(),
          len: content.length,
          files,
          tools
        });

        if (actionHistory.length > 25) {
          actionHistory = actionHistory.slice(-25);
        }

        saveHistory();

        // Проверяем на цикл, если накопили достаточно данных
        if (actionHistory.length >= 6) {
          const loop = detectLoop(actionHistory);
          if (loop) {
            const warning = {
              detected: new Date().toISOString(),
              type: loop.type,
              detail: loop.detail,
              count: loop.count,
              message: loop.message
            };

            try {
              fs.writeFileSync(warningFile, JSON.stringify(warning, null, 2), 'utf-8');
              fs.writeFileSync(triggerFile, loop.message, 'utf-8');
            } catch (e) { /* silent */ }

            // Возвращаем system-предупреждение ассистенту
            return {
              role: 'system',
              content: '⚠️ LoopGuard: Обнаружен цикл!\n' +
                loop.message + '\n' +
                'Проанализируйте корневую причину и попробуйте ДРУГОЙ подход. ' +
                'Не повторяйте те же действия. Если нужно — остановитесь и спросите пользователя.'
            };
          }
        }
      }
    },
  };
};
