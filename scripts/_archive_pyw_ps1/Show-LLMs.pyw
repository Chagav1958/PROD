import sys, os, json, re, urllib.request, urllib.error, socket
import tkinter as tk
from tkinter import ttk, messagebox as mb
import threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow, project_root

class LLMsDialog(AppWindow):
    def __init__(self):
        super().__init__(title="LLM Провайдеры", win_w=960, win_h=640)
        self._base = project_root()
        self._results = {}
        self._load_config()
        self._build_ui()
        self._cache_file = os.path.join(self._base, "temp", "llm_test_results.json")

    def _load_config(self):
        self._providers = []
        for fn in ["opencode.jsonc", "opencode.json"]:
            fp = os.path.join(self._base, fn)
            if os.path.isfile(fp):
                with open(fp, "r", encoding="utf-8") as f:
                    txt = f.read()
                txt = re.sub(r"//.*", "", txt)
                cfg = json.loads(txt)
                break
        else:
            return
        provs = cfg.get("providers", {})
        for name, p in provs.items():
            models = p.get("models", [])
            for m in models:
                self._providers.append({"provider": name, "model": m, "api": p.get("api", "")})

    def _build_ui(self):
        # Splash-like status
        tk.Label(self.content, text="LLM Провайдеры и модели",
                font=("Segoe UI", 10, "bold"), fg="#4A5568", bg="white",
                anchor="w").pack(fill="x", pady=(0, 4))
        self._status = tk.Label(self.content, text="Загрузка...", font=("Segoe UI", 9),
                                fg="#718096", bg="white", anchor="w")
        self._status.pack(fill="x")

        f = tk.Frame(self.content, bg="white")
        f.pack(fill="both", expand=True, pady=(4, 0))

        cols = ("provider", "model", "api", "status")
        self._tree = ttk.Treeview(f, columns=cols, show="headings", selectmode="browse")
        for c, h, w in [("provider", "Провайдер", 120), ("model", "Модель", 200),
                         ("api", "API", 100), ("status", "Статус", 80)]:
            self._tree.heading(c, text=h)
            self._tree.column(c, width=w, minwidth=40)
        self._tree.tag_configure("ok", foreground="#48BB78")
        self._tree.tag_configure("fail", foreground="#E53E3E")
        self._tree.pack(fill="both", expand=True, side="left")

        vsb = ttk.Scrollbar(f, orient="vertical", command=self._tree.yview)
        vsb.pack(side="right", fill="y")
        self._tree.configure(yscrollcommand=vsb.set)

        br = self.button_row()
        br.pack(pady=(6, 0))
        self.button(br, "Тестировать всё", self._test_all, primary=True, name="btn_test")
        self.button(br, "Закрыть", self.destroy, primary=False, name="btn_close")

        self._populate()

    def _populate(self, results=None):
        self._tree.delete(*self._tree.get_children())
        items = self._providers
        if results is None:
            results = self._results
        for idx, p in enumerate(items):
            key = f"{p['provider']}/{p['model']}"
            s = results.get(key, "")
            tag = ""
            if s == "OK":
                tag = "ok"
            elif s:
                tag = "fail"
            self._tree.insert("", "end", values=(p["provider"], p["model"], p["api"] or "-", s or "-"),
                             tags=(tag,) if tag else ())
        self._status.configure(text=f"{len(items)} моделей | {len([v for v in results.values() if v == 'OK'])} OK")

    def _test_all(self):
        self._widgets.get("btn_test").configure(state="disabled")
        self._results = {}
        self._populate()
        threading.Thread(target=self._do_test_all, daemon=True).start()

    def _do_test_all(self):
        for i, p in enumerate(self._providers):
            key = f"{p['provider']}/{p['model']}"
            ok = self._test_one(p)
            self._results[key] = "OK" if ok else f"FAIL"
            self.after(0, self._populate)
        self._cache_results()
        self.after(0, lambda: self._widgets.get("btn_test").configure(state="normal"))

    def _test_one(self, prov):
        api = prov.get("api", "")
        model = prov.get("model", "")
        if not api:
            return False
        try:
            url = api.rstrip("/")
            if "ollama" in api.lower():
                url += "/api/tags"
                req = urllib.request.Request(url)
            elif "openai" in api.lower() or "router" in api.lower() or "anthropic" in api.lower():
                url += "/models"
                req = urllib.request.Request(url)
            else:
                req = urllib.request.Request(url)
            req.timeout = 5
            with urllib.request.urlopen(req) as r:
                return r.status == 200
        except:
            return False

    def _cache_results(self):
        try:
            with open(self._cache_file, "w", encoding="utf-8") as f:
                json.dump(self._results, f, indent=2)
        except:
            pass

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = LLMsDialog()
    dlg.mainloop()
