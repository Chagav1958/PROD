---
description: Тестирует LLM через OpenCode API. Формат: TESTLLM <modelName>
---

# TESTLLM

Тестирует модель LLM на способность ответить "Ok" через OpenCode HTTP API.

## Формат
```
TESTLLM <modelName>
```

Где `<modelName>` — имя провайдера/модели из конфига, например `opencode-zen/claude-sonnet-4-5`.

## Протокол
1. Очищается файл `temp\llm_test_result.log`
2. Вызывается `TESTLLM <modelName>` для каждой модели параллельно
3. Каждый вызов:
   - Создаёт сессию POST `/session` с `{"model":{"id":"<model>","providerID":"<provider>"}}`
   - Отправляет промпт POST `/session/{id}/prompt_async` `{"text":"Ok"}`
   - Опрашивает GET `/session/{id}/message` до получения ответа
   - Если ответ содержит "Ok" — пишет `Ok <modelName>` в `temp\llm_test_result.log`
   - Если ошибка — пишет `Error <modelName>: <причина>` в тот же файл
4. После таймаута (30с) читается `temp\llm_test_result.log`
5. Строки `Ok ...` — работающие модели

## Параллельный запуск
Каждый вызов TESTLLM независим и может выполняться параллельно через Start-Process или отдельный поток PS.
