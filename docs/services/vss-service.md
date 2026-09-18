# VSS-сервис — система контроля версий

> **Версия:** 1.0 от 07.08.2026
> **Родительский том:** [Главный том документации](../master-index.md)

---

## 1. Назначение

VSS-сервис обеспечивает интеграцию с Microsoft Visual SourceSafe (ss.exe) для контроля версий PowerBuilder-объектов.

**Файлы:**
- `scripts\VSS-Utils.ps1` — PowerShell-модуль (Get-VssLatest, Get-VssStatus, Set-VssCheckout, Set-VssCheckin, Undo)
- `scripts\VSS-History.ps1` — история версий с поиском текста
- `scripts\VSS-History-Show.ps1` — WPF-окно истории с TortoiseMerge

---

## 2. Операции МОРДА2

| № | Операция | Команда VSS |
|---|----------|------------|
| 11 | Get Latest | `ss Get $/SRC125/... -R` |
| 12 | Check Status | `ss Status $/SRC125/... -R` |
| 13 | Who Is Using | `ss Properties $/SRC125/... -R` |
| 14 | Checkout | `ss Checkout $/SRC125/... -C"comment"` |
| 15 | Checkin | `ss Checkin $/SRC125/... -C"comment"` |
| 16 | Undo Check Out | `ss Undocheckout $/SRC125/...` |
| 17 | Object History | `ss History $/SRC125/...` |

---

## 3. История объекта

Окно `VSS-History-Show.ps1` показывает все версии объекта с возможностью:
- Сравнения через TortoiseMerge
- Поиска текста по всем версиям
- Прогресс-бары (фаза: версия N из M, шаг: поиск)

---

## 4. Экономическая выгода

- **Автоматизация VSS:** вместо ручного запуска ss.exe — один клик в МОРДА2
- **Массовые операции:** рекурсивный Get Latest/Status для сотен объектов
- **Поиск по истории:** поиск текста во всех версиях объекта за секунды