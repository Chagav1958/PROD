import sys, os, json
import tkinter as tk
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow, _GlossyProgress

class ProgressStateDialog(AppWindow):
    def __init__(self):
        super().__init__(title="AIS Release — Выполнение задач", win_w=460, win_h=280, resizable=False)
        self._state_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "temp", "progress_state.json")
        self._prev_hash = ""
        self._build_ui()

    def _build_ui(self):
        tk.Label(self.content, text="AIS Release — Выполнение задач",
                font=("Segoe UI", 10, "bold"), fg="#1A3A60", bg="white",
                anchor="w").pack(fill="x", pady=(0, 10))

        self._overall_frame = tk.Frame(self.content, bg="white")
        self._overall_frame.pack(fill="x", pady=(0, 6))
        tk.Label(self._overall_frame, text="Общий:", font=("Segoe UI", 9),
                fg="#4A5568", bg="white", width=16, anchor="w").pack(side="left")
        self._overall_bar = _GlossyProgress(self._overall_frame, length=300, phase_bar=True) if hasattr(self, '_overall_bar') else None
        self._overall_bar = _GlossyProgress(self._overall_frame, length=300, phase_bar=True)
        self._overall_bar.pack(side="left", fill="x", expand=True)

        self._task_frame = tk.Frame(self.content, bg="white")
        self._task_frame.pack(fill="x", pady=(0, 6))
        self._task_label = tk.Label(self._task_frame, text="Задача: —", font=("Segoe UI", 9),
                                    fg="#4A5568", bg="white", anchor="w")
        self._task_label.pack(fill="x")

        self._step_frame = tk.Frame(self.content, bg="white")
        self._step_frame.pack(fill="x", pady=(0, 6))
        tk.Label(self._step_frame, text="Текущая:", font=("Segoe UI", 9),
                fg="#4A5568", bg="white", width=16, anchor="w").pack(side="left")
        self._step_bar = _GlossyProgress(self._step_frame, length=300, phase_bar=False)
        self._step_bar.pack(side="left", fill="x", expand=True)

        self._status_label = tk.Label(self.content, text="", font=("Segoe UI", 9),
                                      fg="#718096", bg="white", anchor="w")
        self._status_label.pack(fill="x")

        self._ts_label = tk.Label(self.content, text="", font=("Segoe UI", 8),
                                  fg="#A0AEC0", bg="white", anchor="w")
        self._ts_label.pack(fill="x", pady=(4, 0))

        self.after(500, self._poll)

    def _poll(self):
        if not os.path.isfile(self._state_file):
            self._status_label.configure(text="Ожидание запуска задач...")
            self.after(500, self._poll)
            return
        try:
            with open(self._state_file, "r", encoding="utf-8") as f:
                state = json.load(f)
            h = f"{state.get('task_num','')}|{state.get('step_pct','')}|{state.get('done','')}|{state.get('task_name','')}"
            if h == self._prev_hash:
                self.after(500, self._poll)
                return
            self._prev_hash = h
            if state.get("done"):
                self._status_label.configure(text="✅ Все задачи выполнены!")
                self._overall_bar["value"] = 100
                self._step_bar["value"] = 100
                self._ts_label.configure(text=f"Последнее обновление: {state.get('timestamp','')}")
                self.after(4000, self.destroy)
                return
            total = state.get("task_total", 1)
            num = state.get("task_num", 0)
            overall = int(num / total * 100) if total > 0 else 0
            self._overall_bar["value"] = overall
            self._task_label.configure(text=f"Задача: {num} из {total} — {state.get('task_name','')}")
            step_pct = int(state.get("step_pct", 0))
            self._step_bar["value"] = step_pct
            step_text = state.get("step", "")
            status_text = state.get("status", "")
            lines = []
            if step_text:
                lines.append(f"Шаг: {step_text}")
            if status_text:
                lines.append(f"Статус: {status_text}")
            self._status_label.configure(text=" | ".join(lines) if lines else "")
            self._ts_label.configure(text=f"Обновлено: {state.get('timestamp','')}")
        except:
            self._status_label.configure(text="Ошибка чтения данных...")
        self.after(500, self._poll)

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = ProgressStateDialog()
    dlg.mainloop()
