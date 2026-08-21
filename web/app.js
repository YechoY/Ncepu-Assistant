const { createApp } = Vue;

let api = null;

const APP_INFO = {
  name: "NCEPU 教务助手",
  version: "1.0.0",
  desc: "课表 · 成绩 · 考试安排 · 空闲教室",
  author: "Yecho",
  contact: "https://github.com/YechoY",
};

const WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];
const SECTIONS = Array.from({ length: 10 }, (_, i) => "第" + (i + 1) + "节");
const WEEKS = Array.from({ length: 30 }, (_, i) => "第" + (i + 1) + "周");

const COURSE_COLORS = [
  { bg: "#eff6ff", border: "#bfdbfe", name: "#1e3a8a" },
  { bg: "#f0fdf4", border: "#bbf7d0", name: "#14532d" },
  { bg: "#fef2f2", border: "#fecaca", name: "#7f1d1d" },
  { bg: "#fff7ed", border: "#fed7aa", name: "#7c2d12" },
  { bg: "#f5f3ff", border: "#ddd6fe", name: "#4c1d95" },
  { bg: "#fdf2f8", border: "#fbcfe8", name: "#831843" },
  { bg: "#f0f9ff", border: "#bae6fd", name: "#0c4a6e" },
  { bg: "#fefce8", border: "#fde68a", name: "#713f12" },
];

function courseColor(name) {
  let h = 0;
  const s = String(name || "");
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return COURSE_COLORS[h % COURSE_COLORS.length];
}

function todayStr() {
  const d = new Date();
  const p = n => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function fmtTime(epoch) {
  if (!epoch) return "未知";
  const d = new Date(epoch * 1000);
  const p = n => String(n).padStart(2, "0");
  return `${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function todayWeekdayName() {
  return WEEKDAYS[(new Date().getDay() + 6) % 7];
}

function autoSections() {
  const d = new Date();
  const m = d.getHours() * 60 + d.getMinutes();
  if (m < 480) return ["第1节", "第2节"];
  if (m < 600) return ["第3节", "第4节"];
  if (m < 870) return ["第5节", "第6节"];
  if (m < 970) return ["第7节", "第8节"];
  return ["第9节", "第10节"];
}

function findCol(headers, names) {
  for (let i = 0; i < headers.length; i++) {
    for (const n of names) {
      if (headers[i] === n || headers[i].startsWith(n) || headers[i].includes(n)) return i;
    }
  }
  return -1;
}

function gradeScore(text) {
  const map = { "优": 95, "优秀": 95, "良": 85, "良好": 85, "中": 75, "中等": 75, "及格": 65, "合格": 65, "不及格": 55, "不合格": 55 };
  const s = String(text || "").trim();
  if (!s) return null;
  if (map[s] !== undefined) return map[s];
  const n = parseFloat(s);
  return isNaN(n) ? null : n;
}

function examFinished(timeText) {
  const s = String(timeText || "").trim();
  const m = s.match(/(\d{4})[-/年.](\d{1,2})[-/月.](\d{1,2})/);
  if (!m) return false;
  let m2 = s.match(/(\d{1,2}):(\d{2})\s*[-~至到]\s*(\d{1,2}):(\d{2})/);
  let h, min;
  if (m2) { h = +m2[3]; min = +m2[4]; }
  else {
    m2 = s.match(/(\d{1,2}):(\d{2})/);
    if (!m2) return false;
    h = +m2[1]; min = +m2[2];
  }
  return Date.now() > new Date(+m[1], +m[2] - 1, +m[3], h, min).getTime();
}

createApp({
  data() {
    return {
      view: "login",
      tab: "timetable",
      showAbout: false,
      aboutNever: false,
      about: Object.assign({}, APP_INFO),
      tabs: [
        { key: "timetable", name: "课表", icon: "📅" },
        { key: "grades", name: "课程成绩", icon: "📊" },
        { key: "exams", name: "考试安排", icon: "📝" },
        { key: "classrooms", name: "空闲教室", icon: "🏫" },
      ],

      // 登录
      username: "",
      password: "",
      remember: false,
      loginMsg: "",
      loginError: false,
      loginBusy: false,

      // 课表
      tt: { rows: [], current: null, total: null, updated: null, source: "" },
      ttDate: todayStr(),
      ttWeek: null,
      ttLoading: false,
      userInfo: { name: "", sid: "", className: "" },
      calOpen: false,
      calYear: new Date().getFullYear(),
      calMonth: new Date().getMonth() + 1,

      // 成绩
      grades: { rows: [], updated: null, source: "" },
      termFilter: "全部学期",
      nameFilter: "",
      attrFilter: "全部属性",
      sortCol: null,
      sortDir: 1,
      gradeLoading: false,

      // 考试
      exams: { rows: [], updated: null, source: "" },
      examLoading: false,

      // 空闲教室
      campus: "二校区",
      buildings: [],
      building: "全部",
      dayFrom: todayWeekdayName(),
      dayTo: todayWeekdayName(),
      jcFrom: "",
      jcTo: "",
      weekFrom: "",
      weekTo: "",
      classNames: [],
      classLoading: false,
      classMsg: "",
      classTimer: null,
    };
  },

  computed: {
    // ---------- 课表 ----------
    ttHeaders() {
      return this.tt.rows && this.tt.rows.length ? this.tt.rows[0] : [];
    },
    ttRows() {
      return this.tt.rows ? this.tt.rows.slice(1) : [];
    },
    ttStyle() {
      const n = Math.max(this.ttHeaders.length - 1, 1);
      return { "grid-template-columns": "74px repeat(" + n + ", 1fr)" };
    },
    weekText() {
      const cur = this.ttWeek || this.tt.current;
      if (!cur) return "当前周次未知";
      return this.tt.total ? `第 ${cur} 周 / 共 ${this.tt.total} 周` : `第 ${cur} 周`;
    },

    // ---------- 成绩 ----------
    gradeMeta() {
      const rows = this.grades.rows || [];
      if (!rows.length) return { headers: [], data: [], terms: [], attrs: [] };
      const headers = rows[0].map(h => String(h).trim());
      const termIdx = findCol(headers, ["学年学期", "开课学期", "学期"]);
      const nameIdx = findCol(headers, ["课程名称"]);
      let gradeIdx = -1;
      for (const n of ["总评成绩", "期末成绩", "补考成绩", "重修成绩", "平时成绩"]) {
        const i = findCol(headers, [n]);
        if (i >= 0) { gradeIdx = i; break; }
      }
      if (gradeIdx < 0) gradeIdx = headers.indexOf("成绩");
      const attrIdx = findCol(headers, ["课程性质", "课程属性", "课程类别", "课程类型"]);
      const creditIdx = findCol(headers, ["学分"]);

      const terms = [];
      const attrs = [];
      rows.slice(1).forEach(r => {
        const t = termIdx >= 0 && r[termIdx] !== undefined ? String(r[termIdx]).trim() : "";
        if (t && !terms.includes(t)) terms.push(t);
        const a = attrIdx >= 0 && r[attrIdx] !== undefined ? String(r[attrIdx]).trim() : "";
        if (a && !attrs.includes(a)) attrs.push(a);
      });
      const termFilter = this.termFilter;
      const nameFilter = this.nameFilter.trim().toLowerCase();
      const attrFilter = this.attrFilter;
      const data = [];
      rows.slice(1).forEach(r => {
        const term = termIdx >= 0 && r[termIdx] !== undefined ? String(r[termIdx]).trim() : "";
        const name = nameIdx >= 0 && r[nameIdx] !== undefined ? String(r[nameIdx]).trim() : "";
        const attr = attrIdx >= 0 && r[attrIdx] !== undefined ? String(r[attrIdx]).trim() : "";
        if (termFilter !== "全部学期" && term !== termFilter) return;
        if (nameFilter && !name.toLowerCase().includes(nameFilter)) return;
        if (attrFilter !== "全部属性" && attr !== attrFilter) return;
        data.push({
          term,
          name,
          grade: gradeIdx >= 0 && r[gradeIdx] !== undefined ? String(r[gradeIdx]).trim() : "",
          attr,
          credit: creditIdx >= 0 && r[creditIdx] !== undefined ? String(r[creditIdx]).trim() : "",
        });
      });
      // 排序：开课学期 / 成绩 / 学分
      const cmp = (a, b) => {
        if (a === null && b === null) return 0;
        if (a === null) return 1;
        if (b === null) return -1;
        return (a - b) * this.sortDir;
      };
      if (this.sortCol === 1) {
        data.sort((x, y) => x.term.localeCompare(y.term, "zh") * this.sortDir);
      } else if (this.sortCol === 3) {
        data.sort((x, y) => cmp(gradeScore(x.grade), gradeScore(y.grade)));
      } else if (this.sortCol === 5) {
        data.sort((x, y) => cmp(parseFloat(x.credit) || null, parseFloat(y.credit) || null));
      }
      return { headers, data, terms, attrs };
    },
    gradeHeaders() {
      return ["序号", "开课学期", "课程名称", "成绩", "课程属性", "学分"];
    },
    gradeRows() {
      return this.gradeMeta.data.map((g, i) => [String(i + 1), g.term, g.name, g.grade, g.attr, g.credit]);
    },
    termOptions() {
      return ["全部学期", ...this.gradeMeta.terms];
    },
    attrOptions() {
      return ["全部属性", ...this.gradeMeta.attrs];
    },
    sortableCols() {
      return [1, 3, 5];
    },
    gpaText() {
      let count = 0, credits = 0, scores = 0;
      this.gradeMeta.data.forEach(g => {
        if (!String(g.attr || "").startsWith("必修")) return;
        const sc = gradeScore(g.grade);
        const cr = parseFloat(g.credit);
        if (sc === null || isNaN(cr) || cr <= 0) return;
        count++;
        credits += cr;
        scores += cr * sc;
      });
      if (!count) return "暂无可用必修成绩（优95 / 良85 / 中75 / 及格65 / 不及格55）";
      return `必修 ${count} 门 · 平均学分绩 ${(scores / credits).toFixed(6)}`;
    },
    gradesNote() {
      return `更新于 ${fmtTime(this.grades.updated)} · 共 ${this.gradeRows.length} 门课程` +
        (this.grades.source === "cache" ? " · 离线缓存" : "");
    },

    // ---------- 考试 ----------
    examHeaders() {
      return ["序号", "考试类型", "课程名称", "考试时间", "考试地点", "任课老师"];
    },
    examRows() {
      const rows = this.exams.rows || [];
      if (!rows.length) return [];
      const headers = rows[0].map(h => String(h).trim());
      const typeIdx = findCol(headers, ["考试类型", "考试性质"]);
      const nameIdx = findCol(headers, ["课程名称"]);
      const timeIdx = findCol(headers, ["考试时间", "考试日期", "时间"]);
      const placeIdx = findCol(headers, ["考试地点", "地点", "教室"]);
      const teacherIdx = findCol(headers, ["任课教师", "任课老师", "教师", "老师"]);
      return rows.slice(1).map((r, i) => [
        String(i + 1),
        typeIdx >= 0 && r[typeIdx] !== undefined ? String(r[typeIdx]).trim() : "",
        nameIdx >= 0 && r[nameIdx] !== undefined ? String(r[nameIdx]).trim() : "",
        timeIdx >= 0 && r[timeIdx] !== undefined ? String(r[timeIdx]).trim() : "",
        placeIdx >= 0 && r[placeIdx] !== undefined ? String(r[placeIdx]).trim() : "",
        teacherIdx >= 0 && r[teacherIdx] !== undefined ? String(r[teacherIdx]).trim() : "",
        examFinished(timeIdx >= 0 && r[timeIdx] !== undefined ? r[timeIdx] : ""),
      ]);
    },
    examNote() {
      return `更新于 ${fmtTime(this.exams.updated)} · 共 ${this.examRows.length} 场考试` +
        (this.exams.source === "cache" ? " · 离线缓存" : "");
    },

    sidText() {
      return this.userInfo.sid || this.username || "—";
    },

    // ---------- 空闲教室 ----------
    weekdays() { return WEEKDAYS; },
    sections() { return SECTIONS; },
    weeks() { return WEEKS; },

    // ---------- 自定义日历 ----------
    calDays() {
      const first = new Date(this.calYear, this.calMonth - 1, 1);
      const start = new Date(first);
      start.setDate(1 - ((first.getDay() + 6) % 7));
      const today = todayStr();
      const days = [];
      for (let i = 0; i < 42; i++) {
        const d = new Date(start);
        d.setDate(start.getDate() + i);
        const ds = this.dateStr(d);
        days.push({
          key: ds,
          day: d.getMonth() === this.calMonth - 1 ? d.getDate() : 0,
          today: ds === today,
          selected: ds === this.ttDate,
        });
      }
      return days;
    },
  },

  methods: {
    none() {},

    async closeAbout() {
      if (this.aboutNever) {
        try { await api.set_about_hidden(true); } catch (e) { /* 忽略 */ }
      }
      this.showAbout = false;
    },

    async init() {
      if (!api) {
        this.loginMsg = "无法连接桌面后端（请通过主程序启动）";
        this.loginError = true;
        return;
      }
      try {
        try {
          const hidden = await api.get_about_hidden();
          if (!hidden) this.showAbout = true;
        } catch (e) { this.showAbout = true; }
        const s = await api.get_startup();
        if (s.password) this.password = s.password;
        if (s.username) this.username = s.username;
        this.remember = !!s.remember;
        if (s.logged_in) {
          this.view = "main";
          this.refreshAll();
        } else {
          this.loginMsg = s.online ? "请登录" : "未检测到校园网，请连接校园网后登录";
        }
      } catch (e) {
        this.loginMsg = this.errText(e);
        this.loginError = true;
      }
    },

    // ---------- 登录 ----------
    async doLogin() {
      if (!this.username || !this.password) {
        this.loginMsg = "请输入学号和密码";
        this.loginError = true;
        return;
      }
      this.loginBusy = true;
      this.loginMsg = "";
      this.loginError = false;
      try {
        const res = await api.login(this.username, this.password, this.remember);
        if (res.ok) {
          this.view = "main";
          this.refreshAll();
        } else {
          this.loginMsg = res.message || "登录失败";
          this.loginError = true;
        }
      } catch (e) {
        this.loginMsg = this.errText(e);
        this.loginError = true;
      } finally {
        this.loginBusy = false;
      }
    },

    async doLogout() {
      try { await api.logout(); } catch (e) { /* 忽略 */ }
      this.view = "login";
      this.loginMsg = "";
    },

    // ---------- 通用加载 ----------
    async refreshAll() {
      await Promise.all([this.loadTimetable(null), this.loadGrades(), this.loadExams(), this.loadUserInfo()]);
      this.loadBuildings(false);
    },

    async loadUserInfo() {
      try {
        this.userInfo = Object.assign({ name: "", sid: "", className: "" }, await api.get_user_info());
      } catch (e) {
        this.userInfo = { name: "", sid: "", className: "" };
      }
    },

    async loadTimetable(dateStr) {
      this.ttLoading = true;
      try {
        const res = await api.get_timetable(dateStr || null);
        this.tt = res;
        if (dateStr && res.current != null) {
          const target = new Date(dateStr);
          const today = new Date();
          const monday = new Date(today);
          monday.setDate(today.getDate() - ((today.getDay() + 6) % 7));
          const diff = Math.floor((target - monday) / 86400000 / 7);
          this.ttWeek = Math.max(1, res.current + diff);
        } else {
          this.ttWeek = null;
        }
      } catch (e) {
        this.tt = { rows: [], current: null, total: null, updated: null, source: "cache" };
      } finally {
        this.ttLoading = false;
      }
    },

    async loadGrades() {
      this.gradeLoading = true;
      try {
        this.grades = await api.get_grades();
      } catch (e) {
        this.grades = { rows: [], updated: null, source: "cache" };
      } finally {
        this.gradeLoading = false;
      }
    },

    async loadExams() {
      this.examLoading = true;
      try {
        this.exams = await api.get_exams();
      } catch (e) {
        this.exams = { rows: [], updated: null, source: "cache" };
      } finally {
        this.examLoading = false;
      }
    },

    resetGrades() {
      this.termFilter = "全部学期";
      this.nameFilter = "";
      this.attrFilter = "全部属性";
      this.sortCol = null;
      this.sortDir = 1;
    },

    sortMark(i) {
      if (this.sortCol !== i) return "";
      return this.sortDir === 1 ? "▲" : "▼";
    },

    toggleSort(i) {
      if (this.sortCol === i) {
        this.sortDir = -this.sortDir;
      } else {
        this.sortCol = i;
        this.sortDir = 1;
      }
    },

    toggleCal() {
      if (!this.calOpen) {
        const d = new Date(this.ttDate + "T00:00:00");
        this.calYear = d.getFullYear();
        this.calMonth = d.getMonth() + 1;
      }
      this.calOpen = !this.calOpen;
    },

    calShiftMonth(delta) {
      this.calMonth += delta;
      if (this.calMonth < 1) { this.calMonth = 12; this.calYear--; }
      if (this.calMonth > 12) { this.calMonth = 1; this.calYear++; }
    },

    pickDate(day) {
      const p = n => String(n).padStart(2, "0");
      this.ttDate = `${this.calYear}-${p(this.calMonth)}-${p(day)}`;
      this.calOpen = false;
      this.loadTimetable(this.ttDate);
    },

    // ---------- 课表：日期 / 周次切换 ----------
    dateStr(d) {
      const p = n => String(n).padStart(2, "0");
      return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
    },

    mondayOf(dateStr) {
      const d = new Date(dateStr + "T00:00:00");
      d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
      return this.dateStr(d);
    },

    resetDate() {
      this.ttDate = todayStr();
      this.loadTimetable(this.ttDate);
    },

    shiftWeek(days) {
      const monday = new Date(this.mondayOf(this.ttDate) + "T00:00:00");
      monday.setDate(monday.getDate() + days * 7);
      const target = this.dateStr(monday);
      this.ttDate = target;
      this.loadTimetable(target);
    },

    courseStyle(name) {
      const c = courseColor(name);
      return { background: c.bg, borderColor: c.border, color: c.name };
    },

    attrCredits(cell) {
      const parts = [];
      if (cell.attr) parts.push(cell.attr);
      if (cell.credits) parts.push(cell.credits + "学分");
      return parts.join(" ");
    },

    // ---------- 标签切换 ----------
    switchTab(key) {
      this.tab = key;
      if (key === "classrooms") this.onClassroomOpen();
    },

    onClassroomOpen() {
      const [a, b] = autoSections();
      this.jcFrom = a;
      this.jcTo = b;
      if (!this.buildings.length) this.loadBuildings(false);
    },

    // ---------- 空闲教室 ----------
    async loadBuildings(queryAfter) {
      this.classMsg = "正在加载教学楼…";
      try {
        const res = await api.get_buildings(this.campus);
        this.buildings = res.buildings || [];
        this.building = this.buildings.length ? this.buildings[0][0] : "全部";
        if (!this.buildings.length) this.classMsg = res.message || "教学楼加载失败";
      } catch (e) {
        this.buildings = [];
        this.classMsg = this.errText(e);
      }
      if (queryAfter) this.queryClassrooms();
    },

    onCampusChange() {
      this.loadBuildings(true);
    },

    scheduleClassQuery() {
      if (this.classTimer) clearTimeout(this.classTimer);
      this.classTimer = setTimeout(() => this.queryClassrooms(), 400);
    },

    async queryClassrooms() {
      this.classLoading = true;
      this.classMsg = "正在查询…";
      try {
        const params = {
          campus: this.campus === "二校区" ? "2" : "1",
          building: this.building === "全部" ? "" : this.building,
          week_from: this.weekCode(this.weekFrom),
          week_to: this.weekCode(this.weekTo),
          day_from: String(WEEKDAYS.indexOf(this.dayFrom) + 1),
          day_to: String(WEEKDAYS.indexOf(this.dayTo) + 1),
          jc_from: this.sectionCode(this.jcFrom),
          jc_to: this.sectionCode(this.jcTo),
        };
        const res = await api.query_classrooms(params);
        this.classNames = res.names || [];
        const w1 = this.weekCode(this.weekFrom) || "当前周";
        const w2 = this.weekCode(this.weekTo) || w1;
        const weekText = w1 === w2 ? `第 ${w1} 周` : `第 ${w1}-${w2} 周`;
        this.classMsg = res.ok
          ? `${weekText} · 共 ${this.classNames.length} 间教室`
          : (res.message || "查询失败");
      } catch (e) {
        this.classNames = [];
        this.classMsg = this.errText(e);
      } finally {
        this.classLoading = false;
      }
    },

    errText(e) {
      const s = String(e && e.message || e || "");
      if (/timeout|timed out/i.test(s)) return "连接超时，请检查网络后重试";
      if (/connect|connection|无法连接/i.test(s)) return "无法连接教务系统，请确认已连接校园网";
      return "操作失败，请重试";
    },

    weekCode(text) {
      const n = String(text || "").replace("第", "").replace("周", "").trim();
      return n && !isNaN(n) ? String(parseInt(n, 10)) : "";
    },

    sectionCode(text) {
      const n = String(text || "").replace("第", "").replace("节", "").trim();
      return n && !isNaN(n) ? String(parseInt(n, 10)).padStart(2, "0") : "";
    },
  },

  mounted() {
    const boot = () => {
      api = window.pywebview && window.pywebview.api;
      this.init();
    };
    const readyNow = () => window.pywebview && window.pywebview.api;
    if (readyNow()) {
      boot();
      return;
    }
    window.addEventListener("pywebviewready", boot);
    let tries = 0;
    const poll = setInterval(() => {
      tries++;
      if (readyNow()) {
        clearInterval(poll);
        boot();
      } else if (tries > 25) {
        clearInterval(poll);
        this.loginMsg = "无法连接桌面后端（请通过主程序启动）";
        this.loginError = true;
      }
    }, 300);
  },
}).mount("#app");
