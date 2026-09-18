# Правила сервиса Jira RFC

## Состав сервиса

| Файл | Назначение |
|------|------------|
| `scripts\Create-RFC.ps1` | Создание задачи RFC в Jira для указанной задачи |
| `scripts\Find-JiraFields.ps1` | Обнаружение ID пользовательских полей Jira для настройки |
| `config\config.json` (секция `jira`) | Настройки Jira: URL, проект, custom fields |

## Зависимости

- **Jira REST API** — версия 2 (`/rest/api/2/`)
- **HTTP-авторизация (схема Bearer)** — API-токен
- Invoke-RestMethod (встроенный в PowerShell)

## Поля RFC (из RFC-12336 / RFC-12359)

### Обязательные поля при создании
| Поле | Значение |
|------|----------|
| summary | `Разработка - <название задачи>` |
| description | `RFC сформирована автоматически - AIS Release Preparation` |
| assignee | `{name: "<текущий пользователь>"}` |
| customfield_25953 | План проведения работ (8 шагов, см. шаблон) |
| customfield_25954 | `Исправляем появившиеся ошибки и собираем новую версию` |
| customfield_13852 | `Нет` |
| customfield_15254 | `Нет` |
| customfield_15255 | `{name: "<текущий пользователь>"}` (Ответственный за релиз) |
| customfield_15256 | `{name: "<текущий пользователь>"}` (Эксперт по продукту) |
| customfield_15350 | `[{name: "<reporter задачи>"}]` (Проверяющие на бою = автор задачи) |
| customfield_25955 | `@("SYSTEM-67")` |
| customfield_26053 | `@("SYSTEM-67")` |
| customfield_15258 | Дата начала (now + 1h, округление до часа) |
| customfield_15259 | Дата завершения (старт + 24h) |

### Связь с задачей
- Тип: `Mention`
- inwardIssue: RFC (создаваемая)
- outwardIssue: исходная задача (TaskName)

## Известные ошибки и их предотвращение

### Create-RFC.ps1

1. **Кодировка комментариев в теле скрипта**
   - Текст в `# comment` и строковых литералах местами имеет искажённую кириллицу
   - **Правило:** при редактировании не полагаться на видимый текст комментариев

2. **Пароль Jira через SecureString**
   - `Read-Host -AsSecureString` → `SecureStringToBSTR` → `PtrToStringAuto`
   - **Правило:** удалять `$JiraPassword` после использования

3. **Placeholder поля в config.json**
   - Поля `release_start`, `release_end`, `task_link_field` имеют значения `customfield_XXXXX`
   - **Правило:** проверка `if ($cfStart -and $cfStart -notmatch '^customfield_XXXXX$')` защищает от пустых значений

4. **Линковка RFC к задаче**
   - Тип связи: `Mention` (не `Relates`)
   - Если задача не существует — ошибка перехватывается try/catch

5. **Формат таймстампов**
   - `yyyy-MM-ddTHH:mm:ss.000+0300` (без двоеточия в timezone)

6. **Кодировка UTF-8**
   - Все .ps1 файлы с кириллицей должны быть в UTF-8 with BOM
   - PowerShell 5.1 на русской Windows читает без BOM как Windows-1251

## Рекомендации

- Перед первым использованием запустить `Find-JiraFields.ps1` и обновить config.json
- Пароль Jira не сохраняется — вводится при каждом запуске
- RFC создаётся с окном релиза: `start = now + 1h`, `end = start + 24h`
- Если RFC уже существует для задачи — создание пропускается
