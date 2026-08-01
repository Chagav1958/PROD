import sys, os, datetime
import tkinter as tk
from tkinter import ttk, messagebox as mb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow, project_root, _GlossyButton, HAS_PIL

TAB_DEFS = [
    {"name": "Общие", "files": [
        ("AGENTS.md", "AGENTS.md"),
        ("index.mdc", ".opencode/index.mdc"),
        ("project-context.mdc", ".opencode/project-context.mdc"),
        ("general-rules.md", "rules/general-rules.md"),
        ("repository-layout.mdc", ".opencode/repository-layout.mdc"),
        ("rules/index.md", "rules/index.md"),
        ("rules/changelog.md", "rules/changelog.md"),
        ("pending-tasks.md", "rules/pending-tasks.md"),
    ]},
    {"name": "PowerBuilder", "files": [
        ("pb-object-rules.mdc", ".opencode/pb-object-rules.mdc"),
        ("entity-reference.mdc", ".opencode/entity-reference.mdc"),
        ("pb_export_rules.md", "docs/service_rules/pb_export_rules.md"),
    ]},
    {"name": "SQL", "files": [
        ("sql-rules.mdc", ".opencode/sql-rules.mdc"),
        ("db-object-rules.mdc", ".opencode/db-object-rules.mdc"),
        ("sql-rules.md", "rules/sql-rules.md"),
        ("sql_export_rules.md", "docs/service_rules/sql_export_rules.md"),
    ]},
    {"name": "Jira", "files": [
        ("jira-table-rules.mdc", ".opencode/jira-table-rules.mdc"),
        ("jira-rules.md", "rules/jira-rules.md"),
        ("jira_rfc_rules.md", "docs/service_rules/jira_rfc_rules.md"),
    ]},
    {"name": "VSS", "files": [
        ("vss-rules.mdc", ".opencode/vss-rules.mdc"),
        ("vss-rules.md", "rules/vss-rules.md"),
        ("vss_rules.md", "docs/service_rules/vss_rules.md"),
    ]},
    {"name": "GUI", "files": [
        ("gui-rules.md", "rules/gui-rules.md"),
        ("python-gui.mdc", ".opencode/python-gui.mdc"),
    ]},
    {"name": "Тестирование", "files": [
        ("testing-rules.md", "rules/testing-rules.md"),
        ("gui-testing-rule.mdc", ".opencode/gui-testing-rule.mdc"),
    ]},
    {"name": "Сокращения", "files": [
        ("abbreviations.md", "rules/abbreviations.md"),
    ]},
    {"name": "Команды", "files": [
        ("tool-usage.md", "rules/tool-usage.md"),
        ("remember-rule.md", "rules/remember-rule.md"),
        ("russian-language.mdc", ".opencode/russian-language.mdc"),
        ("save-analysis.mdc", ".opencode/save-analysis.mdc"),
        ("save-large-prompts.mdc", ".opencode/save-large-prompts.mdc"),
        ("task-save-results.mdc", ".opencode/task-save-results.mdc"),
        ("markdown-style.mdc", ".opencode/markdown-style.mdc"),
    ]},
    {"name": "Сервисы", "files": [
        ("fix-archive-history.mdc", ".opencode/fix-archive-history.mdc"),
        ("archive-rules.md", "rules/archive-rules.md"),
    ]},
    {"name": "Прочее", "files": [
        ("glossary.mdc", ".opencode/glossary.mdc"),
        ("knowledge.mdc", ".opencode/knowledge.mdc"),
        ("knowledge-first.mdc", ".opencode/knowledge-first.mdc"),
        ("preflight.mdc", ".opencode/preflight.mdc"),
    ]},
]

class RulesDialog(AppWindow):
    def __init__(self):
        self._base = project_root()
        total = sum(len(t["files"]) for t in TAB_DEFS)
        super().__init__(title="Правила проекта AIS", win_w=960, win_h=640)
        self._build_ui(total)

    def _redraw(self):
        try:
            self.update_idletasks()
        except:
            pass

    def _build_ui(self, total):
        # Header
        hdr = tk.Label(self.content, text=f"Файлы-правила проекта AIS ({total} файлов)",
                       font=("Segoe UI", 10, "bold"), fg="#1A3A60", bg="white", anchor="w")
        hdr.pack(fill="x", padx=0, pady=(0, 4))

        # Main tabs
        self.bind("<Configure>", lambda e: self.after(10, self._redraw))
        self._main_nb = ttk.Notebook(self.content)
        self._main_nb.pack(fill="both", expand=True)

        self._sub_nbs = []  # per main tab: sub Notebook
        self._all_files = []  # list of (full_path, display_name) for ALL files
        self._txt_widgets = []  # list of (main_idx, sub_nb, txt_widget, fname)
        self._search_state = {"query": "", "results": [], "idx": -1}

        for ti, tab_def in enumerate(TAB_DEFS):
            main_page = tk.Frame(self._main_nb, bg="white")
            lbl = f"{tab_def['name']} ({len(tab_def['files'])})"
            self._main_nb.add(main_page, text=lbl)

            # Sub-tabs
            sub_nb = ttk.Notebook(main_page)
            sub_nb.pack(fill="both", expand=True)
            self._sub_nbs.append(sub_nb)

            for fname, fpath in tab_def["files"]:
                full = os.path.join(self._base, fpath)
                self._all_files.append((full, fname))

                sub_page = tk.Frame(sub_nb, bg="white")
                sub_nb.add(sub_page, text=fname)

                # File info bar
                info = tk.Frame(sub_page, bg="white")
                info.pack(fill="x", padx=4, pady=(2, 0))
                info_str = fname
                if os.path.isfile(full):
                    sz = os.path.getsize(full)
                    if sz < 1024:
                        sz_str = f"{sz} B"
                    elif sz < 1024*1024:
                        sz_str = f"{sz/1024:.1f} KB"
                    else:
                        sz_str = f"{sz/1024/1024:.1f} MB"
                    dt_str = datetime.datetime.fromtimestamp(os.path.getmtime(full)).strftime("%d.%m.%Y %H:%M")
                    info_str = f"{fname} | {sz_str} | {dt_str}"
                tk.Label(info, text=info_str, font=("Segoe UI", 9), fg="#4A5568", bg="white",
                        anchor="w").pack(fill="x")

                # Text content
                txt_frame = tk.Frame(sub_page, bg="white")
                txt_frame.pack(fill="both", expand=True, padx=4, pady=(2, 0))

                txt = tk.Text(txt_frame, font=("Consolas", 10), wrap="none",
                              relief="solid", bd=1, state="disabled")
                if os.path.isfile(full):
                    with open(full, "r", encoding="utf-8", errors="replace") as f:
                        content = f.read()
                    txt.config(state="normal")
                    txt.insert("1.0", content)
                    txt.config(state="disabled")

                hsb = ttk.Scrollbar(txt_frame, orient="horizontal", command=txt.xview)
                vsb = ttk.Scrollbar(txt_frame, orient="vertical", command=txt.yview)
                txt.configure(xscrollcommand=hsb.set, yscrollcommand=vsb.set)
                txt.grid(row=0, column=0, sticky="nsew")
                vsb.grid(row=0, column=1, sticky="ns")
                hsb.grid(row=1, column=0, sticky="ew")
                txt_frame.grid_rowconfigure(0, weight=1)
                txt_frame.grid_columnconfigure(0, weight=1)
                self._txt_widgets.append((ti, sub_nb, txt, fname))

        # Bottom bar: search + edit button
        bottom = tk.Frame(self.content, bg="white")
        bottom.pack(fill="x", pady=(6, 0))

        # Search
        sp = tk.Frame(bottom, bg="white")
        sp.pack(side="left", fill="x", expand=True)

        tk.Label(sp, text="Поиск:", font=("Segoe UI", 9), fg="#4A5568", bg="white").pack(side="left")

        self._sv = tk.StringVar()
        se = tk.Entry(sp, textvariable=self._sv, font=("Segoe UI", 9),
                relief="solid", bd=1, width=30)
        se.pack(side="left", padx=(4, 6), ipady=2)
        se.bind("<Return>", lambda e: self._search_down())
        se.bind("<Key>", lambda e: self.after(50, self._search_reset))

        self._match_lbl = tk.Label(sp, text="0 - 0", font=("Segoe UI", 9),
                                   fg="#4A5568", bg="white", width=8, anchor="w")
        self._match_lbl.pack(side="left")

        if HAS_PIL:
            self._btn_down = _GlossyButton(sp, "▼", self._search_down, width=30, height=24, primary=False)
            self._btn_down.pack(side="left", padx=(0, 2))
            self._btn_up = _GlossyButton(sp, "▲", self._search_up, width=30, height=24, primary=False)
            self._btn_up.pack(side="left")
        else:
            tk.Button(sp, text="▼", font=("Segoe UI", 9, "bold"), bg="#F5F7FA",
                     relief="solid", bd=1, padx=4, cursor="hand2",
                     command=self._search_down).pack(side="left", padx=(0, 2))
            tk.Button(sp, text="▲", font=("Segoe UI", 9, "bold"), bg="#F5F7FA",
                     relief="solid", bd=1, padx=4, cursor="hand2",
                     command=self._search_up).pack(side="left")

        # Edit button
        if HAS_PIL:
            _GlossyButton(bottom, "Редактировать", self._toggle_edit,
                         width=120, height=32, primary=True).pack(side="right", padx=(8, 0))
        else:
            tk.Button(bottom, text="Редактировать", font=("Segoe UI", 9, "bold"),
                     bg="#2B6CB0", fg="white", relief="flat", padx=12, pady=4,
                     cursor="hand2", command=self._toggle_edit).pack(side="right", padx=(8, 0))

    def _search_reset(self):
        self._search_state = {"query": "", "results": [], "idx": -1}

    def _search_down(self):
        q = self._sv.get()
        if not q:
            return
        st = self._search_state
        if st["query"] != q:
            st["query"] = q
            st["results"] = []
            st["idx"] = -1
        if not st["results"]:
            for mi, sub_nb, txt, fname in self._txt_widgets:
                content = txt.get("1.0", "end")
                ql = q.lower()
                start = "1.0"
                while True:
                    pos = txt.search(q, start, stopindex="end", nocase=True)
                    if not pos:
                        break
                    st["results"].append((mi, sub_nb, txt, pos, fname))
                    start = f"{pos}+1c"
            st["idx"] = -1
        if not st["results"]:
            self._match_lbl.configure(text="0 - 0")
            return
        st["idx"] = (st["idx"] + 1) % len(st["results"])
        self._goto_result(st["results"][st["idx"]])
        self._match_lbl.configure(text=f"{st['idx']+1} - {len(st['results'])}")

    def _search_up(self):
        q = self._sv.get()
        if not q:
            return
        st = self._search_state
        if st["query"] != q:
            self._search_down()
            return
        if not st["results"]:
            return
        st["idx"] = (st["idx"] - 1) % len(st["results"])
        self._goto_result(st["results"][st["idx"]])
        self._match_lbl.configure(text=f"{st['idx']+1} - {len(st['results'])}")

    def _goto_result(self, result):
        mi, sub_nb, txt, pos, fname = result
        self._main_nb.select(mi)
        sub_nb.select(txt.master.master)
        txt.config(state="normal")
        txt.tag_remove("sel", "1.0", "end")
        line = pos.split(".")[0]
        txt.mark_set("insert", pos)
        txt.see(pos)
        txt.tag_add("sel", pos, f"{pos}+{len(self._sv.get())}c")
        txt.config(state="disabled")
        txt.focus_set()

    def _toggle_edit(self):
        pass

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = RulesDialog()
    dlg.mainloop()
