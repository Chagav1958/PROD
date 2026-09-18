# Инструкции по добавлению Git в контекстное меню Проводника

## Способ 1: Импорт .reg файла (рекомендуется)

1. Откройте Проводник Windows
2. Перейдите в папку `C:\AIS\AI\Prod\docs\transfer-kit\`
3. Дважды кликните по файлу `git-context-menu.reg`
4. Подтвердите добавление в реестр (нажмите "Да" в диалоге UAC)
5. Готово! Команды Git появятся в контекстном меню

## Способ 2: Ручной импорт через regedit

1. Нажмите `Win + R`, введите `regedit`, нажмите Enter
2. В меню "Файл" → "Импорт"
3. Выберите файл `C:\AIS\AI\Prod\docs\transfer-kit\git-context-menu.reg`
4. Нажмите "Открыть"

## Доступные команды

После импорта в контекстном меню (правый клик по папке или пустому месту в папке) появятся:

| Команда | Описание |
|---------|----------|
| **Git Bash Here** | Открыть Git Bash в текущей папке |
| **Git GUI Here** | Открыть Git GUI в текущей папке |
| **Git Pull** | Выполнить `git pull` с паузой для просмотра результата |
| **Git Push** | Выполнить `git push` с паузой для просмотра результата |
| **Git Status** | Показать `git status` с паузой |

## Удаление команд

Если нужно удалить команды из контекстного меню:

1. Создайте файл `remove-git-context-menu.reg` со следующим содержимым:

```reg
Windows Registry Editor Version 5.00

[-HKEY_CLASSES_ROOT\Directory\Background\shell\GitBash]
[-HKEY_CLASSES_ROOT\Directory\shell\GitBash]
[-HKEY_CLASSES_ROOT\Directory\Background\shell\GitGUI]
[-HKEY_CLASSES_ROOT\Directory\shell\GitGUI]
[-HKEY_CLASSES_ROOT\Directory\Background\shell\GitPull]
[-HKEY_CLASSES_ROOT\Directory\shell\GitPull]
[-HKEY_CLASSES_ROOT\Directory\Background\shell\GitPush]
[-HKEY_CLASSES_ROOT\Directory\shell\GitPush]
[-HKEY_CLASSES_ROOT\Directory\Background\shell\GitStatus]
[-HKEY_CLASSES_ROOT\Directory\shell\GitStatus]
```

2. Сохраните в UTF-16 LE (кодировка Unicode)
3. Импортируйте файл двойным кликом

## Перенос на другой ПК

1. Скопируйте файл `git-context-menu.reg` на новый ПК
2. Убедитесь, что Git установлен в `C:\Program Files\Git\`
3. Если путь другой — отредактируйте .reg файл (замените пути)
4. Импортируйте .reg файл

## Примечания

- Команды работают для правого клика по папке И для правого клика по пустому месту внутри папки
- Иконки команд берутся из исполняемых файлов Git
- Команды Pull/Push/Status открывают cmd.exe, выполняют команду и ждут нажатия клавиши (pause)
