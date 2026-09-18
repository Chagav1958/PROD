// Плагин: технический enforcer проверки PB/SQL-кода перед правкой .sr*/.sql
//
// Назначение: принудительно выполнять требование preflight.mdc п.0 —
// ПЕРЕД правкой объекта PowerBuilder (.sr*) или .sql-скрипта модель обязана
// свериться с документацией/валидатором (sybase-docs_validate_code и др.).
//
// Механизм "кредитов валидации":
//   - каждый вызов валидирующего инструмента добавляет кредиты;
//   - каждый edit/write/apply_patch целевого файла тратит 1 кредит;
//   - при отсутствии кредитов правка БЛОКИРУЕТСЯ (режим "block", по умолчанию)
//     или сопровождается предупреждением (режим "warn").
//
// Дополнительно: быстрый статический поиск запрещённых идиом в новом коде
// (iif(, ??, ?., => и т.п. — их нет в PowerScript/Transact-SQL).
//
// Конфигурация (все параметры необязательны):
//   "plugin": [".opencode/plugins/pb-sql-enforcer.js", { "mode": "warn" }]
//   mode: "block" (по умолчанию) | "warn"

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync, spawn } from 'node:child_process';
import { tool } from '@opencode-ai/plugin';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const projectRoot = path.resolve(__dirname, '..', '..');

const stateDir = path.join(projectRoot, '.opencode', 'session');
const stateFile = path.join(stateDir, 'pb-sql-enforcer.json');
const stateMsg = 'файл состояния ' + stateFile;

// LSP pb_lsp (LspProxy.exe) — путь из opencode.jsonc, режим --pipe.
const LSP_PROXY = 'C:\\AIS\\AI\\PB_LSP\\bin\\LspProxy.exe';
const LSP_EXTENSIONS = ['.srw', '.sru', '.srd', '.srf', '.srm', '.srs', '.sql'];

// СЕРВИС PB (PBSERV): конфиг мер — config/pb_service.json
const serviceCfgFile = path.join(projectRoot, 'config', 'pb_service.json');

// --- LSP pb_lsp: проверка/запуск как источник быстрой валидации ---
function isLspRunning() {
  try {
    const out = execSync('tasklist /FI "IMAGENAME eq LspProxy.exe" /NH', { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] });
    return out && out.toLowerCase().indexOf('lspproxy.exe') !== -1;
  } catch (e) { return false; }
}

function ensureLspStarted() {
  if (isLspRunning()) return { started: false, reason: 'already running' };
  try {
    const proc = spawn(LSP_PROXY, ['--pipe'], { detached: true, stdio: 'ignore', windowsHide: true });
    proc.unref();
    return { started: true, pid: proc.pid };
  } catch (e) {
    return { started: false, reason: String(e && e.message || e) };
  }
}

let lspInfo = { checked: false, running: false, started: false, lastCheck: 0 };
function lspStatus() {
  const TTL = 30000;
  const now = Date.now();
  if (lspInfo.checked && (now - lspInfo.lastCheck) < TTL) return lspInfo;
  lspInfo.running = isLspRunning();
  if (!lspInfo.running) {
    const r = ensureLspStarted();
    lspInfo.started = r.started;
    if (r.started) lspInfo.running = true;
  }
  lspInfo.checked = true;
  lspInfo.lastCheck = now;
  return lspInfo;
}

const PB_EXTS = ['.srw', '.sru', '.srd', '.sra', '.srs', '.srm', '.srf'];
const SQL_EXTS = ['.sql'];
const TARGET_EXTS = PB_EXTS.concat(SQL_EXTS);

const EDIT_TOOLS = ['edit', 'write', 'apply_patch'];
// Протухание кредитов: ~10 минут после последней валидации (см. точку возобновления id=45)
const VALIDATION_TTL_MS = 10 * 60 * 1000;

// Инструменты, дающие "кредиты валидации" (проверка кода/правил по документации).
const CREDITS_BY_TOOL = {
  'sybase-docs_validate_code': 2,
  'claude_pb': 1,
  'claude_sql': 1,
  'rules-mcp_get_rule': 1,
  'rules-mcp_preflight_check': 1,
  'sybase-docs_search_docs': 1,
};

// Запрещённые идиомы: их НЕТ в PowerScript/Transact-SQL.
const FORBIDDEN = [
  { re: /iif\s*\(/gi, desc: 'iif(...) нет в PowerScript — используйте if/then/else' },
  { re: /\?\?/g, desc: '?? (склейка null) — это C#/JS, не PB/SQL' },
  { re: /\?\./g, desc: '?. (optional chaining) — это JS/C#, не PB/SQL' },
  { re: /=>/g, desc: '=> (стрелка-лямбда) — не используется в PowerScript/SQL' },
  { re: /\bSwitch\s*\(/gi, desc: 'Switch(...) есть только в PowerScript 12+, проверьте по документации (iif-замена не обязательна)' },
];

// СЕРВИС PB, мера M1: белый список перечисляемых констант messageBox.
// Проверено 16.09.2026 (grep по PB_Main): Warning! в проекте НЕ используется (0 файлов) —
// это выдуманная константа, приводящая к C0060. Разрешены только:
const ALLOWED_ICONS = [
  'Information!', 'StopSign!', 'Exclamation!', 'Question!',
  'None!', 'Error!', 'Asterisk!', 'Hand!'
];
// Известные "обманки" из других языков — блокируются явно.
const KNOWN_BAD_ICONS = ['Warning!', 'Warn!', 'WarningExclamation!', 'Critical!', 'Fatal!'];

// Быстрый статический поиск выдуманных констант messageBox в новом коде.
function scanBadIcons(text) {
  if (typeof text !== 'string' || text.trim() === '') return [];
  const issues = [];
  for (const bad of KNOWN_BAD_ICONS) {
    if (text.indexOf(bad) !== -1) {
      issues.push(bad + ' — выдуманная константа messageBox, в проекте НЕ используется. Разрешены: ' + ALLOWED_ICONS.join(', '));
    }
  }
  return issues;
}

// СЕРВИС PB: чтение конфига мер.
function loadServiceConfig() {
  try {
    if (fs.existsSync(serviceCfgFile)) {
      const raw = fs.readFileSync(serviceCfgFile, 'utf-8');
      const parsed = JSON.parse(raw);
      return parsed;
    }
  } catch (e) { /* повреждённый конфиг — используем значения по умолчанию */ }
  return null;
}

function measureEnabled(cfg, key) {
  if (!cfg || !cfg.measures || !cfg.measures[key]) return true; // по умолчанию включено
  return cfg.measures[key].enabled !== false;
}

function bumpServiceStat(cfg, key) {
  try {
    if (!cfg || !cfg.stats) return;
    if (typeof cfg.stats[key] === 'number') cfg.stats[key] += 1;
    fs.writeFileSync(serviceCfgFile, JSON.stringify(cfg, null, 2), 'utf-8');
  } catch (e) { /* silent */ }
}

function loadState() {
  try {
    if (fs.existsSync(stateFile)) {
      const raw = fs.readFileSync(stateFile, 'utf-8');
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed.credits === 'number') return parsed;
    }
  } catch (e) { /* повреждённый файл — пересоздаём */ }
  return { credits: 0, lastValidation: 0, history: [] };
}

function saveState(state) {
  try {
    if (!fs.existsSync(stateDir)) fs.mkdirSync(stateDir, { recursive: true });
    fs.writeFileSync(stateFile, JSON.stringify(state, null, 2), 'utf-8');
  } catch (e) { /* silent */ }
}

function isTarget(filePath) {
  if (typeof filePath !== 'string' || filePath.trim() === '') return false;
  const ext = path.extname(filePath).toLowerCase();
  return TARGET_EXTS.indexOf(ext) !== -1;
}

function addCredits(state, toolName) {
  const gain = CREDITS_BY_TOOL[toolName] || 0;
  if (gain <= 0) return;
  state.credits += gain;
  // Любой валидирующий вызов (включая доступные claude_pb/claude_sql)
  // делает маркер "свежей валидации" актуальным, чтобы кредиты не
  // сгорали мгновенно из-за устаревшего lastValidation (см. SUPRT-19100).
  state.lastValidation = Date.now();
  state.history.push({ t: Date.now(), tool: toolName, gain: gain });
  if (state.history.length > 50) state.history = state.history.slice(-50);
  saveState(state);
}

function expireCredits(state) {
  if (state.credits <= 0 || state.lastValidation <= 0) return false;
  if (Date.now() - state.lastValidation <= VALIDATION_TTL_MS) return false;
  state.credits = 0;
  saveState(state);
  return true;
}

// Извлекает "новый код" из аргументов инструмента для сканирования.
function extractNewCode(toolName, args) {
  if (!args) return '';
  if (toolName === 'write') {
    const text = args.content || args.text || '';
    return String(text);
  }
  if (toolName === 'edit') {
    const newText = args.newString || args.replaceAll || '';
    return String(newText);
  }
  // apply_patch: текст в формате diff (полноценное извлечение ненадёжно) —
  // сканируем только строки, начинающиеся с '+' (добавления).
  const patch = String(args.patchText || args.patch || '');
  const added = [];
  for (const line of patch.split(/\r?\n/)) {
    if (line.length > 1 && line[0] === '+' && line[1] !== '+' && line[1] !== '-') {
      added.push(line.slice(1));
    }
  }
  return added.join('\n');
}

function scanCode(text) {
  if (typeof text !== 'string' || text.trim() === '') return [];
  const issues = [];
  for (const item of FORBIDDEN) {
    if (item.re.test(text)) issues.push(item.desc);
  }
  return issues;
}

function appendContexts(output, contexts) {
  if (!contexts || contexts.length === 0) return;
  const text = contexts.join('\n');
  output.output = output.output ? `${output.output}\n\n${text}` : text;
}

export default async (_ctx, options = {}) => {
  const mode = (options && options.mode === 'warn') ? 'warn' : 'block';
  const state = loadState();

  return {
    "tool.execute.before": async (input, output) => {
      const toolName = input.tool;
      expireCredits(state);
      if (EDIT_TOOLS.indexOf(toolName) === -1) return;
      const args = output.args || {};
      const filePath = String(args.filePath || args.file_path || '');
      if (!isTarget(filePath)) return;

      const serviceCfg = loadServiceConfig();
      const m1enabled = measureEnabled(serviceCfg, 'm1_enforcer_allowlist');

      const ext = path.extname(filePath).toLowerCase();
      if (state.credits <= 0) {
        if (!m1enabled) return; // СЕРВИС PB M1 выключен — не блокируем правки без валидации
        const msg =
          'PBSQL-ENFORCER BLOCK: правка ' + ext + '-файла запрещена без предварительной валидации. ' +
          'Требование preflight.mdc п.0: ПЕРЕД правкой объекта PowerBuilder/' +
          'ASA SQL необходимо вызвать ' +
          'sybase-docs_validate_code (product "pb12.5" или "ase15.5") с фрагментом кода ' +
          'и/или rules-mcp_get_rule("pb"|"sql"). После валидации повторите правку. ' +
          '(СЕРВИС PB M1: отключить меру — PBSERV -Off m1)';
        bumpServiceStat(serviceCfg, 'm1_enforcer_blocks');
        throw new Error(msg);
      }

      const newCode = extractNewCode(toolName, args);
      const issues = scanCode(newCode);

      // СЕРВИС PB M1: выдуманные константы messageBox
      if (m1enabled) {
        const iconIssues = scanBadIcons(newCode);
        if (iconIssues.length > 0) {
          const msg =
            'PBSQL-ENFORCER BLOCK: в новом коде найдены выдуманные константы messageBox: ' +
            iconIssues.join('; ') + '. Перепишите код, затем повторите правку. ' +
            '(СЕРВИС PB M1: отключить меру — PBSERV -Off m1)';
          bumpServiceStat(serviceCfg, 'm1_enforcer_blocks');
          throw new Error(msg);
        }
      }

      if (issues.length > 0) {
        if (!m1enabled) return; // СЕРВИС PB M1 выключен — идиомы не блокируем
        const msg =
          'PBSQL-ENFORCER BLOCK: в новом коде найдены подозрительные/запрещённые ' +
          'идиомы: ' + issues.join('; ') + '. Перепишите код по документации ' +
          'sybase-docs, затем повторите правку.';
        bumpServiceStat(serviceCfg, 'm1_enforcer_blocks');
        throw new Error(msg);
      }
    },

    "tool.execute.after": async (input, output) => {
      const toolName = input.tool;
      const contexts = [];

      if (CREDITS_BY_TOOL[toolName]) {
        addCredits(state, toolName);
        contexts.push(
          'PBSQL-ENFORCER INFO: валидация "' + toolName + '" получена, ' +
          'осталось кредитов: ' + state.credits + '.'
        );
      } else if (EDIT_TOOLS.indexOf(toolName) !== -1) {
        const args = input.args || output.args || {};
        const filePath = String(args.filePath || args.file_path || '');
        if (isTarget(filePath)) {
          let hint = null;
          if (state.credits <= 0) {
            hint = 'PBSQL-ENFORCER WARNING: правка выполнена БЕЗ предварительной валидации ' +
              '(кредитов не было). Следующая правка будет заблокирована, пока вы не ' +
              'вызовете sybase-docs_validate_code.';
          } else {
            state.credits -= 1;
            saveState(state);
            hint = 'PBSQL-ENFORCER INFO: правка засчитана, списано 1 кредит ' +
              'валидации (осталось: ' + state.credits + ').';
          }
          if (hint) contexts.push(hint);
        }
      }

      appendContexts(output, contexts);
    },

    tool: {
      pb_enforce_status: tool({
        description:
          'Показывает статус плагина-энфорсера PB/SQL: режим (block/warn), ' +
          'остаток кредитов валидации, время последней валидации, историю кредитов, ' +
          'состояние LSP pb_lsp.',
        args: {},
        async execute() {
          expireCredits(state);
          const isRecent = (state.lastValidation > 0) ? new Date(state.lastValidation).toLocaleString('ru-RU') : 'нет';
          const lastFive = state.history.slice(-5)
            .map(function (h) { return '[' + new Date(h.t).toLocaleString('ru-RU') + '] ' + h.tool + ' +' + h.gain; })
            .join('\n  ');
          const serviceCfg = loadServiceConfig();
          const m1 = measureEnabled(serviceCfg, 'm1_enforcer_allowlist');
          const m4 = measureEnabled(serviceCfg, 'm4_mandatory_claude');
          const m5 = measureEnabled(serviceCfg, 'm5_wait_mcp');
          const lsp = lspStatus();
          const lspLine = lsp.running
            ? 'ВКЛ' + (lsp.started ? ' (запущен плагином)' : ' (был запущен ранее)')
            : 'ВЫКЛ (не удалось запустить LspProxy.exe)';
          return (
            'PBSQL-ENFORCER статус:\n' +
            '  режим: ' + mode + '\n' +
            '  кредиты: ' + state.credits + '\n' +
            '  TTL кредитов: ' + (VALIDATION_TTL_MS / 60000) + ' мин\n' +
            '  последняя валидация: ' + isRecent + '\n' +
            '  файл состояния: ' + stateFile + '\n' +
            '  LSP pb_lsp: ' + lspLine + '\n' +
            '  СЕРВИС PB (config/pb_service.json):\n' +
            '    M1 enforcer+константы: ' + (m1 ? 'ВКЛ' : 'ВЫКЛ') + '\n' +
            '    M4 валидация claude_*:  ' + (m4 ? 'ВКЛ' : 'ВЫКЛ') + '\n' +
            '    M5 ждать MCP:          ' + (m5 ? 'ВКЛ' : 'ВЫКЛ') + '\n' +
            '  история (до 5):\n  ' + (lastFive || '(пусто)')
          );
        },
      }),
    },
  };
};
