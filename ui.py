"""桌面界面（tkinter，三个标签页：课表 / 成绩 / 空闲教室）。"""

import threading
import time
import datetime
import calendar
import re
import tkinter as tk
import tkinter.font as tkfont
from tkinter import messagebox, ttk

from client import JwcClient
from storage import Storage

CAMPUSES = [("一校区", "1"), ("二校区", "2")]
WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
SECTIONS = [f"第{i}节" for i in range(1, 11)]
WEEKS = [f"第{i}周" for i in range(1, 31)]


def _collect_lists(obj):
    """递归收集所有可能是“行数据”的列表，兼容各种嵌套结构。"""
    if isinstance(obj, list):
        yield obj
    elif isinstance(obj, dict):
        for value in obj.values():
            yield from _collect_lists(value)


def _to_building(item):
    """把单个教学楼条目转成 (id, 名称)；认不出来返回 None。"""
    if isinstance(item, dict):
        lower = {str(k).lower(): v for k, v in item.items()}
        id_candidates = [
            k for k in lower
            if k in ("jxlid", "jxl_id", "id", "dm", "value", "bh", "code", "编号")
            or k.endswith(("id", "_id", "bh", "dm", "code"))
        ]
        name_candidates = [
            k for k in lower
            if k in ("jxlmc", "jxl_name", "jxlname", "mc", "name", "text", "label", "jxl", "名称", "教学楼名称")
            or k.endswith(("mc", "name", "text", "label"))
        ]

        def sort_key(k):
            # 优先认“楼/教/js/jxl”开头的键，避免把 xqid 之类的键当成楼号
            return (0 if any(s in k for s in ("jxl", "js", "楼", "教")) else 1, k)

        id_candidates.sort(key=sort_key)
        name_candidates.sort(key=sort_key)
        id_key = id_candidates[0] if id_candidates else None
        name_key = name_candidates[0] if name_candidates else None
        if id_key is None and name_key is None:
            return None
        if id_key is None:
            return (str(lower[name_key]), str(lower[name_key]))
        name = str(lower[name_key]) if name_key else str(lower[id_key])
        return (str(lower[id_key]), name)
    if isinstance(item, (list, tuple)) and len(item) >= 2:
        return (str(item[0]), str(item[1]))
    if isinstance(item, str):
        return (item, item)
    return None


def normalize_buildings(result):
    """把各种可能的教学楼返回格式统一成 [(id, 名称), ...]。"""
    buildings = []
    for items in _collect_lists(result):
        for item in items:
            building = _to_building(item)
            if building:
                buildings.append(building)
        if buildings:
            break
    if not buildings and isinstance(result, dict):
        # 形如 {"1": "主楼", "2": "二教"} 的 楼号->楼名 映射
        keys = [str(k) for k in result.keys()]
        if keys and all(k.isdigit() for k in keys) and all(isinstance(v, str) for v in result.values()):
            buildings = [(k, result[k]) for k in result]
    return buildings


class DatePickerDialog(tk.Toplevel):
    """简易月份日历弹窗：点日期后返回该日期。"""

    def __init__(self, parent, initial=None):
        super().__init__(parent)
        self.title("选择日期")
        self.resizable(False, False)
        self.result = None
        today = datetime.date.today()
        self.year = (initial or today).year
        self.month = (initial or today).month
        self._build()
        self._render()
        self.transient(parent)
        self.grab_set()
        self._center(parent)

    def _build(self):
        header = ttk.Frame(self)
        header.pack(padx=10, pady=(10, 4))
        ttk.Button(header, text="◀ 上月", width=8, command=self._prev_month).pack(side="left")
        self.title_lbl = ttk.Label(header, width=16, anchor="center", font=("Microsoft YaHei", 10, "bold"))
        self.title_lbl.pack(side="left", padx=8)
        ttk.Button(header, text="下月 ▶", width=8, command=self._next_month).pack(side="left")
        self.grid = ttk.Frame(self)
        self.grid.pack(padx=10, pady=(0, 10))
        for col, name in enumerate(["一", "二", "三", "四", "五", "六", "日"]):
            ttk.Label(self.grid, text=name, width=4, anchor="center").grid(row=0, column=col, padx=1, pady=2)
        bottom = ttk.Frame(self)
        bottom.pack(padx=10, pady=(0, 10))
        ttk.Button(bottom, text="今天", command=self._go_today).pack()

    def _render(self):
        self.title_lbl.config(text=f"{self.year} 年 {self.month} 月")
        for child in self.grid.winfo_children():
            if child.grid_info().get("row", 0) > 0:
                child.destroy()
        start_col = datetime.date(self.year, self.month, 1).weekday()  # 周一为 0
        days = calendar.monthrange(self.year, self.month)[1]
        for day in range(1, days + 1):
            index = start_col + day - 1
            row, col = divmod(index, 7)
            ttk.Button(
                self.grid, text=str(day), width=4,
                command=lambda d=day: self._pick(d),
            ).grid(row=row + 1, column=col, padx=1, pady=1)

    def _prev_month(self):
        self.year, self.month = (self.year - 1, 12) if self.month == 1 else (self.year, self.month - 1)
        self._render()

    def _next_month(self):
        self.year, self.month = (self.year + 1, 1) if self.month == 12 else (self.year, self.month + 1)
        self._render()

    def _go_today(self):
        today = datetime.date.today()
        self.year, self.month = today.year, today.month
        self._pick(today.day)

    def _pick(self, day):
        self.result = datetime.date(self.year, self.month, day)
        self.destroy()

    def _center(self, parent):
        self.update_idletasks()
        x = parent.winfo_rootx() + (parent.winfo_width() - self.winfo_width()) // 2
        y = parent.winfo_rooty() + (parent.winfo_height() - self.winfo_height()) // 2
        self.geometry(f"+{max(x, 0)}+{max(y, 0)}")


class TimetableView(tk.Canvas):
    """用 Canvas 画课表：每门课三行（课程名 / 地点 / 属性+学分），
    行高按内容自动伸缩，避免长文本重叠。"""

    HEADER_H = 36
    MIN_ROW_H = 76
    FIRST_W = 56
    PAD_X = 8
    PAD_Y = 10
    LINE_H = 20

    def __init__(self, parent):
        super().__init__(parent, bg="white", highlightthickness=0)
        self._rows = []
        self._fonts = {
            "header": tkfont.Font(family="Microsoft YaHei", size=10, weight="bold"),
            "label": tkfont.Font(family="Microsoft YaHei", size=10),
            "name": tkfont.Font(family="Microsoft YaHei", size=10, weight="bold"),
            "info": tkfont.Font(family="Microsoft YaHei", size=9),
        }
        self.bind("<Configure>", lambda e: self._draw())

    def set_data(self, rows):
        self._rows = rows or []
        self._draw()

    def _draw(self):
        self.delete("all")
        rows = self._rows
        if not rows:
            return
        w = max(self.winfo_width(), 320)
        headers = rows[0]
        data_rows = rows[1:]
        n_cols = max(len(headers), 2)
        col_w = (w - self.FIRST_W) / (n_cols - 1) if n_cols > 1 else w - self.FIRST_W

        # 先按内容算每行高度：取该行所有课程卡片里最高的那个
        row_heights = []
        for row in data_rows:
            h = self.MIN_ROW_H
            for c in range(1, n_cols):
                value = row[c] if c < len(row) else ""
                if isinstance(value, dict):
                    avail = max(col_w - self.PAD_X * 2, 20)
                    need = self.PAD_Y * 2
                    for text, font, _ in self._card_lines(value):
                        need += self._wrap_count(text, font, avail) * self.LINE_H
                    h = max(h, need)
            row_heights.append(h)

        total_h = self.HEADER_H + sum(row_heights)
        self.configure(scrollregion=(0, 0, w, total_h))

        # 表头
        for c in range(n_cols):
            x0 = 0 if c == 0 else self.FIRST_W + (c - 1) * col_w
            cw = self.FIRST_W if c == 0 else col_w
            self.create_rectangle(x0, 0, x0 + cw, self.HEADER_H, fill="#EAF0F7", outline="#C9D4E0")
            title = headers[c] if c < len(headers) else ""
            self.create_text(
                x0 + cw / 2, self.HEADER_H / 2,
                text=str(title), font=self._fonts["header"], fill="#33475B",
            )

        # 数据行
        y = self.HEADER_H
        for r, row in enumerate(data_rows):
            row_h = row_heights[r]
            for c in range(n_cols):
                x0 = 0 if c == 0 else self.FIRST_W + (c - 1) * col_w
                cw = self.FIRST_W if c == 0 else col_w
                value = row[c] if c < len(row) else ""
                if c == 0:
                    self.create_rectangle(x0, y, x0 + cw, y + row_h, fill="#F4F7FA", outline="#D5DEE8")
                    self.create_text(
                        x0 + cw / 2, y + row_h / 2,
                        text=str(value), font=self._fonts["label"], fill="#555555",
                    )
                elif isinstance(value, dict):
                    self._draw_course_card(x0, y, cw, row_h, value)
                else:
                    self.create_rectangle(x0, y, x0 + cw, y + row_h, fill="white", outline="#D5DEE8")
            y += row_h

    def _draw_course_card(self, x, y, w, h, value):
        self.create_rectangle(x, y, x + w, y + h, fill="#E7F1FC", outline="#B8CCE4")
        avail = max(w - self.PAD_X * 2, 20)
        text_y = y + self.PAD_Y
        for text, font, color in self._card_lines(value):
            if not text:
                continue
            block_h = self._wrap_count(text, font, avail) * self.LINE_H
            self.create_text(
                x + w / 2, text_y + block_h / 2,
                text=text, font=font, fill=color, width=int(avail), justify="center",
            )
            text_y += block_h

    def _card_lines(self, value):
        return [
            (value.get("name") or "", self._fonts["name"], "#1F3A5F"),
            (value.get("location") or "", self._fonts["info"], "#556677"),
            (self._attr_credits(value), self._fonts["info"], "#2E7D32"),
        ]

    def _wrap_count(self, text, font, avail_w):
        """按字符宽度估算实际占几行（中文按字换行，估算足够准确）。"""
        if not text:
            return 0
        lines = 1
        width = 0
        for ch in text:
            ch_w = font.measure(ch)
            if width + ch_w > avail_w:
                lines += 1
                width = ch_w
            else:
                width += ch_w
        return lines

    @staticmethod
    def _attr_credits(value):
        parts = []
        attr = value.get("attr") or ""
        credits = value.get("credits") or ""
        if attr:
            parts.append(attr)
        if credits:
            parts.append(f"{credits}学分")
        return " ".join(parts)


class NameGridView(ttk.Frame):
    """教室名称卡片网格：每行 3 个，可滚动。"""

    def __init__(self, parent):
        super().__init__(parent)
        self.canvas = tk.Canvas(self, bg="white", highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        self.scrollbar.pack(side="right", fill="y")
        self.canvas.pack(side="left", fill="both", expand=True)
        self.inner = ttk.Frame(self.canvas)
        self._window = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(self._window, width=e.width))
        self.canvas.bind("<MouseWheel>", self._on_wheel)
        self.inner.bind("<MouseWheel>", self._on_wheel)

    def set_names(self, names):
        for child in self.inner.winfo_children():
            child.destroy()
        for idx, name in enumerate(names or []):
            row, col = divmod(idx, 3)
            label = tk.Label(
                self.inner, text=name, width=14, height=2, bg="#E7F1FC",
                relief="solid", bd=1, font=("Microsoft YaHei", 10),
            )
            label.bind("<MouseWheel>", self._on_wheel)
            label.grid(row=row, column=col, padx=6, pady=6, sticky="nsew")
        for c in range(3):
            self.inner.columnconfigure(c, weight=1)

    def _on_wheel(self, event):
        delta = getattr(event, "delta", 0)
        if delta:
            step = max(1, abs(delta) // 120)
            self.canvas.yview_scroll(-step if delta > 0 else step, "units")


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("NCEPU 教务助手")
        self.geometry("980x660")
        self.configure(bg="#F2F5F9")
        self._apply_style()
        self.client = JwcClient()
        self.storage = Storage()
        self._buildings = []
        self._grades_raw = []
        self._query_after_buildings = False
        self._classroom_query_job = None
        self._build_login_view()
        self._build_main_view()
        self.login_frame.pack(fill="both", expand=True)
        self.after(100, self.startup)

    def _apply_style(self):
        """扁平化主题与统一配色。"""
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        bg = "#F2F5F9"
        fg = "#2B3A4A"
        accent = "#2F7FD0"
        style.configure(".", background=bg, foreground=fg, font=("Microsoft YaHei", 10))
        style.configure("TFrame", background=bg)
        style.configure("TLabel", background=bg, foreground=fg)
        style.configure("TButton", background="#FFFFFF", foreground=fg,
                        bordercolor="#C9D4E0", padding=(14, 7), focuscolor=accent)
        style.map("TButton",
                  background=[("active", "#E7F1FC"), ("pressed", "#D6E6F7")],
                  bordercolor=[("active", accent)])
        style.configure("Accent.TButton", background=accent, foreground="#FFFFFF",
                        bordercolor=accent, padding=(18, 8), font=("Microsoft YaHei", 11, "bold"))
        style.map("Accent.TButton",
                  background=[("active", "#2A6FB8"), ("pressed", "#1F5C9C")],
                  bordercolor=[("active", "#2A6FB8")])
        style.configure("TNotebook", background=bg, borderwidth=0)
        style.configure("TNotebook.Tab", background="#E3E9F1", foreground=fg,
                        padding=(18, 8), font=("Microsoft YaHei", 10))
        style.map("TNotebook.Tab",
                  background=[("selected", "#FFFFFF")],
                  foreground=[("selected", accent)])
        style.configure("Treeview", background="#FFFFFF", fieldbackground="#FFFFFF",
                        foreground=fg, rowheight=28, font=("Microsoft YaHei", 9),
                        bordercolor="#D5DEE8")
        style.map("Treeview",
                  background=[("selected", "#B8D4F0")],
                  foreground=[("selected", "#1F3A5F")])
        style.configure("Treeview.Heading", background="#EAF0F7", foreground="#33475B",
                        font=("Microsoft YaHei", 9, "bold"), relief="flat")
        style.map("Treeview.Heading", background=[("active", "#DCE7F3")])
        style.configure("TEntry", fieldbackground="#FFFFFF", bordercolor="#C9D4E0", padding=4)
        style.configure("TCombobox", fieldbackground="#FFFFFF", padding=4)
        style.configure("Card.TFrame", background="#FFFFFF", relief="solid", borderwidth=1, bordercolor="#D5DEE8")
        style.configure("Card.TLabel", background="#FFFFFF", foreground=fg)
        style.configure("Card.TCheckbutton", background="#FFFFFF", foreground=fg)
        style.configure("Title.TLabel", background="#FFFFFF", foreground=accent,
                        font=("Microsoft YaHei", 22, "bold"))
        style.configure("Subtitle.TLabel", background="#FFFFFF", foreground="#8A97A5",
                        font=("Microsoft YaHei", 10))
        style.configure("Vertical.TScrollbar", background="#C9D4E0", troughcolor=bg)

    # ---------- 登录界面 ----------
    def _build_login_view(self):
        self.login_frame = ttk.Frame(self, padding=60)
        card = ttk.Frame(self.login_frame, style="Card.TFrame", padding=(56, 44))
        card.pack()
        ttk.Label(card, text="NCEPU 教务助手", style="Title.TLabel").pack(pady=(0, 6))
        ttk.Label(card, text="课表 · 成绩 · 考试安排 · 空闲教室", style="Subtitle.TLabel").pack(pady=(0, 26))
        form = ttk.Frame(card, style="Card.TFrame")
        form.pack()
        ttk.Label(form, text="学号", style="Card.TLabel").grid(row=0, column=0, sticky="e", padx=(0, 10), pady=8)
        self.user_var = tk.StringVar()
        ttk.Entry(form, textvariable=self.user_var, width=26).grid(row=0, column=1, pady=8, ipady=4)
        ttk.Label(form, text="密码", style="Card.TLabel").grid(row=1, column=0, sticky="e", padx=(0, 10), pady=8)
        self.pass_var = tk.StringVar()
        ttk.Entry(form, textvariable=self.pass_var, width=26, show="*").grid(row=1, column=1, pady=8, ipady=4)
        self.remember_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(
            card, text="记住账号密码（明文保存在本地）",
            variable=self.remember_var, style="Card.TCheckbutton",
        ).pack(pady=(16, 0))
        self.login_btn = ttk.Button(card, text="登  录", style="Accent.TButton", command=self.on_login)
        self.login_btn.pack(pady=(24, 8), ipadx=10)
        self.login_status = ttk.Label(card, text="首次使用请连接校园网登录", style="Card.TLabel")
        self.login_status.pack()

    # ---------- 主界面 ----------
    def _build_main_view(self):
        self.main_frame = ttk.Frame(self)
        toolbar = ttk.Frame(self.main_frame)
        toolbar.pack(fill="x", padx=8, pady=(8, 0))
        ttk.Button(toolbar, text="刷新全部", command=self.refresh_all).pack(side="left")
        ttk.Button(toolbar, text="重新登录", command=self.show_login).pack(side="right")

        self.notebook = ttk.Notebook(self.main_frame)
        self.notebook.pack(fill="both", expand=True, padx=8, pady=8)
        self._build_timetable_tab()
        self._build_grades_tab()
        self._build_classroom_tab()
        self._build_exam_tab()
        self.notebook.bind("<<NotebookTabChanged>>", self._on_tab_changed)

        self.status_var = tk.StringVar(value="状态：尚未登录")
        ttk.Label(self.main_frame, textvariable=self.status_var, anchor="w").pack(fill="x", padx=10, pady=(0, 8))

    def _build_timetable_tab(self):
        frame = ttk.Frame(self.notebook)
        bar = ttk.Frame(frame)
        bar.pack(fill="x", padx=6, pady=6)
        self.week_info_var = tk.StringVar(value="")
        ttk.Label(bar, textvariable=self.week_info_var, foreground="#1F6FB2").pack(side="left", padx=(0, 16))
        ttk.Button(bar, text="本周课表", command=self.refresh_timetable).pack(side="left")
        ttk.Label(bar, text="日期：").pack(side="left", padx=(16, 0))
        self.date_var = tk.StringVar(value=datetime.date.today().isoformat())
        ttk.Entry(bar, textvariable=self.date_var, width=11, state="readonly").pack(side="left")
        ttk.Button(bar, text="选择日期", command=self.pick_date).pack(side="left", padx=4)
        self.timetable_note = ttk.Label(bar, text="")
        self.timetable_note.pack(side="left", padx=12)
        self.timetable_view = TimetableView(frame)
        self.timetable_view.pack(fill="both", expand=True, padx=6, pady=(0, 6))
        self.notebook.add(frame, text=" 课表 ")

    def _build_grades_tab(self):
        frame = ttk.Frame(self.notebook)
        bar = ttk.Frame(frame)
        bar.pack(fill="x", padx=6, pady=6)
        ttk.Button(bar, text="刷新成绩", command=self.refresh_grades).pack(side="left")
        ttk.Label(bar, text="开课学期：").pack(side="left", padx=(16, 0))
        self.grade_term_var = tk.StringVar()
        self.grade_term_combo = ttk.Combobox(bar, textvariable=self.grade_term_var, width=13, state="readonly")
        self.grade_term_combo.pack(side="left")
        self.grade_term_combo.bind("<<ComboboxSelected>>", lambda e: self.apply_grades_filter())
        ttk.Label(bar, text="课程名称：").pack(side="left", padx=(12, 0))
        self.grade_name_var = tk.StringVar()
        ttk.Entry(bar, textvariable=self.grade_name_var, width=16).pack(side="left")
        self.grade_name_var.trace_add("write", lambda *a: self.apply_grades_filter())
        ttk.Button(bar, text="重置", command=self.reset_grades_filter).pack(side="left", padx=8)
        self.grades_note = ttk.Label(bar, text="")
        self.grades_note.pack(side="left", padx=12)
        info_bar = ttk.Frame(frame)
        info_bar.pack(fill="x", padx=6, pady=(0, 4))
        self.gpa_var = tk.StringVar(value="")
        ttk.Label(
            info_bar, textvariable=self.gpa_var, foreground="#1F6FB2",
            font=("Microsoft YaHei", 10, "bold"),
        ).pack(side="left")
        self.grades_tree = ttk.Treeview(frame, show="headings")
        self.grades_tree.pack(fill="both", expand=True, padx=6, pady=(0, 6))
        self.notebook.add(frame, text=" 课程成绩 ")

    def _build_classroom_tab(self):
        frame = ttk.Frame(self.notebook)
        bar = ttk.Frame(frame)
        bar.pack(fill="x", padx=6, pady=6)

        ttk.Label(bar, text="校区：").pack(side="left")
        self.campus_var = tk.StringVar(value="二校区")
        self.campus_combo = ttk.Combobox(
            bar, textvariable=self.campus_var,
            values=[c for c, _ in CAMPUSES], width=8, state="readonly",
        )
        self.campus_combo.pack(side="left")
        self.campus_combo.bind("<<ComboboxSelected>>", self._on_campus_changed)

        ttk.Label(bar, text="教学楼：").pack(side="left", padx=(12, 0))
        self.building_var = tk.StringVar()
        self.building_combo = ttk.Combobox(
            bar, textvariable=self.building_var, width=18, state="readonly",
        )
        self.building_combo.pack(side="left")
        self.building_combo.bind("<<ComboboxSelected>>", lambda e: self._schedule_classroom_query())

        row2 = ttk.Frame(frame)
        row2.pack(fill="x", padx=6, pady=(6, 0))
        ttk.Label(row2, text="星期：").pack(side="left")
        today_name = WEEKDAYS[datetime.date.today().weekday()]
        self.day_from_var = tk.StringVar(value=today_name)
        self.day_to_var = tk.StringVar(value=today_name)
        self.day_from_combo = ttk.Combobox(
            row2, textvariable=self.day_from_var, values=WEEKDAYS, width=5, state="readonly",
        )
        self.day_from_combo.pack(side="left")
        self.day_from_combo.bind("<<ComboboxSelected>>", lambda e: self._schedule_classroom_query())
        ttk.Label(row2, text="至").pack(side="left", padx=2)
        self.day_to_combo = ttk.Combobox(
            row2, textvariable=self.day_to_var, values=WEEKDAYS, width=5, state="readonly",
        )
        self.day_to_combo.pack(side="left")
        self.day_to_combo.bind("<<ComboboxSelected>>", lambda e: self._schedule_classroom_query())

        ttk.Label(row2, text="节次：").pack(side="left", padx=(14, 0))
        self.jc_from_var = tk.StringVar(value="")
        self.jc_to_var = tk.StringVar(value="")
        self.jc_from_combo = ttk.Combobox(
            row2, textvariable=self.jc_from_var, values=[""] + SECTIONS, width=6, state="readonly",
        )
        self.jc_from_combo.pack(side="left")
        self.jc_from_combo.bind("<<ComboboxSelected>>", lambda e: self._schedule_classroom_query())
        ttk.Label(row2, text="至").pack(side="left", padx=2)
        self.jc_to_combo = ttk.Combobox(
            row2, textvariable=self.jc_to_var, values=[""] + SECTIONS, width=6, state="readonly",
        )
        self.jc_to_combo.pack(side="left")
        self.jc_to_combo.bind("<<ComboboxSelected>>", lambda e: self._schedule_classroom_query())

        row3 = ttk.Frame(frame)
        row3.pack(fill="x", padx=6, pady=(6, 0))
        ttk.Label(row3, text="周次：").pack(side="left")
        self.week_from_var = tk.StringVar(value="")
        self.week_to_var = tk.StringVar(value="")
        self.week_from_combo = ttk.Combobox(
            row3, textvariable=self.week_from_var, values=[""] + WEEKS, width=6, state="readonly",
        )
        self.week_from_combo.pack(side="left")
        self.week_from_combo.bind("<<ComboboxSelected>>", lambda e: self._schedule_classroom_query())
        ttk.Label(row3, text="至").pack(side="left", padx=2)
        self.week_to_combo = ttk.Combobox(
            row3, textvariable=self.week_to_var, values=[""] + WEEKS, width=6, state="readonly",
        )
        self.week_to_combo.pack(side="left")
        self.week_to_combo.bind("<<ComboboxSelected>>", lambda e: self._schedule_classroom_query())
        ttk.Button(row3, text="查询空闲教室", command=self.query_classrooms).pack(side="left", padx=14)
        self.classroom_note = ttk.Label(row3, text="")
        self.classroom_note.pack(side="left")

        self.classroom_grid = NameGridView(frame)
        self.classroom_grid.pack(fill="both", expand=True, padx=6, pady=6)
        self.classroom_debug = tk.Text(frame, height=5)
        self.classroom_debug.pack(fill="x", padx=6, pady=(0, 6))
        self.notebook.add(frame, text=" 空闲教室 ")

    def _build_exam_tab(self):
        frame = ttk.Frame(self.notebook)
        bar = ttk.Frame(frame)
        bar.pack(fill="x", padx=6, pady=6)
        ttk.Button(bar, text="刷新考试安排", command=self.refresh_exams).pack(side="left")
        ttk.Label(bar, text="灰色 = 已考完", foreground="#9AA3AD").pack(side="right", padx=8)
        self.exam_note = ttk.Label(bar, text="")
        self.exam_note.pack(side="left", padx=12)
        self.exam_tree = ttk.Treeview(frame, show="headings")
        self.exam_tree.pack(fill="both", expand=True, padx=6, pady=(0, 6))
        self.notebook.add(frame, text=" 考试安排 ")

    # ---------- 启动流程 ----------
    def startup(self):
        cookies = self.storage.load_cookies()
        account = self.storage.load_account()
        if account.get("username"):
            self.user_var.set(account["username"])
        if account.get("password"):
            self.pass_var.set(account["password"])
        if cookies:
            self.client.load_cookies({k: v for k, v in cookies.items() if k != "username"})
            if cookies.get("username"):
                self.user_var.set(cookies["username"])
            self.show_cached()
            if self.client.online():
                self.login_status.config(text="已连接校园网，正在验证登录…")
                self._run(self.client.check_login, on_done=self._on_session_check)
            else:
                self.login_status.config(text="未检测到校园网，先显示本地缓存；连上后点登录")
                self.show_main()
        else:
            self.login_status.config(text="首次使用请连接校园网登录")

    def _on_session_check(self, ok):
        if ok:
            self.login_status.config(text="会话有效")
            self.show_main()
            self.refresh_all()
        else:
            self.login_status.config(text="会话已过期，请重新登录")

    # ---------- 登录 ----------
    def on_login(self):
        user = self.user_var.get().strip()
        pwd = self.pass_var.get()
        if not user or not pwd:
            messagebox.showwarning("提示", "请输入学号和密码")
            return
        self.login_btn.config(state="disabled")
        self.login_status.config(text="登录中…")

        def task():
            self.client.login(user, pwd)
            return user

        def done(user):
            self.login_btn.config(state="normal")
            self.login_status.config(text="登录成功")
            cookies = self.client.cookies_dict()
            cookies["username"] = user
            self.storage.save_cookies(cookies)
            if self.remember_var.get():
                self.storage.save_account(user, pwd)
            else:
                self.storage.clear_account()
            self.show_main()
            self.refresh_all()

        def failed(e):
            self.login_btn.config(state="normal")
            self.login_status.config(text=f"登录失败：{e}")

        self._run(task, on_done=done, on_error=failed)

    # ---------- 数据刷新 ----------
    def refresh_all(self):
        self.status_var.set("正在连接教务系统并刷新数据…")
        self.update_week_info()
        self.refresh_timetable()
        self.refresh_grades()
        self.refresh_exams()
        self.load_buildings()

    def update_week_info(self):
        def task():
            return self.client.get_semester_info()

        def done(info):
            current, total = info
            if current:
                text = f"第 {current} 周"
                if total:
                    text += f" / 共 {total} 周"
                self.week_info_var.set(text)
                if not self.week_from_var.get() and not self.week_to_var.get():
                    default_week = f"第{current}周"
                    self.week_from_var.set(default_week)
                    self.week_to_var.set(default_week)
            else:
                self.week_info_var.set("当前周次未知")

        self._run(task, on_done=done)

    def refresh_timetable(self):
        def task():
            rows = self.client.get_timetable()
            self.storage.save("timetable", rows)
            current, total = self.client.get_semester_info()
            return rows, current, total

        def done(result):
            rows, current, total = result
            self.timetable_view.set_data(rows)
            if current:
                text = f"第 {current} 周"
                if total:
                    text += f" / 共 {total} 周"
                self.week_info_var.set(text)
            t = self._fmt_time(self.storage.last_update("timetable"))
            self.timetable_note.config(text=f"更新于 {t}")
            self.status_var.set(f"状态：在线（课表已更新 {t}）")

        def failed(e):
            cached = self.storage.load("timetable", [])
            self.timetable_view.set_data(cached)
            self.timetable_note.config(text=f"刷新失败，显示缓存：{e}")
            self.status_var.set("状态：在线但刷新失败（会话过期或不在校园网）")

        self._run(task, on_done=done, on_error=failed)

    def pick_date(self):
        try:
            initial = datetime.date.fromisoformat(self.date_var.get())
        except ValueError:
            initial = datetime.date.today()
        dialog = DatePickerDialog(self, initial)
        self.wait_window(dialog)
        if dialog.result:
            self.date_var.set(dialog.result.isoformat())
            self.query_by_date()

    def query_by_date(self):
        date_str = self.date_var.get().strip()
        try:
            target = datetime.date.fromisoformat(date_str)
        except ValueError:
            messagebox.showwarning("提示", "日期格式应为 YYYY-MM-DD，例如 2026-09-07")
            return
        self.timetable_note.config(text="正在查询…")

        def task():
            rows = self.client.get_timetable_by_date(date_str)
            self.storage.save("timetable", rows)
            current, total = self.client.get_semester_info()
            week = None
            if current:
                today = datetime.date.today()
                monday = today - datetime.timedelta(days=today.weekday())
                week = current + (target - monday).days // 7
                if week < 1:
                    week = 1
            return rows, week, total

        def done(result):
            rows, week, total = result
            self.timetable_view.set_data(rows)
            if week:
                text = f"第 {week} 周"
                if total:
                    text += f" / 共 {total} 周"
                self.week_info_var.set(text)
            t = self._fmt_time(self.storage.last_update("timetable"))
            self.timetable_note.config(text=f"{date_str} · 更新于 {t}")

        self._run(task, on_done=done)

    def refresh_grades(self):
        def task():
            rows = self.client.get_grades()
            self.storage.save("grades", rows)
            return rows

        def done(rows):
            self.set_grades_data(rows)
            self.status_var.set("状态：在线（成绩已更新）")

        def failed(e):
            cached = self.storage.load("grades", [])
            self.set_grades_data(cached)
            self.grades_note.config(text=f"刷新失败，显示缓存：{e}")
            self.status_var.set("状态：在线但刷新失败（会话过期或不在校园网）")

        self._run(task, on_done=done, on_error=failed)

    # ---------- 考试安排 ----------
    def refresh_exams(self):
        self.exam_note.config(text="正在查询考试安排…")

        def task():
            term = self.client.get_current_term()
            rows = self.client.get_exams(term)
            self.storage.save("exams", rows)
            return rows, term

        def done(result):
            rows, term = result
            self.display_exams(rows)
            t = self._fmt_time(self.storage.last_update("exams"))
            count = len(rows) - 1 if rows else 0
            self.exam_note.config(text=f"{term} · 共 {count} 场 · 更新于 {t}".lstrip("· "))
            self.status_var.set(f"状态：在线（考试安排已更新 {t}）")

        def failed(e):
            cached = self.storage.load("exams", [])
            self.display_exams(cached)
            self.exam_note.config(text=f"刷新失败，显示缓存：{e}")
            self.status_var.set("状态：在线但刷新失败（会话过期或不在校园网）")

        self._run(task, on_done=done, on_error=failed)

    def display_exams(self, rows):
        """只显示：序号 / 考试类型 / 课程名称 / 考试时间 / 考试地点 / 任课老师。"""
        self.exam_tree.delete(*self.exam_tree.get_children())
        if not rows:
            return
        headers = [str(h).strip() for h in rows[0]]

        def find(names):
            return next(
                (i for i, h in enumerate(headers) if any(h == n or h.startswith(n) or n in h for n in names)),
                None,
            )

        type_idx = find(("考试类型", "考试性质"))
        name_idx = find(("课程名称",))
        time_idx = find(("考试时间", "考试日期", "时间"))
        place_idx = find(("考试地点", "地点", "教室"))
        teacher_idx = find(("任课教师", "任课老师", "教师", "老师"))

        display = [["序号", "考试类型", "课程名称", "考试时间", "考试地点", "任课老师"]]
        for i, row in enumerate(rows[1:], 1):
            display.append([
                str(i),
                str(row[type_idx]).strip() if type_idx is not None and type_idx < len(row) else "",
                str(row[name_idx]).strip() if name_idx is not None and name_idx < len(row) else "",
                str(row[time_idx]).strip() if time_idx is not None and time_idx < len(row) else "",
                str(row[place_idx]).strip() if place_idx is not None and place_idx < len(row) else "",
                str(row[teacher_idx]).strip() if teacher_idx is not None and teacher_idx < len(row) else "",
            ])
        self.fill_tree(self.exam_tree, display, widths=[50, 110, 220, 200, 150, 130])
        # 已经考完的考试整行置灰
        self.exam_tree.tag_configure("done", foreground="#9AA3AD")
        for iid, row in zip(self.exam_tree.get_children(), display[1:]):
            if self._exam_finished(row[3]):
                self.exam_tree.item(iid, tags=self.exam_tree.item(iid, "tags") + ("done",))

    @staticmethod
    def _exam_finished(time_text):
        """判断考试是否已结束：解析“2026-01-15 09:00-11:00”这类时间并和当前时间比较。"""
        text = str(time_text or "").strip()
        if not text:
            return False
        m = re.search(r"(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})", text)
        if not m:
            return False
        year, month, day = int(m.group(1)), int(m.group(2)), int(m.group(3))
        m2 = re.search(r"(\d{1,2}):(\d{2})\s*[-~至到]\s*(\d{1,2}):(\d{2})", text)
        if m2:
            end_hour, end_min = int(m2.group(3)), int(m2.group(4))
        else:
            m3 = re.search(r"(\d{1,2}):(\d{2})", text)
            if not m3:
                return False
            end_hour, end_min = int(m3.group(1)), int(m3.group(2))
        try:
            end = datetime.datetime(year, month, day, end_hour, end_min)
        except ValueError:
            return False
        return datetime.datetime.now() > end

    def show_cached(self):
        self.timetable_view.set_data(self.storage.load("timetable", []))
        self.set_grades_data(self.storage.load("grades", []))
        self.display_exams(self.storage.load("exams", []))

    # ---------- 成绩展示与筛选 ----------
    def set_grades_data(self, rows):
        """保存原始成绩数据，刷新学期下拉，并按当前条件重新显示。"""
        self._grades_raw = rows or []
        headers = [str(h).strip() for h in (self._grades_raw[0] if self._grades_raw else [])]
        term_idx = self._find_col(headers, ("学年学期", "开课学期", "学期"))
        terms = []
        if term_idx is not None:
            for row in self._grades_raw[1:]:
                v = str(row[term_idx]).strip() if term_idx < len(row) else ""
                if v and v not in terms:
                    terms.append(v)
        self.grade_term_combo["values"] = ["全部学期"] + terms
        if self.grade_term_var.get() not in ["全部学期"] + terms:
            self.grade_term_var.set("全部学期")
        self.apply_grades_filter()

    def apply_grades_filter(self):
        """按条件过滤后，只显示：序号 / 开课学期 / 课程名称 / 成绩 / 课程属性 / 学分。"""
        self.grades_tree.delete(*self.grades_tree.get_children())
        rows = self._grades_raw
        if not rows:
            return
        headers = [str(h).strip() for h in rows[0]]
        term_idx = self._find_col(headers, ("学年学期", "开课学期", "学期"))
        name_idx = self._find_col(headers, ("课程名称",))
        grade_idx = self._grade_col(headers)
        attr_idx = self._find_col(headers, ("课程性质", "课程属性", "课程类别", "课程类型"))
        credit_idx = self._find_col(headers, ("学分",))

        term_filter = self.grade_term_var.get().strip()
        name_filter = self.grade_name_var.get().strip().lower()

        display = [["序号", "开课学期", "课程名称", "成绩", "课程属性", "学分"]]
        count = 0
        gpa_count = 0
        credit_sum = 0.0
        score_sum = 0.0
        for row in rows[1:]:
            term = str(row[term_idx]).strip() if term_idx is not None and term_idx < len(row) else ""
            name = str(row[name_idx]).strip() if name_idx is not None and name_idx < len(row) else ""
            grade = str(row[grade_idx]).strip() if grade_idx is not None and grade_idx < len(row) else ""
            attr = str(row[attr_idx]).strip() if attr_idx is not None and attr_idx < len(row) else ""
            credit = str(row[credit_idx]).strip() if credit_idx is not None and credit_idx < len(row) else ""
            if term_filter and term_filter != "全部学期" and term != term_filter:
                continue
            if name_filter and name_filter not in name.lower():
                continue
            count += 1
            display.append([str(count), term, name, grade, attr, credit])
            if attr.startswith("必修"):
                score = self._score_value(grade)
                credit_num = self._credit_value(credit)
                if score is not None and credit_num > 0:
                    gpa_count += 1
                    credit_sum += credit_num
                    score_sum += credit_num * score
        self.fill_tree(self.grades_tree, display, widths=[50, 130, 240, 90, 120, 80])
        t = self._fmt_time(self.storage.last_update("grades"))
        self.grades_note.config(text=f"更新于 {t} · 共 {count} 门课程")
        if gpa_count:
            self.gpa_var.set(f"必修 {gpa_count} 门 · 平均学分绩 {score_sum / credit_sum:.6f}")
        else:
            self.gpa_var.set("暂无可用必修成绩（优95 / 良85 / 中75 / 及格65 / 不及格55）")

    def reset_grades_filter(self):
        self.grade_term_var.set("全部学期")
        self.grade_name_var.set("")
        self.apply_grades_filter()

    @staticmethod
    def _find_col(headers, names):
        for i, h in enumerate(headers):
            if any(h == name or h.startswith(name) for name in names):
                return i
        return None

    @staticmethod
    def _grade_col(headers):
        for name in ("总评成绩", "期末成绩", "补考成绩", "重修成绩", "平时成绩"):
            idx = App._find_col(headers, (name,))
            if idx is not None:
                return idx
        for i, h in enumerate(headers):
            if h == "成绩":
                return i
        return None

    @staticmethod
    def _score_value(text):
        """成绩文本转分数：优95 / 良85 / 中75 / 及格65 / 不及格55，数字直接解析。"""
        mapping = {
            "优": 95, "优秀": 95,
            "良": 85, "良好": 85,
            "中": 75, "中等": 75,
            "及格": 65, "合格": 65,
            "不及格": 55, "不合格": 55,
        }
        t = str(text).strip()
        if not t:
            return None
        if t in mapping:
            return mapping[t]
        try:
            return float(t)
        except ValueError:
            return None

    @staticmethod
    def _credit_value(text):
        try:
            return float(str(text).strip())
        except (ValueError, TypeError):
            return 0.0

    # ---------- 空闲教室 ----------
    def load_buildings(self):
        xqid = dict(CAMPUSES).get(self.campus_var.get(), "2")
        self.classroom_note.config(text="加载教学楼…")

        def task():
            return self.client.get_buildings(xqid)

        def done(result):
            self._buildings = normalize_buildings(result)
            self._buildings = self._order_buildings(self._buildings, self.campus_var.get())
            print("DEBUG buildings =", self._buildings)
            self.building_combo["values"] = ["全部"] + [name for _, name in self._buildings]
            default_idx = 1 if self._buildings and self._buildings[0][1] == "教十一楼" else 0
            self.building_combo.current(default_idx)
            self.classroom_note.config(text=f"共 {len(self._buildings)} 栋教学楼（可不选）")
            if not self._buildings:
                self.classroom_debug.delete("1.0", tk.END)
                self.classroom_debug.insert(tk.END, f"原始返回：\n{result}")
            if self._query_after_buildings:
                self._query_after_buildings = False
                self.query_classrooms()

        self._run(task, on_done=done)

    @staticmethod
    def _order_buildings(buildings, campus):
        """二校区的教学楼按常用顺序排列：教十一楼（默认）、教九楼B座、教十楼B座、教八楼B座，其余往后排。"""
        if campus != "二校区":
            return buildings
        priority = ["教十一楼", "教九楼B座", "教十楼B座", "教八楼B座"]
        ordered = []
        for name in priority:
            for item in buildings:
                if item[1] == name and item not in ordered:
                    ordered.append(item)
                    break
        rest = [item for item in buildings if item not in ordered]
        return ordered + rest

    def query_classrooms(self):
        xqbh = dict(CAMPUSES).get(self.campus_var.get(), "2")
        idx = self.building_combo.current()
        building_id = self._buildings[idx - 1][0] if self._buildings and idx >= 1 else ""
        week_from = self._week_code(self.week_from_var.get())
        week_to = self._week_code(self.week_to_var.get())
        day_from = str(WEEKDAYS.index(self.day_from_var.get()) + 1)
        day_to = str(WEEKDAYS.index(self.day_to_var.get()) + 1)
        jc_from = self._section_code(self.jc_from_var.get())
        jc_to = self._section_code(self.jc_to_var.get())
        self.classroom_note.config(text="查询中…")

        def task():
            current = self.client.get_current_week() or 1
            w1 = week_from or current
            w2 = week_to or current
            rows = self.client.get_free_classrooms(xqbh, building_id, w1, w2, day_from, day_to, jc_from, jc_to)
            return rows, w1, w2

        def done(result):
            rows, w1, w2 = result
            self.classroom_debug.delete("1.0", tk.END)
            if rows:
                names = self._classroom_names(rows)
                self.classroom_grid.set_names(names)
                week_text = f"第 {w1} 周" if w1 == w2 else f"第 {w1}-{w2} 周"
                self.classroom_note.config(text=f"{week_text} · 共 {len(names)} 间教室")
            else:
                self.classroom_grid.set_names([])
                self.classroom_note.config(text="未查询到空闲教室（或需要重新登录）")

        self._run(task, on_done=done)

    @staticmethod
    def _classroom_names(rows):
        """从查询结果里取教室名称：
        普通表格找“教室名称”列；实际返回格式则取每行第一个格子（形如 教十一楼A102(188/66)）。"""
        if not rows:
            return []
        headers = [str(h).strip() for h in rows[0]]
        for i, h in enumerate(headers):
            if "教室名称" in h or h == "教室":
                return [str(row[i]).strip() for row in rows[1:] if i < len(row) and str(row[i]).strip()]
        # 实际格式：教室名在每行第一个格子里，去掉“（容纳/座位）”后缀
        names = []
        for row in rows[1:]:
            cell = str(row[0]).strip() if row else ""
            if not cell:
                continue
            cell = re.sub(r"\s*\(\d+\s*/\s*\d+\)\s*$", "", cell)
            if cell:
                names.append(cell)
        return names

    @staticmethod
    def _section_code(text):
        """节次文本转两位数字：'第3节' -> '03'；空值返回空串。"""
        text = str(text or "").strip()
        if not text:
            return ""
        n = text.replace("第", "").replace("节", "").strip()
        return f"{int(n):02d}" if n.isdigit() else ""

    @staticmethod
    def _week_code(text):
        """周次文本转数字：'第10周' -> '10'；空值返回空串。"""
        text = str(text or "").strip()
        if not text:
            return ""
        n = text.replace("第", "").replace("周", "").strip()
        return str(int(n)) if n.isdigit() else ""

    # ---------- 空闲教室自动节次与自动查询 ----------
    def _on_tab_changed(self, event=None):
        if self.notebook.index(self.notebook.select()) == self._classroom_tab_index():
            self._on_classroom_tab_open()

    def _classroom_tab_index(self):
        for i, tab_id in enumerate(self.notebook.tabs()):
            if "空闲教室" in self.notebook.tab(tab_id, "text"):
                return i
        return -1

    def _on_classroom_tab_open(self):
        jc_from, jc_to = self._auto_sections()
        self.jc_from_var.set(jc_from)
        self.jc_to_var.set(jc_to)
        if not self._buildings:
            self.load_buildings()

    def _on_campus_changed(self, event=None):
        """切换校区：重新加载教学楼，加载完成后自动查询一次。"""
        self._query_after_buildings = True
        self.load_buildings()

    def _schedule_classroom_query(self):
        """条件变化后延时 400ms 查询一次，连续改动只触发最后一次。"""
        if self._classroom_query_job:
            self.after_cancel(self._classroom_query_job)
        self._classroom_query_job = self.after(400, self.query_classrooms)

    @staticmethod
    def _auto_sections(now=None):
        """按当前时间自动选择节次范围。"""
        now = now or datetime.datetime.now()
        minutes = now.hour * 60 + now.minute
        if minutes < 8 * 60:              # 8点前
            return "第1节", "第2节"
        if minutes < 10 * 60:             # 8点-10点
            return "第3节", "第4节"
        if minutes < 14 * 60 + 30:        # 10点-14:30
            return "第5节", "第6节"
        if minutes < 16 * 60 + 10:        # 14:30-16:10
            return "第7节", "第8节"
        return "第9节", "第10节"           # 16:10之后

    # ---------- 工具方法 ----------
    def _run(self, fn, on_done=None, on_error=None):
        def worker():
            try:
                result = fn()
                self.after(0, lambda result=result: on_done(result) if on_done else None)
            except Exception as e:  # noqa: BLE001 - 界面线程要兜住所有网络错误
                self.after(0, lambda e=e: (on_error(e) if on_error else self._show_error(e)))

        threading.Thread(target=worker, daemon=True).start()

    def _show_error(self, e):
        messagebox.showerror("出错了", str(e))

    @staticmethod
    def fill_tree(tree, rows, widths=None):
        tree.delete(*tree.get_children())
        if not rows:
            return
        headers = rows[0]
        tree["columns"] = list(range(len(headers)))
        for i, h in enumerate(headers):
            tree.heading(i, text=h or f"列{i + 1}")
            tree.column(i, width=(widths[i] if widths and i < len(widths) else 130), anchor="center")
        for r, row in enumerate(rows[1:]):
            tree.insert(
                "", "end",
                values=[row[i] if i < len(row) else "" for i in range(len(headers))],
                tags=(f"r{r % 2}",),
            )
        tree.tag_configure("r0", background="#FFFFFF")
        tree.tag_configure("r1", background="#F2F6FB")

    @staticmethod
    def _fmt_time(epoch):
        return time.strftime("%m-%d %H:%M", time.localtime(epoch)) if epoch else "未知"

    def show_login(self):
        self.main_frame.pack_forget()
        self.login_frame.pack(fill="both", expand=True)

    def show_main(self):
        self.login_frame.pack_forget()
        self.main_frame.pack(fill="both", expand=True)
