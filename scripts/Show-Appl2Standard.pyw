import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow, C_WHITE
import tkinter as tk

PHASES = ["Фаза 1: инициализация", "Фаза 2: обработка", "Фаза 3: финализация"]
SAMPLE_DATA = [
    ("w_ais_request_select", "Window", "READY", "Окно выбора заявок — ожидает выгрузки"),
    ("w_ais_request_card", "Window", "NOT_READY", "Карточка заявки — требуется доработка"),
    ("u_em_ais_rs", "UserObject", "READY", "Пользовательский объект для работы с заявками"),
    ("d_ais_request_list", "DataWindow", "NOT_READY", "Список заявок — ожидает выверки"),
    ("f_get_client_requests", "Function", "READY", "Функция получения заявок клиента"),
    ("p_create_request", "Procedure", "DIFF", "Процедура создания заявки — есть отличия"),
    ("tr_request_after_insert", "Trigger", "READY", "Триггер после вставки заявки"),
    ("w_ais_request_edit", "Window", "NEW_OBJECT", "Новое окно редактирования заявки"),
]

class Appl2StandardDialog(AppWindow):
    def __init__(self):
        super().__init__(title="APPL2 Стандарт", win_w=580, win_h=620)
        self._tick = 0
        self._total = 30
        self._build_ui()

    def _build_ui(self):
        fg = self.field_group()
        fg.pack(fill="x", padx=0, pady=(0, 6))

        ff = tk.Frame(fg, bg=C_WHITE)
        ff.pack(fill="x")
        self.field_text(ff, label="TextBox", name="txt_field").pack(side="left", padx=(0, 6), fill="x", expand=True)
        self.field_password(ff, label="PasswordBox", name="pwd_field").pack(side="left", padx=(0, 6), fill="x", expand=True)
        self.field_combo(ff, label="ComboBox", items=["Пункт 1", "Пункт 2", "Пункт 3"], name="cmb_field").pack(side="left", fill="x", expand=True)

        dg = self.data_grid(self.content, ["Объект", "Тип", "Статус", "Описание"], SAMPLE_DATA, name="grid")
        dg.pack(fill="both", expand=True, pady=(0, 6))

        sp = self.search_panel(self.content, treeview=self._widgets.get("grid"), name="grid")
        sp.pack(fill="x")

        f, self.pb1, self.pb2, self.pl, self.sl = self.progress_pair(name="prog")
        f.pack(fill="x", pady=(4, 0))
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
    dlg = Appl2StandardDialog()
    dlg.mainloop()
