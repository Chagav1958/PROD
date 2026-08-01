import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow
import tkinter as tk

PHASES = ["Фаза 1: инициализация", "Фаза 2: обработка", "Фаза 3: финализация"]

class TestMsgDialog(AppWindow):
    def __init__(self):
        super().__init__(title="MSG Тест дизайна", win_w=520, win_h=580)
        self._tick = 0
        self._total = 30
        self._build_ui()

    def _build_ui(self):
        ib = self.info_box("Это тестовое окно для проверки оформления MSG-диалогов "
                           "в стиле APPL. Овальные кнопки, закруглённые углы, "
                           "серая градация фона.")
        ib.pack(fill="x", padx=0, pady=(6, 10))

        fg = self.field_group()
        fg.pack(fill="x", padx=0, pady=(0, 10))
        self.field_text(fg, label="Текстовое поле (TextBox)", name="txt_field")
        self.field_password(fg, label="Поле пароля (PasswordBox)", name="pwd_field")
        self.field_combo(fg, label="Выпадающий список (ComboBox)",
                        items=["Пункт 1 — обычный", "Пункт 2 — важный", "Пункт 3 — срочный"],
                        name="cmb_field")

        f, self.pb1, self.pb2, self.pl, self.sl = self.progress_pair(name="prog")
        f.pack(fill="x", pady=(0, 6))
        self.pb1["value"] = 45
        self.pb2["value"] = 30

        br = self.button_row()
        br.pack(pady=(6, 0))
        self.button(br, "OK", self._on_ok, primary=True, name="btn_ok")
        self.button(br, "Отмена", self.destroy, primary=False, name="btn_cancel")

    def _on_ok(self):
        self.pl.configure(text="Фаза 1: инициализация")
        self.sl.configure(text="(0 - 5)")
        self.pb1["value"] = 0
        self.pb2["value"] = 0
        self._tick = 0
        self._animate()

    def _animate(self):
        self._tick += 1
        pct = min(100, int(self._tick / self._total * 100))
        phase_idx = min(2, int(self._tick / 10))
        self.pl.configure(text=PHASES[phase_idx])
        self.pb1["value"] = pct
        self.sl.configure(text=f"({self._tick} из {self._total})")
        self.pb2["value"] = min(100, (self._tick % 10) * 10)
        if self._tick < self._total:
            self.after(200, self._animate)
        else:
            self.pl.configure(text="Готово")
            self.sl.configure(text="Завершено")
            self.pb1["value"] = 100
            self.pb2["value"] = 100

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = TestMsgDialog()
    dlg.mainloop()
