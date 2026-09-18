---
name: pb-object-skill
description: Работа с объектами PowerBuilder: анализ и правка .srw/.sru/.srd/.srm/.srs, PowerScript, event-ы, функции, call super, DDDW, GetChild, HEX-кодирование русского текста, зависимости PB-объектов. Используй ТОЛЬКО когда задача касается PB-кода или PowerScript, НЕ для общих вопросов.
---

# PowerBuilder объекты — правила работы

> Полный источник: `C:\AIS\AI\Prod\.opencode\pb-object-rules.mdc`

## 0. PREFLIGHT перед любым PB-кодом (ОБЯЗАТЕЛЬНО)

ПЕРЕД написанием ЛЮБОГО кода PowerScript / правки .sr* — читать MCP/LSP:
- `sybase-docs_search_docs` — синтаксис функций и event-ов
- `sybase-docs_validate_code(code=..., product="pb12.5")` — валидация
- `rules-mcp_get_rule("pb")` — правила проекта
- НЕ полагаться на память (реальный баг: `iif(` → C0051; используйте многострочный `if ... then ... else ... end if`)

## Запрещённые идиомы PowerScript

- `iif(` — НЕТ такой функции; только многострочный `if ... then ... else ... end if`
- `??`, `?.`, `=>`, `Switch(` — отсутствуют в PowerScript/ASA SQL

## 1. Event-ы

Каждый создаваемый event обязан заканчиваться `end event`:

```powerbuilder
event clicked;call super::clicked;
// какой-то код
end event
```

Даже пустой event требует `end event` (с `return success`).

## 2. Разделение списков функций и event-ов

- **event-ы** — только в списке событий (`forward events ... end events`)
- **функции** — только в списке функций (`forward prototypes ... end prototypes`)
- В силу особенностей PB Export event-ы могут быть в общем `forward prototypes` в конце списка, отделённые от функций. Главное — не путать event с function.

## 3. call super:: и флаг «Extend Ancestor Script»

- Если флаг «Extend Ancestor Script» **включён** (в IDE) — НЕ вставлять `call super::` → будет ДВОЙНОЕ выполнение родительского кода
- Если флаг **выключен** — вставлять `call super::` первой строкой
- В текстовом экспорте флаг не виден; при правке через инструменты всегда явно указывать `call super::` (флаг нельзя установить текстом)

## 4. Именование и общие рекомендации

- **Функции:** префикс `uf_`; **события:** `ue_`; переменные: `i_` (instance), `li_/ls_/ld_` (local)
- **DDDW** — тип переменной **`DataWindowChild`** (НЕ `DataStoreChild` — такого типа нет):

```powerbuilder
DataWindowChild ldsc_child
IF dw_table1.GetChild('column_name', ldsc_child) = 1 THEN
    ldsc_child.SetFilter("filter_condition")
    ldsc_child.Filter()
END IF
```

- **Проверка объекта:** перед обращением к динамическому объекту — `IsValid()`:

```powerbuilder
w_entity_card lw_parent
this.of_getparentwindow(ref lw_parent)
IF IsValid(lw_parent) THEN
    // безопасное обращение
END IF
```

## 5. Русскоязычные строки в PB Export — HEX

Все русские строки в .sr* кодируются:

```
$$HEX<длина_в_байтах>$$<UTF-16LE hex>$$ENDHEX$$
```

Утилита: `ConvertTo-PBHex` (PowerShell) — см. в `pb-object-rules.mdc`.

## 6. Анализ зависимостей PB-объектов (5 типов связей)

| dep_type | Направление | Где искать |
|----------|-------------|------------|
| `calls` | PB → PB | PowerScript: `uf_...()`, `of_...()`, `uo_class.of_method()` |
| `sql_ref` | PB → SQL | Встроенный SELECT/EXEC, `dataobject="d_*"` |
| `dddw` | PB → PB | `.srd`: `dddw.name="d_..."`; код: `GetChild`, `Modify("col.dddw.Name")` |
| `contains` | PB → PB | `.srw/.sru`: `type dw_1 from datawindow within w_bill` |
| `inherits` | PB → PB | `$PBExportHeader$...`, `type w_x from w_y` |

При анализе ЛЮБОГО PB-объекта проверять ВСЕ 5 типов, не только calls/sql_ref.

## 7. Кодировка

- `.sr*` файлы — **Windows-1251** без BOM; после любой правки конвертировать обратно в CP1251 (Bug-061), иначе PB IDE показывает кракозябры.