// Плагин: сохранение пользовательских промптов через кастомный инструмент
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { tool } from '@opencode-ai/plugin';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..', '..');

const archiveDir = path.join(projectRoot, 'archives', 'prompts');
const archiveFile = path.join(archiveDir, 'prompts_archive.log');
const tempFile = path.join(projectRoot, 'temp', 'user_prompts.log');

if (!fs.existsSync(archiveDir)) fs.mkdirSync(archiveDir, { recursive: true });
if (!fs.existsSync(path.join(projectRoot, 'temp'))) fs.mkdirSync(path.join(projectRoot, 'temp'), { recursive: true });

function appendToLog(text, msgTime) {
  try {
    let ts;
    if (msgTime) {
      const d = new Date(msgTime);
      ts = d.toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' });
    } else {
      const now = new Date();
      ts = now.toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' });
    }
    const firstLine = text.split('\n')[0] || '';
    const shortName = firstLine.length > 60 ? firstLine.substring(0, 57) + '...' : firstLine;
    const entry = `[${ts}]\nИмя: ${shortName}\n${text}\n${'='.repeat(60)}\n`;
    fs.appendFileSync(archiveFile, entry, 'utf-8');
    const tempEntry = `[${ts}]\n${text}\n${'='.repeat(60)}\n`;
    fs.appendFileSync(tempFile, tempEntry, 'utf-8');
  } catch (e) {}
}

export default async (ctx) => {
  return {
    "chat.message": async (input) => {
      try {
        if (!input) return;
        const role = input.role || '';
        const content = input.content || '';
        if (role === 'user' && content.trim().length >= 5) {
          appendToLog(content.trim(), input.timestamp || null);
        }
      } catch (e) { /* silent */ }
    },
    tool: {
      save_prompt: tool({
        description: 'Сохраняет промпт пользователя в архив. Вызывать при каждом новом сообщении пользователя.',
        args: { text: tool.schema.string(), timestamp: tool.schema.string().optional() },
        async execute(args, context) {
          if (args.text && args.text.trim().length >= 5) {
            appendToLog(args.text.trim(), args.timestamp || null);
            return 'OK';
          }
          return 'SKIP: too short';
        },
      }),
    },
  };
};
