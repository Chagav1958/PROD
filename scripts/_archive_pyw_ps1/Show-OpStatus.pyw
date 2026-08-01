import sys, os, json
import tkinter as tk
from tkinter import ttk, messagebox as mb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gui_lib import AppWindow

STATUS_MAP = {"EDIT": "#ECC94B", "FIXED": "#48BB78", "READY": "#3182CE", "DIFF": "#E53E3E", "NEW_OBJECT": "#805AD5"}

class OpStatusDialog(AppWindow):
    def __init__(self):
        super().__init__(title="FIXSHOW - Статусы объектов", win_w=920, win_h=520)
        self._base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self._reg_file = os.path.join(self._base, "config", "status_registry.json")
        self._lay_file = os.path.join(self._base, "config", "fixshow_layout.json")
        self._registry = self._load_registry()
        self._original = json.dumps(self._registry) if self._registry else ""
        self._auto_register()
        self._data = self._build_list()
        self._build_ui()
        self._restore_geometry()

    def _load_registry(self):
        if os.path.isfile(self._reg_file):
            with open(self._reg_file, "r", encoding="utf-8") as f:
                return json.load(f)
        return {"objects": {}}

    def _auto_register(self):
        sp = os.path.join(self._base, "scripts")
        known = set()
        for fn in os.listdir(sp):
            if fn.startswith("Show-") or fn == "VSS-History-Show.ps1":
                known.add(fn.replace(".ps1", "").replace(".pyw", ""))
        bp = os.path.join(self._base, "bin")
        if os.path.isdir(bp):
            for fn in os.listdir(bp):
                if fn.startswith("Show-") or fn == "Prod-GUI.ps1":
                    known.add(fn.replace(".ps1", "").replace(".pyw", ""))
        changed = False
        for k in known:
            if k not in self._registry["objects"]:
                name = k.replace("Show-", "").replace("Prod-GUI", "МОРДА (главное окно)").replace("VSS-History-Show", "ДО VSS: История")
                self._registry["objects"][k] = {"id": k, "type": "ДО", "name": name, "status": "EDIT"}
                changed = True
        if changed:
            self._save_registry()

    def _build_list(self):
        data = []
        for key, obj in self._registry["objects"].items():
            data.append({"id": obj.get("id", key), "type": obj.get("type", ""),
                         "name": obj.get("name", ""), "status": obj.get("status", "")})
        return data

    def _save_registry(self):
        with open(self._reg_file, "w", encoding="utf-8") as f:
            json.dump(self._registry, f, ensure_ascii=False, indent=2)

    def _restore_geometry(self):
        if os.path.isfile(self._lay_file):
            try:
                with open(self._lay_file, "r", encoding="utf-8") as f:
                    lay = json.load(f)
                if lay.get("Width", 0) >= 400 and lay.get("Height", 0) >= 300:
                    geo = f"{lay['Width']}x{lay['Height']}"
                    if lay.get("Left") is not None and lay.get("Top") is not None:
                        geo += f"+{lay['Left']}+{lay['Top']}"
                    self.geometry(geo)
            except:
                pass

    def _save_geometry(self):
        g = self.geometry()
        import re
        m = re.match(r"(\d+)x(\d+)[+]?(-?\d+)[+]?(-?\d+)", g)
        if m:
            lay = {"Width": int(m.group(1)), "Height": int(m.group(2)),
                   "Left": int(m.group(3)), "Top": int(m.group(4))}
            with open(self._lay_file, "w", encoding="utf-8") as f:
                json.dump(lay, f, indent=2)

    def _build_ui(self):
        top = tk.Frame(self.content, bg="white")
        top.pack(fill="both", expand=True, padx=8, pady=8)

        cols = ("id", "type", "name", "status")
        headers = {"id": "ID", "type": "Тип", "name": "Имя", "status": "Статус"}
        widths = {"id": 120, "type": 50, "name": 320, "status": 100}

        self._tree = ttk.Treeview(top, columns=cols, show="headings", selectmode="browse")
        for c in cols:
            self._tree.heading(c, text=headers[c])
            self._tree.column(c, width=widths[c], minwidth=40)
        self._tree.tag_configure("alt", background="#F5F7FA")
        for idx, row in enumerate(self._data):
            tag = "alt" if idx % 2 else ""
            self._tree.insert("", "end", values=(row["id"], row["type"], row["name"], row["status"]),
                             tags=(tag,) if tag else ())
        self._tree.pack(fill="both", expand=True, side="left")

        vsb = ttk.Scrollbar(top, orient="vertical", command=self._tree.yview)
        vsb.pack(side="right", fill="y")
        self._tree.configure(yscrollcommand=vsb.set)

        # Buttons
        br = self.button_row()
        br.pack(pady=(6, 0))
        for txt, cmd, prim in [("FIX", self._set_fix, True), ("FIXED", self._set_fixed, True),
                               ("EDIT", self._set_edit, False), ("BACK", self._set_back, True),
                               ("Отмена", self.destroy, False)]:
            self.button(br, txt, cmd, primary=prim)

    def _get_selected(self):
        sel = self._tree.selection()
        if not sel:
            mb.showwarning("Выбор", "Выберите объект в таблице")
            return None
        item = self._tree.item(sel[0])
        return {"id": item["values"][0], "type": item["values"][1],
                "name": item["values"][2], "status": item["values"][3],
                "iid": sel[0]}

    def _update_status(self, new_status):
        obj = self._get_selected()
        if not obj:
            return
        oid = obj["id"]
        if oid in self._registry["objects"]:
            self._registry["objects"][oid]["status"] = new_status
            self._save_registry()
            self._tree.item(obj["iid"], values=(obj["id"], obj["type"], obj["name"], new_status))

    def _set_fix(self):
        self._update_status("FIX")

    def _set_fixed(self):
        self._update_status("FIXED")

    def _set_edit(self):
        self._update_status("EDIT")

    def _set_back(self):
        self._update_status("BACK")

if __name__ == "__main__":
    root = tk.Tk()
    root.withdraw()
    dlg = OpStatusDialog()
    root.mainloop()
