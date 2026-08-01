import sys, os, json
import tkinter as tk
from tkinter import ttk
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow, project_root

class AbbreviationsDialog(AppWindow):
    def __init__(self):
        super().__init__(title="Сокращения AIS Release", win_w=900, win_h=600)
        self._load_data()
        self._build_ui()

    def _load_data(self):
        jp = os.path.join(project_root(), "config", "abbreviations_data.json")
        with open(jp, "r", encoding="utf-8") as f:
            self._tabs_data = json.load(f)

    def _build_ui(self):
        # Search panel (global, across all tabs)
        sp = tk.Frame(self.content, bg="white")
        sp.pack(fill="x", pady=(20, 4))

        self._match_label = tk.Label(sp, text="0", font=("Segoe UI", 9, "bold"),
                                     fg="#4A5568", bg="white", width=6, anchor="w")
        self._match_label.pack(side="left")

        self._sv = tk.StringVar()
        self._sv.trace("w", lambda *a: self._filter_all())
        tk.Entry(sp, textvariable=self._sv, font=("Segoe UI", 9),
                relief="solid", bd=1, width=40).pack(side="left", fill="x", expand=True, padx=(0, 4), ipady=2)

        def on_down():
            n = self._search_next(1)
        def on_up():
            n = self._search_next(-1)
        self._btn_down = tk.Button(sp, text="▼", command=on_down,
                                  font=("Segoe UI", 9, "bold"), bg="#F5F7FA",
                                  relief="solid", bd=1, padx=4, cursor="hand2")
        self._btn_down.pack(side="left", padx=(0, 2))
        self._btn_up = tk.Button(sp, text="▲", command=on_up,
                                font=("Segoe UI", 9, "bold"), bg="#F5F7FA",
                                relief="solid", bd=1, padx=4, cursor="hand2")
        self._btn_up.pack(side="left")

        # Notebook
        self._nb = ttk.Notebook(self.content)
        self._nb.pack(fill="both", expand=True)

        self._trees = []  # (tree, items_data, tab_name)
        for tab in self._tabs_data:
            tab_frame = tk.Frame(self._nb, bg="white")
            self._nb.add(tab_frame, text=f"{tab['Header']} ({len(tab['Data'])})")

            cols = list(range(len(tab["Headers"])))
            tree = ttk.Treeview(tab_frame, columns=cols, show="headings", selectmode="extended")
            for i, h in enumerate(tab["Headers"]):
                tree.heading(i, text=h, command=lambda c=i, t=tree: self._sort(t, c, False))
                tree.column(i, width=120, minwidth=60)
            tree.tag_configure("alt", background="#F5F7FA")

            items = []
            for row in tab["Data"]:
                items.append(tuple(str(row.get(c, "")) for c in tab["Columns"]))

            tree.pack(fill="both", expand=True, side="left")
            vsb = ttk.Scrollbar(tab_frame, orient="vertical", command=tree.yview)
            vsb.pack(side="right", fill="y")
            tree.configure(yscrollcommand=vsb.set)

            self._trees.append({"tree": tree, "items": items, "name": tab["Header"]})
            self._populate(tree, items)

        self._search_state = {"query": "", "results": [], "idx": -1}

    def _populate(self, tree, items):
        tree.delete(*tree.get_children())
        for idx, row in enumerate(items):
            tag = "alt" if idx % 2 else ""
            tree.insert("", "end", values=row, tags=(tag,) if tag else ())

    def _filter_all(self):
        q = self._sv.get().lower()
        total = 0
        for td in self._trees:
            if not q:
                self._populate(td["tree"], td["items"])
                total += len(td["items"])
            else:
                filt = [r for r in td["items"] if any(q in str(v).lower() for v in r)]
                self._populate(td["tree"], filt)
                total += len(filt)
        self._match_label.configure(text=str(total))
        self._search_state = {"query": q, "results": [], "idx": -1}

    def _search_next(self, direction):
        q = self._sv.get().lower()
        if not q:
            return
        st = self._search_state
        if st["query"] != q:
            st["query"] = q
            st["results"] = []
            st["idx"] = -1
        if not st["results"]:
            for ti, td in enumerate(self._trees):
                for item in td["tree"].get_children(""):
                    vals = td["tree"].item(item, "values")
                    if any(q in str(v).lower() for v in vals):
                        st["results"].append((ti, item))
            st["idx"] = -1 if direction == 1 else len(st["results"])
        if not st["results"]:
            return
        st["idx"] = (st["idx"] + direction) % len(st["results"])
        ti, item = st["results"][st["idx"]]
        self._nb.select(ti)
        td = self._trees[ti]
        td["tree"].selection_set(item)
        td["tree"].focus(item)
        td["tree"].see(item)
        self._match_label.configure(text=f"{st['idx']+1}/{len(st['results'])}")

    def _sort(self, tree, col, reverse):
        items = [(tree.set(item, col), item) for item in tree.get_children("")]
        items.sort(key=lambda x: str(x[0]).lower(), reverse=reverse)
        for idx, (_, item) in enumerate(items):
            tree.move(item, "", idx)
            tag = "alt" if idx % 2 else ""
            tree.item(item, tags=(tag,) if tag else ())
        tree.heading(col, command=lambda: self._sort(tree, col, not reverse))

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = AbbreviationsDialog()
    dlg.mainloop()
