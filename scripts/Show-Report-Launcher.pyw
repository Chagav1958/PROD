import sys, os, subprocess
import tkinter as tk
from tkinter import ttk
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow

class ReportLauncherDialog(AppWindow):
    def __init__(self):
        super().__init__(title="ОТЧЁТ — ввод задачи", win_w=520, win_h=240, resizable=False)
        self._tasks = self._load_tasks()
        self._build_ui()

    def _load_tasks(self):
        release = r"C:\AIS\1 Release"
        if not os.path.isdir(release):
            return []
        tasks = []
        for d in os.listdir(release):
            dp = os.path.join(release, d)
            if os.path.isdir(dp) and (d.startswith("SYBASE-") or d.startswith("SUPRT-")):
                tasks.append(d)
        tasks.sort(key=lambda x: os.path.getctime(os.path.join(release, x)), reverse=True)
        return tasks

    def _build_ui(self):
        tk.Label(self.content, text="Выберите задачу для формирования отчёта:",
                font=("Segoe UI", 10, "bold"), fg="#4A5568", bg="white",
                anchor="w").pack(fill="x", pady=(0, 8))

        self._combo = ttk.Combobox(self.content, values=self._tasks,
                                   font=("Segoe UI", 10), state="readonly")
        if self._tasks:
            self._combo.current(0)
        self._combo.pack(fill="x", ipady=4)

        tk.Label(self.content, text="История задач из C:\\AIS\\1 Release",
                font=("Segoe UI", 9), fg="#718096", bg="white",
                anchor="w").pack(fill="x", pady=(4, 0))

        br = self.button_row()
        br.pack(pady=(12, 0))
        self.button(br, "Открыть отчёт", self._open_report, primary=True, name="btn_open")
        self.button(br, "Отмена", self.destroy, primary=False, name="btn_cancel")

    def _open_report(self):
        task = self._combo.get()
        if not task:
            return
        sp = os.path.dirname(os.path.abspath(__file__))
        rp = os.path.join(sp, "Show-Report.ps1")
        if os.path.isfile(rp):
            subprocess.Popen(["powershell", "-NoLogo", "-File", rp, "-TaskName", task])
            self.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = ReportLauncherDialog()
    dlg.mainloop()
