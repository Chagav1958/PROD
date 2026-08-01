import tkinter as tk
from tkinter import ttk
import os, sys, json, math

try:
    from PIL import Image, ImageTk
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

try:
    import win32api, win32con, win32gui
    HAS_WIN32 = True
except ImportError:
    HAS_WIN32 = False

C_DARK_BLUE = "#1A3A60"
C_MID_BLUE = "#2B6CB0"
C_LIGHT_BLUE = "#87CEEB"
C_WHITE = "#FFFFFF"
C_LIGHT_BG = "#F5F7FA"
C_BORDER = "#CBD5E0"
C_TEXT = "#4A5568"
C_TEXT_MUTED = "#718096"
C_CLOSE_RED = "#E81123"
C_SEARCH_BLUE = "#3182CE"
C_TITLE_BG = "#1A3A60"
C_BTN_OK_TOP = "#2A5080"
C_BTN_OK_BOT = "#87CEEB"
C_BTN_CANCEL_TOP = "#606060"
C_BTN_CANCEL_BOT = "#909090"
C_TITLE_SHADOW = "#6B8DB0"

EDGE_MARGIN = 6
EDGE_TOP = 1; EDGE_BOTTOM = 2; EDGE_LEFT = 4; EDGE_RIGHT = 8
EDGE_TOPLEFT = 5; EDGE_TOPRIGHT = 9; EDGE_BOTTOMLEFT = 6; EDGE_BOTTOMRIGHT = 10
EDGE_NONE = 0

def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(r, g, b):
    return f"#{r:02x}{g:02x}{b:02x}"

def blend_hex(c1, c2, alpha):
    r1, g1, b1 = hex_to_rgb(c1)
    r2, g2, b2 = hex_to_rgb(c2)
    r = int(r1 * alpha + r2 * (1 - alpha))
    g = int(g1 * alpha + g2 * (1 - alpha))
    b = int(b1 * alpha + b2 * (1 - alpha))
    return rgb_to_hex(r, g, b)

def _make_gradient(w, h, c1, c2, alpha=255, alpha2=None, radius=0):
    if not HAS_PIL:
        return None
    if alpha2 is None:
        alpha2 = alpha
    r1, g1, b1 = hex_to_rgb(c1)
    r2, g2, b2 = hex_to_rgb(c2)
    img = Image.new("RGBA", (w, h))
    for y in range(h):
        t = y / max(h-1, 1)
        r = int(r1 + (r2 - r1) * t)
        g = int(g1 + (g2 - g1) * t)
        b = int(b1 + (b2 - b1) * t)
        a = int(alpha + (alpha2 - alpha) * t)
        for x in range(w):
            img.putpixel((x, y), (r, g, b, a))
    if radius > 0 and w > 1 and h > 1:
        from PIL import ImageDraw
        mask = Image.new("L", (w, h), 0)
        draw = ImageDraw.Draw(mask)
        draw.rounded_rectangle((1, 1, w-1, h-1), radius=radius, fill=255)
        img.putalpha(mask)
    return ImageTk.PhotoImage(img)

def _make_gloss_overlay(w, h, gloss_height=0.5):
    if not HAS_PIL:
        return None
    gh = max(1, int(h * gloss_height))
    img = Image.new("RGBA", (w, gh))
    for y in range(gh):
        t = y / max(gh-1, 1)
        alpha = int(180 * (1 - t * t))
        for x in range(w):
            img.putpixel((x, y), (255, 255, 255, alpha))
    return ImageTk.PhotoImage(img)

def _make_shadow(w, h, blur=3):
    if not HAS_PIL:
        return None
    img = Image.new("RGBA", (w + blur*2, h + blur*2))
    for y in range(h):
        for x in range(w):
            px, py = x+blur, y+blur
            for dy in range(-blur, blur+1):
                for dx in range(-blur, blur+1):
                    d = max(1, dx*dx + dy*dy)
                    a = int(80 / d)
                    nx, ny = px+dx, py+dy
                    if 0 <= nx < img.width and 0 <= ny < img.height:
                        ca = img.getpixel((nx, ny))[3]
                        img.putpixel((nx, ny), (80, 80, 80, min(255, ca + a)))
    return ImageTk.PhotoImage(img)

def get_asset_path(rel):
    base = sys._MEIPASS if getattr(sys, 'frozen', False) else os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base, rel)

def project_root():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(os.path.dirname(os.path.dirname(sys.executable)))
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def scripts_dir():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(os.path.dirname(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))

def _draw_rounded_rect(cv, x1, y1, x2, y2, r, **kw):
    pts = []
    steps = max(8, int(r * 0.5))
    for angle in range(0, 360, max(1, 360 // steps)):
        a = math.radians(angle)
        sx = math.cos(a)
        sy = math.sin(a)
        if angle < 90:
            cx, cy = x2 - r, y1 + r
        elif angle < 180:
            cx, cy = x1 + r, y1 + r
        elif angle < 270:
            cx, cy = x1 + r, y2 - r
        else:
            cx, cy = x2 - r, y2 - r
        pts.append((cx + sx * r, cy + sy * r))
    return cv.create_polygon(pts, smooth=True, **kw)


class _WidgetRegistry:
    def __init__(self):
        self._map = {}
    def reg(self, name, widget):
        self._map[name] = widget
    def get(self, name):
        return self._map.get(name)


class _GlossyButton(tk.Canvas):
    def __init__(self, parent, text, command, width=120, height=40, primary=True):
        super().__init__(parent, width=width, height=height,
                        highlightthickness=0, bd=0, bg=C_WHITE)
        self._cmd = command
        self._primary = primary
        self._btn_text = text
        self._btn_w = width
        self._btn_h = height
        self._grad_img = None
        self._gloss_img = None
        self._shadow_img = None
        self._hovered = False
        self._draw()
        self.bind("<Button-1>", self._on_click)
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)
        self.configure(cursor="hand2")

    def _draw(self):
        self.delete("all")
        r = 300
        top_c = C_BTN_OK_TOP if self._primary else C_BTN_CANCEL_TOP
        bot_c = C_BTN_OK_BOT if self._primary else C_BTN_CANCEL_BOT
        if self._hovered:
            top_c = rgb_to_hex(*[min(255, c+25) for c in hex_to_rgb(top_c)])
            bot_c = rgb_to_hex(*[min(255, c+25) for c in hex_to_rgb(bot_c)])

        grad = _make_gradient(self._btn_w, self._btn_h, top_c, bot_c)
        if grad:
            self._grad_img = grad
            self.create_image(0, 0, image=self._grad_img, anchor="nw")
        else:
            _draw_rounded_rect(self, 0, 0, self._btn_w, self._btn_h, r,
                              fill=top_c, outline="")

        gloss = _make_gloss_overlay(self._btn_w, self._btn_h)
        if gloss:
            self._gloss_img = gloss
            self.create_image(0, 0, image=self._gloss_img, anchor="nw")

        xc, yc = self._btn_w // 2, self._btn_h // 2
        self.create_text(xc, yc, text=self._btn_text, fill=C_WHITE,
                        font=("Segoe UI", 11, "bold"))

    def _on_click(self, e):
        if self._cmd:
            self._cmd()

    def _on_enter(self, e):
        self._hovered = True
        self._draw()

    def _on_leave(self, e):
        self._hovered = False
        self._draw()

    def invoke(self):
        if self._cmd:
            self._cmd()


class _GlossyProgress(tk.Frame):
    def __init__(self, parent, length=300, height=14, phase_bar=True):
        super().__init__(parent, bg=C_WHITE)
        self._len = length
        self._hgt = height
        self._val = 0
        self._max = 100
        self._phase_bar = phase_bar
        self._track_img = _make_gradient(length, height, "#E2E8F0", "#CBD5E0")
        self._indicator_img = None
        self._gloss_img = None
        self.cnv = tk.Canvas(self, width=length, height=height,
                            highlightthickness=0, bd=0, bg=C_WHITE)
        self.cnv.pack()
        self._redraw()

    def _redraw(self):
        self.cnv.delete("all")
        r = 300

        _draw_rounded_rect(self.cnv, 0, 0, self._len, self._hgt, r,
                          fill="#E2E8F0", outline=C_BORDER)

        if self._val > 0 and self._max > 0:
            fw = max(self._hgt, int(self._len * self._val / self._max))
            if self._phase_bar:
                top_c, bot_c = "#1A3A60", "#2B6CB0"
            else:
                top_c, bot_c = "#0F2440", "#1A5276"
            g = _make_gradient(fw, self._hgt, top_c, bot_c)
            if g:
                self._indicator_img = g
                self.cnv.create_image(0, 0, image=self._indicator_img, anchor="nw")
            else:
                _draw_rounded_rect(self.cnv, 0, 0, fw, self._hgt, r,
                                  fill=top_c, outline="")

            gloss = _make_gloss_overlay(fw, self._hgt)
            if gloss:
                self._gloss_img = gloss
                self.cnv.create_image(0, 0, image=self._gloss_img, anchor="nw")

    def __setitem__(self, key, value):
        if key == "value":
            self._val = value
            self._redraw()
        elif key == "maximum":
            self._max = value
            self._redraw()

    def __getitem__(self, key):
        if key == "value":
            return self._val
        if key == "maximum":
            return self._max
        return None


class AppWindow(tk.Toplevel):
    def __init__(self, title="APPL2 Диалог", win_w=520, win_h=580, resizable=True):
        super().__init__()
        self._widgets = _WidgetRegistry()
        self._win_w = win_w
        self._win_h = win_h
        self.title_text = title
        self._resizable = resizable
        self._maximized = False
        self._prev_geom = None
        self._drag_data = None
        self._resize_data = None
        self._search_state = {"query": "", "results": [], "idx": -1, "tree": None}
        self._match_label = None
        self._edge_mode = EDGE_NONE
        self.configure(bg=C_DARK_BLUE)
        self.overrideredirect(True)
        cx = (self.winfo_screenwidth() - win_w) // 2
        cy = (self.winfo_screenheight() - win_h) // 2
        self.geometry(f"{win_w}x{win_h}+{cx}+{cy}")
        self.attributes("-topmost", True)
        self.attributes("-alpha", 0.98)
        self._build_window()
        self._apply_window_style()
        self._widgets.reg("_window_", self)
        self.bind("<Escape>", lambda e: self.destroy())
        self.protocol("WM_DELETE_WINDOW", self.destroy)

    def _get_edge(self, event):
        if not self._resizable:
            return EDGE_NONE
        w, h = self.winfo_width(), self.winfo_height()
        x, y = event.x, event.y
        on_top = y < EDGE_MARGIN
        on_bottom = y > h - EDGE_MARGIN
        on_left = x < EDGE_MARGIN
        on_right = x > w - EDGE_MARGIN
        if on_top and on_left: return EDGE_TOPLEFT
        if on_top and on_right: return EDGE_TOPRIGHT
        if on_bottom and on_left: return EDGE_BOTTOMLEFT
        if on_bottom and on_right: return EDGE_BOTTOMRIGHT
        if on_top: return EDGE_TOP
        if on_bottom: return EDGE_BOTTOM
        if on_left: return EDGE_LEFT
        if on_right: return EDGE_RIGHT
        return EDGE_NONE

    def _edge_cursor(self, edge):
        return {
            EDGE_TOP: "sb_v_double_arrow", EDGE_BOTTOM: "sb_v_double_arrow",
            EDGE_LEFT: "sb_h_double_arrow", EDGE_RIGHT: "sb_h_double_arrow",
            EDGE_TOPLEFT: "size_nw_se", EDGE_BOTTOMRIGHT: "size_nw_se",
            EDGE_TOPRIGHT: "size_ne_sw", EDGE_BOTTOMLEFT: "size_ne_sw",
        }.get(edge, "")

    def _build_window(self):
        outer = tk.Frame(self, bg="#0D1E32")
        outer.pack(fill="both", expand=True)
        self._outer = outer

        tb = tk.Frame(outer, bg="#0D1E32", height=40)
        tb.pack(fill="x", padx=5, pady=(5, 0))
        tb.pack_propagate(False)
        self._title_bar = tb

        tbg = _make_gradient(self._win_w - 10, 40, "#FFFFFF", "#FFFFFF", alpha=30, alpha2=0)
        if tbg:
            self._tbg_img = tbg
            tbg_cv = tk.Canvas(tb, width=self._win_w - 10, height=40,
                              highlightthickness=0, bd=0, bg="#0D1E32")
            tbg_cv.create_image(0, 0, image=tbg, anchor="nw")
            tbg_cv.place(x=0, y=0, relwidth=1, relheight=1)
            tbg_cv.bind("<ButtonPress-1>", self._title_press)
            tbg_cv.bind("<B1-Motion>", self._title_drag)
        else:
            tb.bind("<ButtonPress-1>", self._title_press)
            tb.bind("<B1-Motion>", self._title_drag)

        shade = tk.Frame(tb, bg="#0D1E32")
        shade.pack(side="left", fill="x", expand=True, padx=(10, 0))
        shade_lbl = tk.Label(shade, text=self.title_text,
                            font=("Segoe UI", 14, "bold"),
                            fg=C_WHITE, bg="#0D1E32", anchor="w")
        shade_lbl.place(x=1, y=1)
        shade_lbl.bind("<ButtonPress-1>", self._title_press)
        shade_lbl.bind("<B1-Motion>", self._title_drag)
        front_lbl = tk.Label(shade, text=self.title_text,
                            font=("Segoe UI", 14, "bold"),
                            fg=C_WHITE, bg="#0D1E32", anchor="w")
        front_lbl.pack(fill="x")
        front_lbl.bind("<ButtonPress-1>", self._title_press)
        front_lbl.bind("<B1-Motion>", self._title_drag)
        self._title_front = front_lbl

        bf = tk.Frame(tb, bg="#0D1E32")
        bf.pack(side="right", padx=4)
        for txt, cmd, tip in [("━", self._iconify, "Свернуть"),
                              ("☐", self._toggle_max, "Развернуть"),
                              ("✕", self.destroy, "Закрыть")]:
            self._add_title_btn(bf, txt, cmd, C_WHITE, tip)

        cb = tk.Frame(outer, bg=C_DARK_BLUE)
        cb.pack(fill="both", expand=True, padx=5, pady=(0, 5))
        self._content_border = cb

        self.content = tk.Frame(cb, bg=C_WHITE,
                                highlightbackground=C_DARK_BLUE, highlightthickness=1)
        self.content.pack(fill="both", expand=True, padx=3, pady=3)

        self.bind("<Motion>", self._on_motion)
        self.bind("<ButtonPress-1>", self._on_press)
        self.bind("<B1-Motion>", self._on_drag)
        self.bind("<ButtonRelease-1>", self._on_release)
        self.bind("<Double-Button-1>", self._on_double)

        self.bind("<Configure>", self._on_configure)

    def _on_motion(self, event):
        edge = self._get_edge(event)
        if edge != EDGE_NONE:
            self.configure(cursor=self._edge_cursor(edge))
        else:
            self.configure(cursor="")
        self._edge_mode = edge

    def _on_press(self, event):
        self._drag_data = None
        edge = self._get_edge(event)
        if edge != EDGE_NONE:
            self._resize_data = {"x": event.x_root, "y": event.y_root,
                                "w": self.winfo_width(), "h": self.winfo_height(),
                                "edge": edge,
                                "left": self.winfo_x(), "top": self.winfo_y()}

    def _title_press(self, event):
        self._drag_data = {"x": event.x_root - self.winfo_x(),
                           "y": event.y_root - self.winfo_y()}

    def _title_drag(self, event):
        if self._drag_data:
            y = event.y_root - self.winfo_y()
            if y < 50:
                self.geometry(f"+{event.x_root - self._drag_data['x']}+{event.y_root - self._drag_data['y']}")

    def _on_drag(self, event):
        if self._resize_data:
            rd = self._resize_data
            dx = event.x_root - rd["x"]
            dy = event.y_root - rd["y"]
            new_w, new_h = rd["w"], rd["h"]
            new_x, new_y = rd["left"], rd["top"]
            edge = rd["edge"]
            if edge & EDGE_RIGHT:
                new_w = max(320, rd["w"] + dx)
            if edge & EDGE_LEFT:
                new_w = max(320, rd["w"] - dx)
                new_x = rd["left"] + dx
            if edge & EDGE_BOTTOM:
                new_h = max(300, rd["h"] + dy)
            if edge & EDGE_TOP:
                new_h = max(300, rd["h"] - dy)
                new_y = rd["top"] + dy
            self.geometry(f"{new_w}x{new_h}+{new_x}+{new_y}")
        elif self._drag_data:
            self.geometry(f"+{event.x_root - self._drag_data['x']}+{event.y_root - self._drag_data['y']}")

    def _on_release(self, event):
        self._resize_data = None
        self._drag_data = None

    def _on_double(self, event):
        if self._get_edge(event) == EDGE_NONE:
            self._toggle_max()

    def _on_configure(self, event):
        if self._resize_data:
            return
        if self.winfo_width() > 0 and self.winfo_height() > 0:
            w = self.winfo_width()
            h = self.winfo_height()
            if w != self._win_w or h != self._win_h:
                self._win_w = w
                self._win_h = h
                self.after(50, self._rebuild_region)

    def _add_title_btn(self, parent, text, cmd, color, tooltip=""):
        btn = tk.Label(parent, text=text, font=("Segoe UI", 14, "bold"),
                       fg=color, bg=C_TITLE_BG, width=3, cursor="hand2")
        btn.pack(side="left", padx=0)
        btn.bind("<Button-1>", lambda e: cmd())
        btn.bind("<Enter>", lambda e: btn.configure(bg="#2A5080"))
        btn.bind("<Leave>", lambda e: btn.configure(bg=C_TITLE_BG))
        if tooltip:
            self._add_tooltip(btn, tooltip)
        return btn

    def _add_tooltip(self, widget, text):
        tip = None
        def show(e):
            nonlocal tip
            if tip:
                return
            tip = tk.Toplevel(self)
            tip.wm_overrideredirect(True)
            tip.wm_geometry(f"+{e.x_root+10}+{e.y_root+10}")
            lbl = tk.Label(tip, text=text, bg="#FFFFDD", fg=C_TEXT,
                          font=("Segoe UI", 9), relief="solid", bd=1, padx=4, pady=2)
            lbl.pack()
        def hide(e):
            nonlocal tip
            if tip:
                tip.destroy()
                tip = None
        widget.bind("<Enter>", show)
        widget.bind("<Leave>", hide)

    def _toggle_max(self):
        if not self._maximized:
            self._prev_geom = self.geometry()
            sw, sh = self.winfo_screenwidth(), self.winfo_screenheight()
            self.geometry(f"{sw}x{sh}+0+0")
            self._maximized = True
        else:
            if self._prev_geom:
                self.geometry(self._prev_geom)
                self._prev_geom = None
            self._maximized = False
        self.update_idletasks()
        self.after(50, self._rebuild_region)

    def _iconify(self):
        self.withdraw()
        self.after(100, lambda: self.deiconify() if self.winfo_exists() else None)

    def _apply_window_style(self):
        if not HAS_WIN32:
            return
        try:
            hwnd = win32gui.GetParent(self.winfo_id())
            style = win32gui.GetWindowLong(hwnd, win32con.GWL_EXSTYLE)
            style |= win32con.WS_EX_APPWINDOW
            win32gui.SetWindowLong(hwnd, win32con.GWL_EXSTYLE, style)
            old = win32gui.GetWindowLong(hwnd, win32con.GWL_STYLE)
            win32gui.SetWindowLong(hwnd, win32con.GWL_STYLE, old | win32con.WS_SIZEBOX)
            rgn = win32gui.CreateRoundRectRgn(0, 0, self._win_w, self._win_h, 22, 22)
            win32gui.SetWindowRgn(hwnd, rgn, True)
            cs_drop = 0x20000
            cls = win32gui.GetClassLong(hwnd, win32con.GCL_STYLE)
            win32gui.SetClassLong(hwnd, win32con.GCL_STYLE, cls | cs_drop)
        except:
            pass

    def _add_title_btn(self, parent, text, cmd, color, tooltip=""):
        btn = tk.Label(parent, text=text, font=("Segoe UI", 14, "bold"),
                       fg=color, bg=C_TITLE_BG, width=3, cursor="hand2")
        btn.pack(side="left", padx=0)
        btn.bind("<Button-1>", lambda e: cmd())
        btn.bind("<Enter>", lambda e: btn.configure(bg="#2A5080"))
        btn.bind("<Leave>", lambda e: btn.configure(bg=C_TITLE_BG))
        if tooltip:
            self._add_tooltip(btn, tooltip)
        return btn

    def _rebuild_region(self):
        if not HAS_WIN32:
            return
        try:
            hwnd = win32gui.GetParent(self.winfo_id())
            w = self.winfo_width()
            h = self.winfo_height()
            if w > 0 and h > 0:
                rgn = win32gui.CreateRoundRectRgn(0, 0, w, h, 22, 22)
                win32gui.SetWindowRgn(hwnd, rgn, True)
        except:
            pass

    def info_box(self, text):
        f = tk.Frame(self.content, bg=C_LIGHT_BG,
                     highlightbackground=C_BORDER, highlightthickness=1)
        lbl = tk.Label(f, text=text, wraplength=460, justify="left",
                       font=("Segoe UI", 10), fg=C_TEXT, bg=C_LIGHT_BG, padx=10, pady=8)
        lbl.pack(fill="both", expand=True)
        return f

    def field_group(self):
        return tk.Frame(self.content, bg=C_WHITE)

    def field_text(self, parent, label="", name=None):
        f = tk.Frame(parent, bg=C_WHITE)
        lbl = tk.Label(f, text=label, font=("Segoe UI", 10, "bold"),
                       fg=C_TEXT, bg=C_WHITE, anchor="w")
        lbl.pack(fill="x", pady=(0, 2))
        ef = tk.Frame(f, bg=C_WHITE, highlightbackground=C_BORDER, highlightthickness=1)
        var = tk.StringVar()
        entry = tk.Entry(ef, textvariable=var, font=("Segoe UI", 10),
                        relief="flat", bd=2, highlightthickness=0)
        entry.pack(fill="x", ipady=5, padx=4)
        ef.pack(fill="x")
        if name:
            self._widgets.reg(name, entry)
            self._widgets.reg(name + ".var", var)
        return f

    def field_password(self, parent, label="", name=None):
        f = tk.Frame(parent, bg=C_WHITE)
        lbl = tk.Label(f, text=label, font=("Segoe UI", 10, "bold"),
                       fg=C_TEXT, bg=C_WHITE, anchor="w")
        lbl.pack(fill="x", pady=(0, 2))
        ef = tk.Frame(f, bg=C_WHITE, highlightbackground=C_BORDER, highlightthickness=1)
        var = tk.StringVar()
        entry = tk.Entry(ef, textvariable=var, show="*", font=("Segoe UI", 10),
                        relief="flat", bd=2, highlightthickness=0)
        entry.pack(fill="x", ipady=5, padx=4)
        ef.pack(fill="x")
        if name:
            self._widgets.reg(name, entry)
            self._widgets.reg(name + ".var", var)
        return f

    def field_combo(self, parent, label="", items=None, name=None):
        if items is None:
            items = []
        f = tk.Frame(parent, bg=C_WHITE)
        lbl = tk.Label(f, text=label, font=("Segoe UI", 10, "bold"),
                       fg=C_TEXT, bg=C_WHITE, anchor="w")
        lbl.pack(fill="x", pady=(0, 2))
        var = tk.StringVar()
        combo = ttk.Combobox(f, textvariable=var, values=items,
                            font=("Segoe UI", 10), state="readonly")
        if items:
            combo.current(0)
        combo.pack(fill="x", ipady=5, padx=1)
        if name:
            self._widgets.reg(name, combo)
            self._widgets.reg(name + ".var", var)
        return f

    def search_panel(self, parent, treeview=None, name=None):
        sp = tk.Frame(parent, bg=C_WHITE)
        self._match_label = tk.Label(sp, text="0 - 0", font=("Segoe UI", 10),
                                     fg=C_TEXT, bg=C_WHITE)
        self._match_label.pack(side="left")
        sb_var = tk.StringVar()
        sb = tk.Entry(sp, textvariable=sb_var, font=("Segoe UI", 10),
                     relief="solid", bd=1,
                     highlightbackground=C_BORDER, highlightthickness=1)
        sb.pack(side="left", fill="x", expand=True, padx=(6, 4), ipady=2)
        def on_down():
            self._search_tree(sb_var.get(), treeview, 1)
        def on_up():
            self._search_tree(sb_var.get(), treeview, -1)
        btn_down = tk.Button(sp, text="▼", command=on_down,
                            font=("Segoe UI", 9, "bold"), bg=C_LIGHT_BG,
                            relief="solid", bd=1, padx=4, cursor="hand2")
        btn_down.pack(side="left", padx=(0, 2))
        btn_up = tk.Button(sp, text="▲", command=on_up,
                          font=("Segoe UI", 9, "bold"), bg=C_LIGHT_BG,
                          relief="solid", bd=1, padx=4, cursor="hand2")
        btn_up.pack(side="left")
        sb.bind("<Return>", lambda e: on_down())
        self._search_state = {"query": "", "results": [], "idx": -1, "tree": treeview}
        if name:
            self._widgets.reg(name + ".search", sb)
            self._widgets.reg(name + ".down", btn_down)
            self._widgets.reg(name + ".up", btn_up)
        return sp

    def _search_tree(self, query, tree, direction=1):
        if not tree or not query:
            return
        st = self._search_state
        if st["query"] != query:
            st["query"] = query
            st["results"] = []
            st["idx"] = -1
        if not st["results"]:
            items = tree.get_children("")
            ql = query.lower()
            for item in items:
                vals = tree.item(item, "values")
                if any(ql in str(v).lower() for v in vals):
                    st["results"].append(item)
            st["idx"] = -1 if direction == 1 else len(st["results"])
        if not st["results"]:
            self._match_label.configure(text="0 - 0")
            return
        st["idx"] = (st["idx"] + direction) % len(st["results"])
        item = st["results"][st["idx"]]
        tree.selection_set(item)
        tree.focus(item)
        tree.see(item)
        self._match_label.configure(text=f"{st['idx']+1} - {len(st['results'])}")

    def data_grid(self, parent, columns, data, name=None):
        f = tk.Frame(parent, bg=C_WHITE)
        tree = ttk.Treeview(f, columns=list(range(len(columns))), show="headings",
                            selectmode="browse")
        for i, col in enumerate(columns):
            tree.heading(i, text=col, command=lambda c=i: self._sort_tree(tree, c, False))
            tree.column(i, width=120, minwidth=60)
        tree.tag_configure("alt", background=C_LIGHT_BG)
        for idx, row in enumerate(data):
            tag = "alt" if idx % 2 else ""
            tree.insert("", "end", values=row, tags=(tag,) if tag else ())
        tree.pack(fill="both", expand=True)
        if name:
            self._widgets.reg(name, tree)
        return f

    def _sort_tree(self, tree, col, reverse):
        items = [(tree.set(item, col), item) for item in tree.get_children("")]
        items.sort(key=lambda x: x[0].lower(), reverse=reverse)
        for idx, (_, item) in enumerate(items):
            tree.move(item, "", idx)
            tag = "alt" if idx % 2 else ""
            tree.item(item, tags=(tag,) if tag else ())
        tree.heading(col, command=lambda: self._sort_tree(tree, col, not reverse))

    def progress_pair(self, parent=None, phase_text="Фаза: загрузка данных",
                      step_text="Шаг: (3 - 10)", name=None):
        if parent is None:
            parent = self.content
        f = tk.Frame(parent, bg=C_WHITE)
        pf = tk.Frame(f, bg=C_WHITE)
        pf.pack(fill="x", pady=(0, 4))
        pl = tk.Label(pf, text=phase_text, font=("Segoe UI", 9), fg=C_TEXT,
                     bg=C_WHITE, width=22, anchor="w")
        pl.pack(side="left")
        pb1 = _GlossyProgress(pf, length=280, phase_bar=True) if HAS_PIL else ttk.Progressbar(pf, length=280, mode="determinate")
        pb1.pack(side="left", fill="x", expand=True)
        sf = tk.Frame(f, bg=C_WHITE)
        sf.pack(fill="x")
        sl = tk.Label(sf, text=step_text, font=("Segoe UI", 9), fg=C_TEXT,
                     bg=C_WHITE, width=22, anchor="w")
        sl.pack(side="left")
        pb2 = _GlossyProgress(sf, length=280, phase_bar=False) if HAS_PIL else ttk.Progressbar(sf, length=280, mode="determinate")
        pb2.pack(side="left", fill="x", expand=True)
        if name:
            self._widgets.reg(name + ".phase_bar", pb1)
            self._widgets.reg(name + ".step_bar", pb2)
            self._widgets.reg(name + ".phase_label", pl)
            self._widgets.reg(name + ".step_label", sl)
        return f, pb1, pb2, pl, sl

    def button_row(self, parent=None):
        if parent is None:
            parent = self.content
        return tk.Frame(parent, bg=C_WHITE)

    def button(self, parent, text, command, primary=True, name=None):
        if HAS_PIL:
            btn = _GlossyButton(parent, text, command, width=120, height=40, primary=primary)
            btn.pack(side="left", padx=6)
        else:
            fg = C_WHITE if primary else C_TEXT
            bg = C_DARK_BLUE if primary else "#D0D8E0"
            btn = tk.Button(parent, text=text, command=command,
                          font=("Segoe UI", 10, "bold"),
                          fg=fg, bg=bg, relief="flat", padx=20, pady=6,
                          cursor="hand2", activebackground=bg)
            btn.pack(side="left", padx=6)
        if name:
            self._widgets.reg(name, btn)
        return btn

    def test_click(self, name):
        w = self._widgets.get(name)
        if w and hasattr(w, "invoke"):
            w.invoke()
        elif w:
            w.event_generate("<Button-1>")

    def test_set(self, name, value):
        var = self._widgets.get(name + ".var")
        if var:
            var.set(value)
            return
        w = self._widgets.get(name)
        if w and isinstance(w, tk.Entry):
            w.delete(0, "end")
            w.insert(0, value)

    def test_get(self, name):
        var = self._widgets.get(name + ".var")
        if var:
            return var.get()
        w = self._widgets.get(name)
        if w and hasattr(w, "get"):
            return w.get()
        return None

    def test_select_combo(self, name, value):
        w = self._widgets.get(name)
        if w and hasattr(w, "set"):
            w.set(value)

    def test_find_window(self):
        try:
            return self.winfo_exists()
        except:
            return False

    def test_close(self):
        self.destroy()
