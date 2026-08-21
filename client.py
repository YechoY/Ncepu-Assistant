"""NCEPU 教务系统接口封装（requests + lxml）。"""

import datetime
import re
from pathlib import Path

import requests
from lxml import html

BASE = "https://jwxt.ncepu.edu.cn"
SESS_URL = BASE + "/Logon.do?method=logon&flag=sess"   # 获取加密种子
LOGIN_URL = BASE + "/Logon.do?method=logon"            # 正式登录
MAIN_URL = BASE + "/jsxsd/framework/xsMain.jsp"        # 主页（登录验证用）
MAIN_PAGE_URL = BASE + "/jsxsd/framework/xsMain_new.jsp"      # 主页新版（含当前周次）
MAIN_KB_URL = BASE + "/jsxsd/framework/main_index_loadkb.jsp"  # 课表数据：POST rq=日期
GRADES_URL = BASE + "/jsxsd/kscj/cjcx_list"            # 课程成绩列表
BUILDING_URL = BASE + "/jsxsd/kbxx/jsjy_processAjax"   # 教学楼 / 空闲教室
EXAM_URL = BASE + "/jsxsd/xsks/xsksap_list"            # 考试安排
CLASSROOM_QUERY_URL = BASE + "/jsxsd/kbxx/jsjy_query2"  # 空闲教室查询

TIMEOUT = 10
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36")


class LoginError(Exception):
    pass


class JwcClient:
    """负责登录、抓取课表 / 成绩 / 空闲教室，并保持会话 cookie。"""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": UA})

    # ---------- 连接检测 ----------
    def online(self, timeout=3):
        try:
            self.session.get(BASE, timeout=timeout, allow_redirects=True)
            return True
        except requests.RequestException:
            return False

    # ---------- 登录 ----------
    def login(self, username, password):
        try:
            r = self.session.post(SESS_URL, timeout=TIMEOUT)
            data_str = r.text.strip()
        except requests.RequestException as e:
            raise LoginError(f"无法连接教务系统：{e}") from e

        if not data_str:
            raise LoginError("登录失败：加密种子为空，请确认已连接校园网")

        encoded = self._make_encoded(username, password, data_str)

        # TODO: 如果登录一直失败，把浏览器 F12 中“点登录”按钮发出的请求
        # （请求地址 + 表单内容）贴给我，我按真实格式修正。
        payload = {
            "userAccount": username,
            "userPassword": password,
            "RANDOMCODE": "",
            "encoded": encoded,
        }
        try:
            self.session.post(LOGIN_URL, data=payload, timeout=TIMEOUT)
        except requests.RequestException as e:
            raise LoginError(f"登录请求失败：{e}") from e

        if not self.check_login():
            raise LoginError("登录失败：账号或密码错误（也可能是加密算法不匹配）")

    def _make_encoded(self, username, password, data_str):
        """强智教务通用算法：把返回的种子切成 scode / sxh 两段，
        再与“学号%%%密码”逐字符交叉混合得到 encoded。"""
        sep = next((s for s in ("#", ";", "|") if s in data_str), None)
        if sep is None:
            raise LoginError(f"无法解析登录种子：{data_str[:60]!r}")
        scode, sxh = data_str.split(sep, 1)
        code = username + "%%%" + password
        encoded = ""
        for i, ch in enumerate(code):
            n = int(sxh[i]) if i < len(sxh) and sxh[i].isdigit() else 0
            encoded += ch + scode[:n]
            scode = scode[n:]
        # 方便你在浏览器登录时对比 F12 里的 encoded 是否一致
        print("DEBUG encoded =", encoded)
        return encoded

    def check_login(self):
        """是否已经处于登录状态（能打开主页且没有跳回登录页）。"""
        try:
            r = self.session.get(MAIN_URL, timeout=TIMEOUT, allow_redirects=True)
            if "Logon.do" in r.url:
                return False
            text = r.text
            return ("xsMain" in r.url) or ("本周课表" in text) or ("退出" in text)
        except requests.RequestException:
            return False

    def get_current_week(self):
        """从主页文本里找“第X周”，返回当前周次；找不到返回 None。"""
        for url in (MAIN_PAGE_URL, MAIN_URL):
            try:
                r = self.session.get(url, timeout=TIMEOUT)
            except requests.RequestException:
                continue
            r.encoding = r.apparent_encoding or "utf-8"
            m = re.search(r"第\s*(\d{1,2})\s*周", r.text)
            if m:
                week = int(m.group(1))
                if week > 0:
                    return week
        return None

    def get_semester_info(self):
        """返回 (当前周次, 本学期总周数)，取不到的部分为 None。"""
        for url in (MAIN_PAGE_URL, MAIN_URL):
            try:
                r = self.session.get(url, timeout=TIMEOUT)
            except requests.RequestException:
                continue
            r.encoding = r.apparent_encoding or "utf-8"
            try:
                doc = html.fromstring(r.text)
            except Exception:
                continue
            # 主页周次结构：<div id="li_showWeek"><span>第16周</span>/26周</div>
            node = doc.xpath("//*[@id='li_showWeek']")
            if node:
                nums = re.findall(r"(\d{1,2})\s*周", node[0].text_content() or "")
                current = int(nums[0]) if nums and int(nums[0]) > 0 else None
                total = int(nums[1]) if len(nums) > 1 and int(nums[1]) > 0 else None
                if current is not None:
                    return current, total
            # 兜底：从整页文字里找
            text = r.text
            m = re.search(r"(?:当前|本学期|本周)[^<]{0,20}?第\s*(\d{1,2})\s*周", text)
            if not m:
                m = re.search(r"第\s*(\d{1,2})\s*周", text)
            current = int(m.group(1)) if m and int(m.group(1)) > 0 else None
            total = None
            for pattern in (
                r"共\s*(\d{1,2})\s*周",
                r"(\d{1,2})\s*周(?:课程|教学|课)",
                r"本学期[^<]{0,30}?(\d{1,2})\s*周",
            ):
                m2 = re.search(pattern, text)
                if m2:
                    total = int(m2.group(1))
                    break
            if current is not None:
                return current, total
        return None, None

    # ---------- 课表 ----------
    def get_timetable(self):
        """本周课表：和网页一样，POST 今天的日期给课表接口。"""
        return self.get_timetable_by_date(datetime.date.today().isoformat())

    def get_timetable_by_date(self, date_str):
        """按日期查课表（POST rq=日期，服务器自己换算第几周）。
        返回结构化数据方便界面画卡片：
        [[节次, 周一, ...], [节次值, {name,location,attr,credits} 或 '', ...], ...]"""
        try:
            doc = self._fetch_timetable_doc(date_str)
            table = self._pick_table(doc)
        except Exception:
            return []
        if table is None:
            return []
        rows = []
        for tr in table.xpath(".//tr"):
            cells = [self._cell_info(td) for td in tr.xpath(".//th | .//td")]
            if any(cells):
                rows.append(cells)
        return rows

    def _fetch_timetable_doc(self, date_str):
        r = self.session.post(
            MAIN_KB_URL,
            data={"rq": date_str},
            headers={
                "Referer": MAIN_PAGE_URL,
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "X-Requested-With": "XMLHttpRequest",
            },
            timeout=TIMEOUT,
        )
        r.encoding = r.apparent_encoding or "utf-8"
        return html.fromstring(r.text)

    # ---------- 课程成绩 ----------
    def get_grades(self):
        data = {"kksj": "", "kcxz": "", "kcmc": "", "xsfs": "all"}
        r = self.session.post(
            GRADES_URL,
            data=data,
            timeout=TIMEOUT,
            headers={
                "Referer": BASE + "/jsxsd/kscj/cjcx_query",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        r.encoding = r.apparent_encoding or "utf-8"
        table = self._pick_table(html.fromstring(r.text))
        rows = self._table_rows(table) if table is not None else []
        if rows:
            print("DEBUG grades headers =", rows[0])
        return rows

    def get_current_term(self):
        """从主页/查询页文本找当前学年学期，形如 2025-2026-2；找不到返回空串。"""
        cn_digit = {"一": "1", "二": "2", "三": "3"}
        pages = (
            MAIN_PAGE_URL,
            MAIN_URL,
            BASE + "/jsxsd/kbxx/jsjy_query",
            BASE + "/jsxsd/xsks/xsksap_query",
        )
        for url in pages:
            try:
                r = self.session.get(url, timeout=TIMEOUT)
            except requests.RequestException:
                continue
            r.encoding = r.apparent_encoding or "utf-8"
            m = re.search(r"(\d{4}-\d{4}-[123])", r.text)
            if m:
                return m.group(1)
            m = re.search(r"(\d{4})-(\d{4})[^0-9]{0,8}?([一二三])", r.text)
            if m:
                return f"{m.group(1)}-{m.group(2)}-{cn_digit[m.group(3)]}"
        return ""

    def get_exams(self, term=""):
        """考试安排：POST 表单，返回解析后的表格行。"""
        if not term:
            term = self.get_current_term()
        data = {"xqlbmc": "", "xnxqid": term, "kc": "", "ksjs": "", "jkls": ""}
        r = self.session.post(
            EXAM_URL,
            data=data,
            timeout=TIMEOUT,
            headers={
                "Referer": BASE + "/jsxsd/xsks/xsksap_query",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        r.encoding = r.apparent_encoding or "utf-8"
        print(f"DEBUG exam response len={len(r.text)} term={term!r}")
        try:
            doc = html.fromstring(r.text)
        except Exception as e:
            print("DEBUG exam parse failed:", e)
            return []
        print("DEBUG exam tables =", len(doc.xpath("//table")))
        table = self._pick_table(doc)
        rows = self._table_rows(table) if table is not None else []
        print("DEBUG exam rows =", len(rows))
        if rows:
            print("DEBUG exam headers =", rows[0])
        return rows

    # ---------- 空闲教室 ----------
    def get_buildings(self, xqid="1"):
        """教学楼列表（你已经抓到的 requestType=jxl）。"""
        r = self.session.get(BUILDING_URL, params={"xqid": xqid, "requestType": "jxl"}, timeout=TIMEOUT)
        return self._parse_payload(r)

    def get_free_classrooms(self, xqid, building_id, week_from, week_to, day_from, day_to, jc_from, jc_to):
        """空闲教室查询：按抓包的真实请求 POST jsjy_query2。"""
        term = self.get_current_term()
        data = {
            "typewhere": "jszq",
            "xnxqh": term,
            "xqbh": xqid,
            "jxqbh": "",
            "jxlbh": building_id or "",
            "jsbh": "",
            "bjfh": "=",
            "rnrs": "",
            "jszt": "8",
            "zc": week_from,
            "zc2": week_to,
            "xq": day_from,
            "xq2": day_to,
            "jc": jc_from or "",
            "jc2": jc_to or "",
            "jsjylx": "",
        }
        print("DEBUG classroom request =", data)
        r = self.session.post(
            CLASSROOM_QUERY_URL,
            data=data,
            timeout=TIMEOUT,
            headers={
                "Referer": BASE + "/jsxsd/kbxx/jsjy_query",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        r.encoding = r.apparent_encoding or "utf-8"
        try:
            Path.home().joinpath(".ncepu_jwc").mkdir(parents=True, exist_ok=True)
            Path.home().joinpath(".ncepu_jwc", "classroom_debug.html").write_text(r.text, encoding="utf-8")
        except Exception:
            pass
        print(f"DEBUG classroom response len={len(r.text)}")
        try:
            doc = html.fromstring(r.text)
        except Exception as e:
            print("DEBUG classroom parse failed:", e)
            return []
        print("DEBUG classroom tables =", len(doc.xpath("//table")))
        table = self._pick_table(doc)
        rows = self._table_rows(table) if table is not None else []
        print("DEBUG classroom rows =", len(rows))
        if rows:
            print("DEBUG classroom headers =", rows[0])
            print("DEBUG classroom first row =", rows[1] if len(rows) > 1 else None)
            print("DEBUG classroom cell counts =", [len(row) for row in rows[:8]])
        return rows

    # ---------- 通用解析 ----------
    def _parse_payload(self, r):
        r.encoding = r.apparent_encoding or "utf-8"
        text = r.text.strip()
        try:
            return r.json()
        except ValueError:
            pass
        try:
            table = self._pick_table(html.fromstring(text))
            if table is not None:
                return self._table_rows(table)
        except Exception:
            pass
        return text  # 实在解析不了就原样返回，方便调试

    @staticmethod
    def _pick_table(doc):
        tables = doc.xpath("//table")
        if not tables:
            return None
        return max(tables, key=lambda t: len(t.xpath(".//tr")))

    @staticmethod
    def _table_rows(table):
        rows = []
        for tr in table.xpath(".//tr"):
            cells = []
            for td in tr.xpath(".//th | .//td"):
                cells.append(JwcClient._cell_full_text(td))
            if any(cells):
                rows.append(cells)
        return rows

    @staticmethod
    def _cell_full_text(td):
        """单元格文本：课程类单元格取完整课程名+地点，其余用可见文本。"""
        info = JwcClient._cell_info(td)
        if isinstance(info, dict):
            name = info.get("name", "")
            location = info.get("location", "")
            return f"{name} {location}" if location else name
        return info

    @staticmethod
    def _cell_info(td):
        """课程单元格返回 {name, location, attr, credits}，否则返回可见文本。"""
        info = JwcClient._title_lines(JwcClient._cell_title(td))
        if "课程名称" in info:
            return {
                "name": info["课程名称"],
                "location": info.get("上课地点", ""),
                "attr": info.get("课程属性", ""),
                "credits": info.get("课程学分", ""),
            }
        return JwcClient._cell_visible_text(td)

    @staticmethod
    def _cell_visible_text(td):
        parts = [p.strip() for p in td.xpath(".//text()") if p.strip()]
        return " ".join(" ".join(p.split()) for p in parts)

    @staticmethod
    def _cell_title(td):
        """取单元格自身或子元素里最长的 title（完整课程信息所在）。"""
        title = ""
        for el in [td] + td.xpath(".//*[@title]"):
            t = (el.get("title") or "").strip()
            if len(t) > len(title):
                title = t
        return title

    @staticmethod
    def _title_lines(title):
        lines = [
            line.strip()
            for line in title.replace("<br/>", "\n").replace("<br>", "\n").split("\n")
            if line.strip()
        ]
        info = {}
        for line in lines:
            key, sep, value = line.partition("：")
            if sep:
                info[key.strip()] = value.strip()
        return info

    # ---------- cookie ----------
    def cookies_dict(self):
        return requests.utils.dict_from_cookiejar(self.session.cookies)

    def load_cookies(self, cookie_dict):
        if cookie_dict:
            self.session.cookies.update(cookie_dict)
