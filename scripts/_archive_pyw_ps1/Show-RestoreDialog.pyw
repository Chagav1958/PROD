import sys, os, json, re, subprocess
import tkinter as tk
from tkinter import ttk, messagebox as mb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow

class RestoreDialog(AppWindow):
    def __init__(self):
        super().__init__(title="Восстановление конфигов OpenCode", win_w=560, win_h=380, resizable=False)
        self._snapshots = []
        self._load_snapshots()
        self._build_ui()

    def _load_snapshots(self):
        base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        archive = os.path.join(base, "archives", "OpenCode")
        if not os.path.isdir(archive):
            return
        for d in sorted(os.listdir(archive), reverse=True):
            dp = os.path.join(archive, d)
            if not os.path.isdir(dp) or not d.startswith("Snapshot_"):
                continue
            meta = {}
            mp = os.path.join(dp, "_meta.json")
            if os.path.isfile(mp):
                try:
                    with open(mp, "r", encoding="utf-8") as f:
                        meta = json.load(f)
                except:
                    pass
            files = [x for x in os.listdir(dp) if x != "_meta.json"]
            self._snapshots.append({
                "folder": d, "label": meta.get("label", ""),
                "files": len(files), "mtime": os.path.getmtime(dp)
            })

    def _build_ui(self):
        tk.Label(self.content, text="Выберите снапшот для восстановления:",
                font=("Segoe UI", 10, "bold"), fg="#4A5568", bg="white",
                anchor="w").pack(fill="x", pady=(0, 8))

        self._listbox = tk.Listbox(self.content, font=("Consolas", 9),
                                   relief="solid", bd=1, bg="white",
                                   selectbackground="#3182CE")
        self._listbox.pack(fill="both", expand=True)
        for s in self._snapshots:
            label = s["label"]
            line = f"{s['folder']:<45} {s['files']:>3}ф  {label}"
            self._listbox.insert("end", line)
        if not self._snapshots:
            self._listbox.insert("end", "--- Нет снапшотов ---")
        else:
            self._listbox.selection_set(0)

        tk.Label(self.content, text="Или введите дату вручную (YYYYMMDD_HHMMSS):",
                font=("Segoe UI", 9), fg="#4A5568", bg="white",
                anchor="w").pack(fill="x", pady=(6, 2))

        self._date_entry = tk.Entry(self.content, font=("Consolas", 10),
                                    relief="solid", bd=1)
        self._date_entry.pack(fill="x", ipady=2)
        self._date_entry.bind("<Return>", lambda e: self._do_restore())

        self._status = tk.Label(self.content, text="", font=("Segoe UI", 9),
                                fg="#718096", bg="white", anchor="w")
        self._status.pack(fill="x", pady=(4, 0))

        br = self.button_row()
        br.pack(pady=(6, 0))
        self.button(br, "Восстановить", self._do_restore, primary=True, name="btn_restore")
        self.button(br, "Отмена", self.destroy, primary=False, name="btn_cancel")

    def _do_restore(self):
        self._widgets.get("btn_restore").configure(state="disabled")
        self._status.configure(text="Восстановление...")
        self.update()
        date_param = self._date_entry.get().strip()
        if not date_param and self._snapshots:
            sel = self._listbox.curselection()
            if sel:
                s = self._snapshots[sel[0]]
                m = re.search(r"Snapshot_(\d{8}_\d{6})", s["folder"])
                if m:
                    date_param = m.group(1)
        sp = os.path.dirname(os.path.abspath(__file__))
        rs = os.path.join(sp, "Restore-OpenCode.ps1")
        cmd = ["powershell", "-NoLogo", "-File", rs]
        if date_param:
            cmd += ["-Date", date_param]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            out = result.stdout + result.stderr
            if result.returncode == 0:
                mb.showinfo("Восстановление завершено", out)
            else:
                mb.showerror("Ошибка при восстановлении", out)
        except Exception as ex:
            mb.showerror("Ошибка", str(ex))
        self.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = RestoreDialog()
    dlg.mainloop()
