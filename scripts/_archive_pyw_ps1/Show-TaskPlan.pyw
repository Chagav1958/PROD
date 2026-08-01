import sys, os, subprocess
import tkinter as tk
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow

class TaskPlanDialog(AppWindow):
    def __init__(self):
        super().__init__(title="TaskPlan", win_w=380, win_h=160, resizable=False)
        self._build_ui()

    def _build_ui(self):
        tk.Label(self.content, text="Запуск TaskPlan...",
                font=("Segoe UI", 10), fg="#4A5568", bg="white",
                anchor="w").pack(fill="x", pady=(20, 10))
        self._status = tk.Label(self.content, text="", font=("Segoe UI", 9),
                                fg="#718096", bg="white", anchor="w")
        self._status.pack(fill="x")
        br = self.button_row()
        br.pack(pady=(10, 0))
        self.button(br, "Запустить", self._launch, primary=True, name="btn_start")
        self.button(br, "Отмена", self.destroy, primary=False, name="btn_cancel")

    def _launch(self):
        sp = os.path.dirname(os.path.abspath(__file__))
        gui = os.path.join(sp, "Show-TaskPlanGUI.ps1")
        if os.path.isfile(gui):
            subprocess.Popen(["powershell", "-NoLogo", "-WindowStyle", "Hidden", "-File", gui])
            self.destroy()
        else:
            self._status.configure(text="Show-TaskPlanGUI.ps1 не найден")

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = TaskPlanDialog()
    dlg.mainloop()
