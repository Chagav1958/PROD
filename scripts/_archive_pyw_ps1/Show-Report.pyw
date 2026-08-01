import sys, os, json, re, datetime, shutil
import tkinter as tk
from tkinter import ttk, messagebox as mb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow

class ReportDialog(AppWindow):
    def __init__(self, task_name=""):
        self._task_name = task_name
        title = f"ОТЧЁТ: {task_name}" if task_name else "ОТЧЁТ"
        super().__init__(title=title, win_w=960, win_h=640)
        self._base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self._release_root = r"C:\AIS\1 Release"
        self._task_path = self._find_task()
        self._lay_file = os.path.join(self._base, "config", "report_layout.json")
        self._data = self._scan_task() if self._task_path else {}
        self._build_ui()
        self._restore_geometry()

    def _find_task(self):
        if not self._task_name:
            return None
        if os.path.isdir(os.path.join(self._release_root, self._task_name)):
            return os.path.join(self._release_root, self._task_name)
        candidates = []
        if os.path.isdir(self._release_root):
            for d in os.listdir(self._release_root):
                if d.startswith(self._task_name) or d == self._task_name:
                    candidates.append(os.path.join(self._release_root, d))
        candidates.sort(key=lambda x: os.path.getctime(x), reverse=True)
        return candidates[0] if candidates else None

    def _scan_task(self):
        if not self._task_path:
            return {}
        data = {"changed": [], "pb_ide": [], "ready": [], "structure": []}
        for root, dirs, files in os.walk(self._task_path):
            for f in files:
                fp = os.path.join(root, f)
                rel = os.path.relpath(fp, self._task_path)
                size = os.path.getsize(fp)
                ext = os.path.splitext(f)[1]
                entry = {"file": rel, "ext": ext, "size": size, "path": fp}
                if f.endswith(".sr?"):
                    data["changed"].append(entry)
                data["structure"].append(entry)
        return data

    def _restore_geometry(self):
        if os.path.isfile(self._lay_file):
            try:
                with open(self._lay_file, "r", encoding="utf-8") as f:
                    lay = json.load(f)
                if lay.get("Width", 0) >= 400 and lay.get("Height", 0) >= 300:
                    geo = f"{lay['Width']}x{lay['Height']}"
                    if lay.get("Left") is not None:
                        geo += f"+{lay['Left']}+{lay.get('Top', 0)}"
                    self.geometry(geo)
            except:
                pass

    def _save_geometry(self):
        g = self.geometry()
        m = re.match(r"(\d+)x(\d+)[+]?(-?\d+)[+]?(-?\d+)", g)
        if m:
            lay = {"Width": int(m.group(1)), "Height": int(m.group(2)),
                   "Left": int(m.group(3)), "Top": int(m.group(4))}
            with open(self._lay_file, "w", encoding="utf-8") as f:
                json.dump(lay, f, indent=2)

    def _build_ui(self):
        if not self._task_path:
            tk.Label(self.content, text=f"Задача '{self._task_name}' не найдена в {self._release_root}",
                    font=("Segoe UI", 10), fg="#E53E3E", bg="white").pack(pady=40)
            br = self.button_row()
            br.pack(pady=(6, 0))
            self.button(br, "Закрыть", self.destroy, primary=False)
            return

        nb = ttk.Notebook(self.content)
        nb.pack(fill="both", expand=True, padx=4, pady=4)

        tabs = [
            ("Изменённые объекты", self._make_grid, self._data.get("changed", [])),
            ("Структура задачи", self._make_grid, self._data.get("structure", [])),
        ]
        for title, maker, data in tabs:
            page = tk.Frame(nb, bg="white")
            nb.add(page, text=f"{title} ({len(data)})")
            maker(page, data)

        # Buttons
        br = self.button_row()
        br.pack(pady=(6, 0))
        self.button(br, "Создать архив", self._create_archive, primary=True, name="btn_archive")
        self.button(br, "Закрыть", self.destroy, primary=False, name="btn_close")

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _make_grid(self, parent, data):
        if not data:
            tk.Label(parent, text="Нет данных", font=("Segoe UI", 10),
                    fg="#718096", bg="white").pack(pady=20)
            return
        cols = ("file", "ext", "size")
        headers = {"file": "Файл", "ext": "Тип", "size": "Размер"}
        widths = {"file": 500, "ext": 60, "size": 100}
        tree = ttk.Treeview(parent, columns=cols, show="headings", selectmode="browse")
        for c in cols:
            tree.heading(c, text=headers[c])
            tree.column(c, width=widths[c], minwidth=40)
        tree.tag_configure("alt", background="#F5F7FA")
        for idx, row in enumerate(data):
            tag = "alt" if idx % 2 else ""
            tree.insert("", "end", values=(row["file"], row["ext"], f"{row['size']:,} B"),
                       tags=(tag,) if tag else ())
        tree.pack(fill="both", expand=True, side="left")
        vsb = ttk.Scrollbar(parent, orient="vertical", command=tree.yview)
        vsb.pack(side="right", fill="y")
        tree.configure(yscrollcommand=vsb.set)

    def _create_archive(self):
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        dest = os.path.join(self._base, "archives", "REPORT", f"{self._task_name}_{ts}")
        os.makedirs(dest, exist_ok=True)
        try:
            import subprocess
            cmd = ["powershell", "-NoLogo", "Copy-Item", f"'{self._task_path}\\*'", f"'-Destination'", f"'{dest}'", "-Recurse"]
            subprocess.run(["powershell", "-NoLogo",
                           f"Copy-Item '{self._task_path}\\*' -Destination '{dest}' -Recurse -Force"],
                          capture_output=True, timeout=60)
            mb.showinfo("Архив", f"Архив создан:\n{dest}")
        except Exception as ex:
            mb.showerror("Ошибка", str(ex))

    def _on_close(self):
        self._save_geometry()
        self.destroy()

if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else ""
    root = tk.Tk()
    root.withdraw()
    dlg = ReportDialog(task_name=name)
    dlg.mainloop()
