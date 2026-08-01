import sys, os, json, subprocess
import tkinter as tk
from tkinter import ttk, messagebox as mb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow

class TaskPlanGUIDialog(AppWindow):
    def __init__(self):
        super().__init__(title="TaskPlan — Управление планами задач", win_w=900, win_h=600)
        self._base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self._sp = os.path.dirname(os.path.abspath(__file__))
        self._plans_dir = os.path.join(self._base, "plans")
        self._build_ui()

    def _run_ps(self, script, *args):
        fp = os.path.join(self._sp, script)
        if not os.path.isfile(fp):
            return f"Скрипт не найден: {fp}"
        try:
            cmd = ["powershell", "-NoLogo", "-File", fp] + list(args)
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            return r.stdout + r.stderr
        except Exception as ex:
            return str(ex)

    def _build_ui(self):
        nb = ttk.Notebook(self.content)
        nb.pack(fill="both", expand=True, padx=4, pady=4)

        # Tab 0: Список задач
        t0 = tk.Frame(nb, bg="white")
        nb.add(t0, text="Список задач")
        tk.Label(t0, text="Планы задач:", font=("Segoe UI", 10, "bold"),
                fg="#4A5568", bg="white", anchor="w").pack(fill="x", pady=(0, 4))
        plans = []
        if os.path.isdir(self._plans_dir):
            plans = [d for d in os.listdir(self._plans_dir) if os.path.isdir(os.path.join(self._plans_dir, d))]
        self._plan_combo = ttk.Combobox(t0, values=plans, font=("Segoe UI", 10), state="readonly")
        self._plan_combo.pack(fill="x", ipady=4)
        self._plan_out = tk.Text(t0, font=("Consolas", 9), height=10, relief="solid", bd=1)
        self._plan_out.pack(fill="both", expand=True, pady=(4, 0))
        br0 = tk.Frame(t0, bg="white")
        br0.pack(pady=(6, 0))
        tk.Button(br0, text="След. этап", command=self._next_stage,
                 font=("Segoe UI", 9, "bold"), bg="#2B6CB0", fg="white",
                 relief="flat", padx=12, pady=4, cursor="hand2").pack(side="left", padx=2)
        tk.Button(br0, text="Подг. бриф", command=self._prepare_brief,
                 font=("Segoe UI", 9, "bold"), bg="#2B6CB0", fg="white",
                 relief="flat", padx=12, pady=4, cursor="hand2").pack(side="left", padx=2)

        # Tab 1: Тесты
        t1 = tk.Frame(nb, bg="white")
        nb.add(t1, text="Тесты")
        tk.Label(t1, text="Результаты тестов:", font=("Segoe UI", 10, "bold"),
                fg="#4A5568", bg="white", anchor="w").pack(fill="x", pady=(0, 4))
        self._test_out = tk.Text(t1, font=("Consolas", 9), relief="solid", bd=1)
        self._test_out.pack(fill="both", expand=True)
        br1 = tk.Frame(t1, bg="white")
        br1.pack(pady=(6, 0))
        tk.Button(br1, text="Запустить тесты", command=self._run_tests,
                 font=("Segoe UI", 9, "bold"), bg="#2B6CB0", fg="white",
                 relief="flat", padx=12, pady=4, cursor="hand2").pack(side="left")

        # Tab 2: Импорт
        t2 = tk.Frame(nb, bg="white")
        nb.add(t2, text="Импорт")
        tk.Label(t2, text="Импорт данных из TASK", font=("Segoe UI", 10, "bold"),
                fg="#4A5568", bg="white", anchor="w").pack(fill="x", pady=(0, 4))
        self._import_out = tk.Text(t2, font=("Consolas", 9), relief="solid", bd=1)
        self._import_out.pack(fill="both", expand=True)
        br2 = tk.Frame(t2, bg="white")
        br2.pack(pady=(6, 0))
        tk.Button(br2, text="Импорт", command=self._do_import,
                 font=("Segoe UI", 9, "bold"), bg="#2B6CB0", fg="white",
                 relief="flat", padx=12, pady=4, cursor="hand2").pack(side="left")

    def _append(self, widget, text):
        widget.insert("end", text + "\n")
        widget.see("end")

    def _next_stage(self):
        plan = self._plan_combo.get()
        if not plan:
            mb.showwarning("Выбор", "Выберите план")
            return
        result = self._run_ps("TaskPlan-Manager.ps1", "-Action", "NextStage", "-Plan", plan)
        self._append(self._plan_out, result)

    def _prepare_brief(self):
        plan = self._plan_combo.get()
        if not plan:
            mb.showwarning("Выбор", "Выберите план")
            return
        result = self._run_ps("TaskPlan-PrepareBrief.ps1", "-Plan", plan)
        self._append(self._plan_out, result)

    def _run_tests(self):
        self._test_out.delete("1.0", "end")
        result = self._run_ps("TaskPlan-Tests.ps1")
        self._append(self._test_out, result)

    def _do_import(self):
        self._import_out.delete("1.0", "end")
        result = self._run_ps("TaskPlan-Manager.ps1", "-Action", "Import")
        self._append(self._import_out, result)

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = TaskPlanGUIDialog()
    dlg.mainloop()
