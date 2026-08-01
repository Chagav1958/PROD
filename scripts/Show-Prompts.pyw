import sys, os, re
import tkinter as tk
from tkinter import ttk, messagebox as mb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow

class PromptsDialog(AppWindow):
    def __init__(self):
        super().__init__(title="Архив промптов", win_w=960, win_h=640)
        self._base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self._log_file = os.path.join(self._base, "temp", "user_prompts.log")
        self._prompts = []
        self._load_prompts()
        self._build_ui()

    def _load_prompts(self):
        if not os.path.isfile(self._log_file):
            self._prompts = []
            return
        with open(self._log_file, "r", encoding="utf-8") as f:
            content = f.read()
        blocks = re.split(r"={4,}", content)
        for b in blocks:
            b = b.strip()
            if not b:
                continue
            lines = b.split("\n")
            name = ""
            dt = ""
            text = b
            for l in lines:
                if l.startswith("Name:"):
                    name = l[5:].strip()
                elif l.startswith("DateTime:"):
                    dt = l[9:].strip()
            self._prompts.append({"name": name, "datetime": dt, "text": text})
        self._prompts.reverse()

    def _build_ui(self):
        # Toolbar
        tb = tk.Frame(self.content, bg="white")
        tb.pack(fill="x", pady=(0, 4))
        tk.Label(tb, text=f"Промптов: {len(self._prompts)}",
                font=("Segoe UI", 9, "bold"), fg="#4A5568", bg="white").pack(side="left")

        # Search
        tk.Label(tb, text="Поиск:", font=("Segoe UI", 9), fg="#4A5568", bg="white").pack(side="left", padx=(12, 4))
        self._search_var = tk.StringVar()
        self._search_var.trace("w", lambda *a: self._filter())
        tk.Entry(tb, textvariable=self._search_var, font=("Segoe UI", 9),
                relief="solid", bd=1, width=30).pack(side="left", padx=(0, 4), ipady=2)

        # Grid
        f = tk.Frame(self.content, bg="white")
        f.pack(fill="both", expand=True)

        cols = ("name", "datetime", "text")
        self._tree = ttk.Treeview(f, columns=cols, show="headings", selectmode="browse")
        self._tree.heading("name", text="Имя")
        self._tree.heading("datetime", text="Дата/Время")
        self._tree.heading("text", text="Текст")
        self._tree.column("name", width=160, minwidth=80)
        self._tree.column("datetime", width=140, minwidth=80)
        self._tree.column("text", width=600, minwidth=200)
        self._tree.tag_configure("alt", background="#F5F7FA")
        self._tree.pack(fill="both", expand=True, side="left")

        vsb = ttk.Scrollbar(f, orient="vertical", command=self._tree.yview)
        vsb.pack(side="right", fill="y")
        self._tree.configure(yscrollcommand=vsb.set)

        self._populate(self._prompts)

        # Copy button
        br = self.button_row()
        br.pack(pady=(6, 0))
        self.button(br, "Копировать", self._copy_selected, primary=True, name="btn_copy")
        self.button(br, "Закрыть", self.destroy, primary=False, name="btn_close")

    def _populate(self, items):
        self._tree.delete(*self._tree.get_children())
        for idx, p in enumerate(items):
            tag = "alt" if idx % 2 else ""
            self._tree.insert("", "end", values=(p["name"], p["datetime"], p["text"][:200]),
                             tags=(tag,) if tag else ())

    def _filter(self):
        q = self._search_var.get().lower()
        if not q:
            self._populate(self._prompts)
            return
        filtered = [p for p in self._prompts if q in p["text"].lower() or q in p["name"].lower()]
        self._populate(filtered)

    def _copy_selected(self):
        sel = self._tree.selection()
        if not sel:
            mb.showwarning("Копирование", "Выберите промпт из списка")
            return
        item = self._tree.item(sel[0])
        name = item["values"][0]
        for p in self._prompts:
            if p["name"] == name:
                self.clipboard_clear()
                self.clipboard_append(p["text"])
                mb.showinfo("Копирование", "Промпт скопирован в буфер обмена")
                return

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = PromptsDialog()
    dlg.mainloop()
