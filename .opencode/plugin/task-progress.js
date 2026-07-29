// Плагин: прогресс задач при промпте
// При получении промпта: РР → Show-TaskProgressDialog → промпт
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..', '..');
const triggerFile = path.join(projectRoot, 'temp', 'show_task_dialog.trigger');

// Убедимся что temp существует
const tempDir = path.join(projectRoot, 'temp');
if (!fs.existsSync(tempDir)) {
  fs.mkdirSync(tempDir, { recursive: true });
}

export default async () => {
  return {
    'chat.message': async (input) => {
      if (!input) return;
      const role = input.role || '';
      const content = input.content || '';
      if (role === 'user' && content.trim()) {
        const trimmed = content.trim();
        // Пропускаем системные команды
        if (trimmed.startsWith('/') || trimmed === 'РР' || trimmed === 'СОХР' || trimmed === 'СОКР' || trimmed === 'ЦИКЛ' || trimmed.startsWith('FIX') || trimmed.startsWith('EDIT') || trimmed.startsWith('НОМ')) {
          return;
        }
        // Создаём триггер для GUI показать диалог прогресса
        try {
          fs.writeFileSync(triggerFile, new Date().toISOString(), 'utf-8');
        } catch (e) {
          // silent
        }
      }
    },
  };
};
