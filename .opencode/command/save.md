---
description: "СОХР — сохранить текущий вариант проекта, сделать архив на дату-время."
---

# СОХР

Запусти скрытно (антивирус): `powershell -NoProfile -File scripts\Launch-Hidden.ps1 -Script "Save-Snapshot.ps1" -Minimized`. MetroWindow не работает в Hidden, только Minimized.

Архивируются:
- `bin/*.ps1`, `bin/*.bat`
- `scripts/*.ps1`
- `config/*.json`, `config/*.txt`
- `docs/*.html`, `docs/*.pdf`, `docs/*.md`, `docs/screenshots/*.*`
- `rules/*.md`
- `.opencode/*.mdc`, `.opencode/plugin/*.js`, `.opencode/command/*.md`
- `AGENTS.md`
