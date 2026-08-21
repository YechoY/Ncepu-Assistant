"""pywebview 与前端 Vue 页面之间的桥接层。

后端逻辑（登录 / 抓取 / 本地缓存）全部复用 client.py 与 storage.py，
这里只把能力包装成前端可调用的方法，返回 JSON 可序列化数据。
"""

import datetime
import re

from client import JwcClient, LoginError, MAIN_PAGE_URL, MAIN_URL
from storage import Storage

CAMPUS_NAMES = {"一校区": "1", "二校区": "2"}


class Api:
    def __init__(self):
        self._client = JwcClient()
        self._storage = Storage()

    # ---------- 启动 / 登录 ----------
    def get_startup(self):
        """启动信息：总是先显示登录页；只有勾选过“记住账号密码”才预填。"""
        account = self._storage.load_account()
        online = self._client.online()
        return {
            "online": online,
            "logged_in": False,
            "username": account.get("username", ""),
            "password": account.get("password", ""),
            "remember": bool(self._storage.load("remember", False)),
        }

    def login(self, username, password, remember):
        try:
            self._client.login(username, password)
        except LoginError as e:
            return {"ok": False, "message": self._err_msg(e)}
        cookies = self._client.cookies_dict()
        cookies["username"] = username
        self._storage.save_cookies(cookies)
        self._storage.save("remember", bool(remember))
        if remember:
            self._storage.save_account(username, password)
        else:
            self._storage.clear_account()
        return {"ok": True, "message": "登录成功"}

    def logout(self):
        """退出登录：清空当前会话；勾选过记住密码则保留账号密码，否则删除。"""
        self._storage.save_cookies({})
        if not bool(self._storage.load("remember", False)):
            self._storage.clear_account()

    def cleanup_on_close(self):
        """窗口关闭：未勾选记住密码时，删除本地保存的账号密码与会话。"""
        if not bool(self._storage.load("remember", False)):
            self._storage.clear_account()
            self._storage.save_cookies({})

    def get_about_hidden(self):
        """启动弹窗是否被勾选“不再显示”。"""
        return bool(self._storage.load("about_hidden", False))

    def set_about_hidden(self, hidden):
        self._storage.save("about_hidden", bool(hidden))

    def get_user_info(self):
        """从首页抓取 姓名 / 学号 / 班级（尽力解析，抓不到的部分为空）。
        首页（xsMain.jsp）里的“学生编号”就是学号。"""
        for url in (MAIN_PAGE_URL, MAIN_URL):
            try:
                r = self._client.session.get(url, timeout=10)
                r.encoding = r.apparent_encoding or "utf-8"
                text = re.sub(r"<[^>]+>", " ", r.text)
                text = re.sub(r"\s+", " ", text)
            except Exception:
                continue
            info = {}
            m = re.search(r"(?:学生编号|学号)[:：\s]*([0-9A-Za-z]{4,})", text)
            if m:
                info["sid"] = m.group(1)
            m = re.search(r"欢迎[^0-9A-Za-z]{0,6}?([\u4e00-\u9fa5]{2,4})\s*(?:同学|，|,)", text)
            if not m:
                m = re.search(r"(?:姓名|学生姓名)[:：\s]*([\u4e00-\u9fa5]{2,4})", text)
            if m:
                info["name"] = m.group(1)
            m = re.search(r"(?:班级名称|班级)[:：\s]*([\u4e00-\u9fa5A-Za-z0-9\-]{2,20})", text)
            if m:
                info["className"] = m.group(1).strip()
            if info:
                print("DEBUG user info =", info)
                return info
        print("DEBUG user info = {}")
        return {}

    # ---------- 课表 ----------
    def get_timetable(self, date_str=None):
        try:
            rows = self._client.get_timetable_by_date(
                date_str or datetime.date.today().isoformat()
            )
            self._storage.save("timetable", rows)
            source = "online"
        except Exception:
            rows = self._storage.load("timetable", [])
            source = "cache"
        semester = self._semester()
        return {
            "rows": rows,
            "current": semester["current"],
            "total": semester["total"],
            "updated": self._storage.last_update("timetable"),
            "source": source,
        }

    # ---------- 成绩 ----------
    def get_grades(self):
        try:
            rows = self._client.get_grades()
            self._storage.save("grades", rows)
            source = "online"
        except Exception:
            rows = self._storage.load("grades", [])
            source = "cache"
        return {
            "rows": rows,
            "updated": self._storage.last_update("grades"),
            "source": source,
        }

    # ---------- 考试安排 ----------
    def get_exams(self):
        try:
            rows = self._client.get_exams()
            self._storage.save("exams", rows)
            source = "online"
        except Exception:
            rows = self._storage.load("exams", [])
            source = "cache"
        return {
            "rows": rows,
            "updated": self._storage.last_update("exams"),
            "source": source,
        }

    # ---------- 空闲教室 ----------
    def get_buildings(self, campus_name="二校区"):
        try:
            payload = self._client.get_buildings(CAMPUS_NAMES.get(campus_name, "2"))
            buildings = self._normalize_buildings(payload)
            buildings = self._order_buildings(buildings, campus_name)
            return {"buildings": buildings}
        except Exception as e:
            return {"buildings": [], "message": self._err_msg(e)}

    def query_classrooms(self, params):
        try:
            rows = self._client.get_free_classrooms(
                params.get("campus", "2"),
                params.get("building", ""),
                params.get("week_from", ""),
                params.get("week_to", ""),
                params.get("day_from", "1"),
                params.get("day_to", "1"),
                params.get("jc_from", ""),
                params.get("jc_to", ""),
            )
            return {"names": self._classroom_names(rows), "ok": True}
        except Exception as e:
            return {"names": [], "ok": False, "message": self._err_msg(e)}

    # ---------- 内部工具 ----------
    @staticmethod
    def _err_msg(e):
        """把底层异常转成普通用户能看懂的中文提示。"""
        text = str(e)
        low = text.lower()
        if "timeout" in low or "timed out" in low:
            return "连接超时，请检查网络后重试"
        if "connect" in low or "connection" in low or "无法连接" in text:
            return "无法连接教务系统，请确认已连接校园网"
        if "登录" in text:
            return text
        return "操作失败，请重试"

    def _semester(self):
        try:
            current, total = self._client.get_semester_info()
            return {"current": current, "total": total}
        except Exception:
            return {"current": None, "total": None}

    @staticmethod
    def _collect_lists(obj):
        if isinstance(obj, list):
            yield obj
        elif isinstance(obj, dict):
            for value in obj.values():
                yield from Api._collect_lists(value)

    @staticmethod
    def _to_building(item):
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

    @staticmethod
    def _normalize_buildings(result):
        buildings = []
        for items in Api._collect_lists(result):
            for item in items:
                building = Api._to_building(item)
                if building:
                    buildings.append(building)
            if buildings:
                break
        if not buildings and isinstance(result, dict):
            keys = [str(k) for k in result.keys()]
            if keys and all(k.isdigit() for k in keys) and all(isinstance(v, str) for v in result.values()):
                buildings = [(k, result[k]) for k in result]
        return buildings

    @staticmethod
    def _order_buildings(buildings, campus_name):
        if campus_name != "二校区":
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

    @staticmethod
    def _classroom_names(rows):
        if not rows:
            return []
        headers = [str(h).strip() for h in rows[0]]
        for i, h in enumerate(headers):
            if "教室名称" in h or h == "教室":
                return [str(row[i]).strip() for row in rows[1:] if i < len(row) and str(row[i]).strip()]
        names = []
        for row in rows[1:]:
            cell = str(row[0]).strip() if row else ""
            if not cell:
                continue
            cell = re.sub(r"\s*\(\d+\s*/\s*\d+\)\s*$", "", cell)
            if cell:
                names.append(cell)
        return names
