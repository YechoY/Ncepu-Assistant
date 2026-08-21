# 华电教务助手 Flutter 安卓版 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Flutter 实现华电教务助手安卓版：登录、课表、成绩、考试、空闲教室，含离线缓存与安全存储。

**Architecture:** 四层结构——UI（5 个页面 + 胶囊导航）、状态（Riverpod）、数据（ApiClient 移植桌面版 client.py 的登录加密与 HTML 解析 + sqflite 缓存）、安全（flutter_secure_storage 存密码）。启动探测网络，在线自动登录 + 每天首次更新一次；离线有缓存直接进；退出登录清空全部数据。

**Tech Stack:** Flutter 3.47 stable / Dart 3.13，flutter_riverpod、http、html、sqflite、path_provider、path、flutter_secure_storage、shared_preferences、flutter_launcher_icons（仅开发期）。

**环境约束：** 项目在 `app/` 子目录创建；仓库仅本地，禁止推送任何云端；minSdk 26；应用名“华电教务助手”；图标源文件 `.superpowers/brainstorm/667-1787287467/icons/minimax_image_20260821_131752_0_0.jpg`。

**网络注意：** pub.dev / Google 仓库若超时，配置国内镜像（PUB_HOSTED_URL 或 Flutter 镜像）后重试；学校教务系统仅校园网可达，真机联调需校园网或 VPN。

---

## 文件结构（锁定）

```
app/
├── pubspec.yaml
├── analysis_options.yaml
├── android/                     # flutter create 生成，改 3 处（见 Task 1）
├── assets/icon/icon.png         # 由生成图转换（Task 1）
└── lib/
    ├── main.dart                # 入口：ProviderScope + 启动流程
    ├── app.dart                 # 根组件：主题 + 路由 + 启动分支
    ├── theme.dart               # 浅色渐变主题、颜色常量、胶囊导航样式
    ├── models/
    │   ├── course_cell.dart     # 课程卡数据 {name, location, attr, credits}
    │   ├── grade.dart           # 成绩行（6 列精简）
    │   ├── exam.dart            # 考试行
    │   ├── building.dart        # 教学楼 (id, name)
    │   └── timetable_row.dart   # 课表行（节次标签 + 7 列）
    ├── services/
    │   ├── api_client.dart      # 登录加密 + 4 类接口请求与解析（移植 client.py）
    │   ├── cache_service.dart   # sqflite kv + 时间戳 + TTL
    │   └── auth_service.dart    # secure storage 密码、记住/自动登录、退出清理
    ├── providers/
    │   ├── app_state.dart       # 在线状态、启动流程
    │   ├── auth_state.dart      # 登录态
    │   └── data_state.dart      # 课表/成绩/考试/教室 数据 + 每日更新 + 手动刷新
    ├── pages/
    │   ├── login_page.dart
    │   ├── timetable_page.dart
    │   ├── grades_page.dart
    │   ├── exams_page.dart
    │   └── classrooms_page.dart
    └── widgets/
        ├── capsule_nav.dart     # 4 标签胶囊导航
        ├── top_bar.dart         # 页面标题 + 刷新按钮 + 用户胶囊
        ├── offline_banner.dart  # 离线模式横幅
        ├── course_card.dart     # 课程卡 + 详情弹窗
        ├── grade_card.dart      # 成绩卡
        ├── exam_card.dart       # 考试卡
        ├── room_card.dart       # 空闲教室卡
        └── empty_view.dart      # 空状态
└── test/
    ├── encoded_test.dart        # 加密算法（基准向量）
    ├── parser_test.dart         # 4 类 HTML 解析
    ├── gpa_test.dart            # 平均学分绩
    ├── cache_test.dart          # TTL 与清理
    └── widget_test.dart         # 登录页/导航/课程卡
```

---

## Task 1：创建 Flutter 工程并配置安卓基础

**Files:**
- Create: `app/`（flutter create 产物）
- Modify: `app/android/app/build.gradle.kts`、`app/android/app/src/main/AndroidManifest.xml`、`app/pubspec.yaml`
- Create: `app/assets/icon/icon.png`（由 minimax 图转换）

- [ ] **Step 1: 创建工程**

Run（在仓库根目录）:
```bash
flutter create --project-name hdjw_assistant --org com.hdjw --platforms android app
```
Expected: `app/` 生成完整 Flutter 安卓工程。

- [ ] **Step 2: 转换图标源图**

Run（Python，Pillow 已随桌面项目可用；若缺失先 `pip install pillow`）:
```bash
python -c "from PIL import Image; im=Image.open(r'.superpowers/brainstorm/667-1787287467/icons/minimax_image_20260821_131752_0_0.jpg').convert('RGB'); im=im.resize((1024,1024)); im.save(r'app/assets/icon/icon.png')"
```
Expected: `app/assets/icon/icon.png` 存在（1024x1024）。

- [ ] **Step 3: 配置 minSdk 26**

修改 `app/android/app/build.gradle.kts`，把：
```kotlin
        minSdk = flutter.minSdkVersion
```
改为：
```kotlin
        minSdk = 26
```

- [ ] **Step 4: 应用名**

修改 `app/android/app/src/main/AndroidManifest.xml` 的 `android:label` 为 `华电教务助手`。

- [ ] **Step 5: pubspec 依赖**

`app/pubspec.yaml` 的 dependencies 增加：
```yaml
  flutter_riverpod: ^2.6.1
  http: ^1.2.2
  html: ^0.15.4
  sqflite: ^2.4.1
  path: ^1.9.0
  path_provider: ^2.1.5
  flutter_secure_storage: ^9.2.4
  shared_preferences: ^2.3.3
```
dev_dependencies 增加：
```yaml
  flutter_launcher_icons: ^0.14.2
```
并在文件末尾（flutter 段落外）加：
```yaml
flutter_launcher_icons:
  android: true
  image_path: assets/icon/icon.png
  adaptive_icon_background: "#2563eb"
  adaptive_icon_foreground: assets/icon/icon.png
  min_sdk_android: 26
```

- [ ] **Step 6: 安装依赖并生成图标**

Run:
```bash
cd app
flutter pub get
dart run flutter_launcher_icons
```
Expected: `pub get` 成功；`flutter_launcher_icons` 生成 `android/app/src/main/res/mipmap-*/ic_launcher*.png`。若网络超时，设置 `PUB_HOSTED_URL=https://pub.flutter-io.cn` 后重试。

- [ ] **Step 7: 提交**

```bash
git add app docs/superpowers/plans
git commit -m "chore: 创建 Flutter 工程并配置图标/应用名/minSdk"
```

---

## Task 2：数据模型

**Files:**
- Create: `app/lib/models/course_cell.dart`、`grade.dart`、`exam.dart`、`building.dart`、`timetable_row.dart`

- [ ] **Step 1: 写模型代码**

`app/lib/models/course_cell.dart`:
```dart
class CourseCell {
  final String name;
  final String location;
  final String attr;
  final String credits;
  const CourseCell({this.name = '', this.location = '', this.attr = '', this.credits = ''});
  bool get isEmpty => name.isEmpty && location.isEmpty && attr.isEmpty && credits.isEmpty;
  factory CourseCell.fromJson(Map<String, dynamic> j) => CourseCell(
    name: j['name'] as String? ?? '',
    location: j['location'] as String? ?? '',
    attr: j['attr'] as String? ?? '',
    credits: j['credits'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {'name': name, 'location': location, 'attr': attr, 'credits': credits};
}
```

`app/lib/models/grade.dart`:
```dart
class Grade {
  final String term, name, grade, attr, credit;
  const Grade({required this.term, required this.name, required this.grade, required this.attr, required this.credit});
  factory Grade.fromJson(Map<String, dynamic> j) => Grade(
    term: j['term'] as String? ?? '', name: j['name'] as String? ?? '',
    grade: j['grade'] as String? ?? '', attr: j['attr'] as String? ?? '',
    credit: j['credit'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {'term': term, 'name': name, 'grade': grade, 'attr': attr, 'credit': credit};
}
```

`app/lib/models/exam.dart`:
```dart
class Exam {
  final String type, name, time, location, teacher;
  const Exam({required this.type, required this.name, required this.time, required this.location, required this.teacher});
  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
    type: j['type'] as String? ?? '', name: j['name'] as String? ?? '',
    time: j['time'] as String? ?? '', location: j['location'] as String? ?? '',
    teacher: j['teacher'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {'type': type, 'name': name, 'time': time, 'location': location, 'teacher': teacher};
}
```

`app/lib/models/building.dart`:
```dart
class Building {
  final String id, name;
  const Building({required this.id, required this.name});
}
```

`app/lib/models/timetable_row.dart`:
```dart
import 'course_cell.dart';
class TimetableRow {
  final String section; // 如 "1-2"
  final List<CourseCell> cells; // 7 列，周一..周日
  const TimetableRow({required this.section, required this.cells});
}
```

- [ ] **Step 2: 提交**

```bash
git add app/lib/models
git commit -m "feat: 添加数据模型"
```

---

## Task 3：登录加密算法（TDD）

**Files:**
- Create: `app/lib/services/api_client.dart`（先只写 encoded 部分）、`app/test/encoded_test.dart`

**说明：** 算法移植自 `client.py::_make_encoded`。基准向量已由桌面版 Python 实际运行得出：

| seed | username | password | encoded |
|---|---|---|---|
| `abc#1234567890` | `2025000001` | `mypass123` | `2a0bc25000001%%%mypass123` |
| `a;1` | `2025000001` | `mypass123` | `2a025000001%%%mypass123` |
| `x#123` | `2025000002` | `pw` | `2x025000002%%%pw` |

- [ ] **Step 1: 写失败测试** `app/test/encoded_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/services/api_client.dart';

void main() {
  group('encoded 算法', () {
    test('标准种子 abc#1234567890', () {
      expect(encodeLogin('2025000001', 'mypass123', 'abc#1234567890'), '2a0bc25000001%%%mypass123');
    });
    test('分隔符 ;', () {
      expect(encodeLogin('2025000001', 'mypass123', 'a;1'), '2a025000001%%%mypass123');
    });
    test('sxh 长度不足按 0 处理', () {
      expect(encodeLogin('2025000002', 'pw', 'x#123'), '2x025000002%%%pw');
    });
    test('无分隔符抛错', () {
      expect(() => encodeLogin('a', 'b', 'noseparator'), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd app && flutter test test/encoded_test.dart`
Expected: FAIL（encodeLogin 未定义）。

- [ ] **Step 3: 实现**

在 `app/lib/services/api_client.dart` 顶部添加：
```dart
String encodeLogin(String username, String password, String dataStr) {
  final String sep;
  if (dataStr.contains('#')) { sep = '#'; }
  else if (dataStr.contains(';')) { sep = ';'; }
  else if (dataStr.contains('|')) { sep = '|'; }
  else { throw ArgumentError('无法解析登录种子: ${dataStr.length > 60 ? dataStr.substring(0, 60) : dataStr}'); }
  final parts = dataStr.split(sep);
  var scode = parts[0];
  final sxh = parts[1];
  final code = username + '%%%' + password;
  final buf = StringBuffer();
  for (var i = 0; i < code.length; i++) {
    final n = i < sxh.length && int.tryParse(sxh[i]) != null ? int.parse(sxh[i]) : 0;
    buf.write(code[i]);
    if (n > 0 && scode.length >= n) {
      buf.write(scode.substring(0, n));
      scode = scode.substring(n);
    }
  }
  return buf.toString();
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd app && flutter test test/encoded_test.dart`
Expected: 4 个测试全 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/services/api_client.dart app/test/encoded_test.dart
git commit -m "feat: 登录加密算法（含基准向量测试）"
```

---

## Task 4：ApiClient 请求与解析（TDD）

**Files:**
- Modify: `app/lib/services/api_client.dart`
- Create: `app/test/parser_test.dart`

**说明：** 全部解析函数为纯函数（输入 HTML 字符串 → 输出模型），测试用内嵌 fixture。网络部分（login/fetch）用 `package:http` 的 `Client` 实现，便于注入 MockClient 测试。

- [ ] **Step 1: 写失败测试** `app/test/parser_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/services/api_client.dart';

void main() {
  const kbHtml = '''
<html><body><table>
<tr><th>节次</th><th>星期一</th><th>星期二</th></tr>
<tr><td>1-2</td>
  <td><p title="课程学分：4.0&lt;br/&gt;课程属性：必修&lt;br/&gt;课程名称：数据结构&lt;br/&gt;上课时间：1-2节&lt;br/&gt;上课地点：教十一302">数据结构..</p></td>
  <td></td></tr>
<tr><td>3-4</td><td></td>
  <td><p title="课程学分：5.5&lt;br/&gt;课程属性：必修&lt;br/&gt;课程名称：高等数学&lt;br/&gt;上课时间：3-4节&lt;br/&gt;上课地点：教九A105">高等数学..</p></td></tr>
</table></body></html>''';

  test('解析课表', () {
    final rows = parseTimetable(kbHtml);
    expect(rows.length, 2);
    expect(rows[0].section, '1-2');
    final mon = rows[0].cells[0];
    expect(mon.name, '数据结构');
    expect(mon.location, '教十一302');
    expect(mon.attr, '必修');
    expect(mon.credits, '4.0');
    expect(rows[1].cells[1].name, '高等数学');
  });

  const gradesHtml = '''
<table>
<tr><th>序号</th><th>开课学期</th><th>课程编号</th><th>课程名称</th><th>成绩</th><th>成绩标识</th><th>学分</th><th>总学时</th><th>绩点</th><th>补重学期</th><th>考核方式</th><th>考试性质</th><th>课程属性</th><th>课程性质</th><th>通选课类别</th></tr>
<tr><td>1</td><td>2025-2026-1</td><td>CS101</td><td>数据结构</td><td>92</td><td></td><td>4.0</td><td>64</td><td>3.7</td><td></td><td>考试</td><td>正常</td><td>必修</td><td>理论</td><td></td></tr>
<tr><td>2</td><td>2024-2025-2</td><td>EN101</td><td>大学英语</td><td>优</td><td></td><td>3.0</td><td>48</td><td>4.5</td><td></td><td>考试</td><td>正常</td><td>必修</td><td>理论</td><td></td></tr>
</table>''';

  test('解析成绩', () {
    final grades = parseGrades(gradesHtml);
    expect(grades.length, 2);
    expect(grades[0].name, '数据结构');
    expect(grades[0].grade, '92');
    expect(grades[0].credit, '4.0');
    expect(grades[1].grade, '优');
  });

  const examHtml = '''
<table>
<tr><th>序号</th><th>考试类型</th><th>课程编号</th><th>课程名称</th><th>考试时间</th><th>考试地点</th><th>任课/负责老师</th><th>主监考</th><th>说明</th><th>座位号</th></tr>
<tr><td>1</td><td>期末考试</td><td>CS101</td><td>数据结构</td><td>2026-09-03 14:00</td><td>教十一302</td><td>王老师</td><td></td><td></td><td></td></tr>
</table>''';

  test('解析考试', () {
    final exams = parseExams(examHtml);
    expect(exams.length, 1);
    expect(exams[0].name, '数据结构');
    expect(exams[0].time, '2026-09-03 14:00');
    expect(exams[0].teacher, '王老师');
  });

  const classroomHtml = '''
<table>
<tr><th>星期</th><th>星期一</th></tr>
<tr><td>教十一302(100/50)</td><td></td></tr>
<tr><td>教十一305(80/40)</td><td></td></tr>
</table>''';

  test('解析空闲教室（去掉括号容量）', () {
    final rooms = parseClassrooms(classroomHtml);
    expect(rooms, ['教十一302', '教十一305']);
  });

  test('提取当前学期', () {
    expect(extractTerm('2025-2026学年第二学期 2025-2026-2'), '2025-2026-2');
    expect(extractTerm('2025-2026学年第二学期'), '2025-2026-2');
  });

  test('提取当前周', () {
    expect(extractWeek('<span>第16周</span>/26周'), 16);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd app && flutter test test/parser_test.dart`
Expected: FAIL（函数未定义）。

- [ ] **Step 3: 实现解析函数**（追加到 `api_client.dart`）

```dart
import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../models/course_cell.dart';
import '../models/exam.dart';
import '../models/grade.dart';
import '../models/timetable_row.dart';

const baseUrl = 'https://jwxt.ncepu.edu.cn';

List<CourseCell> _cellsOf(dynamic tr) {
  final cells = <CourseCell>[];
  for (final td in tr.querySelectorAll('th,td')) {
    var title = td.attributes['title'] ?? '';
    for (final el in td.querySelectorAll('[title]')) {
      final t = el.attributes['title'] ?? '';
      if (t.length > title.length) title = t;
    }
    if (title.contains('课程名称')) {
      final info = <String, String>{};
      for (final line in title.replaceAll('<br/>', '\n').replaceAll('<br>', '\n').split('\n')) {
        final i = line.indexOf('：');
        if (i > 0) info[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
      cells.add(CourseCell(
        name: info['课程名称'] ?? '',
        location: info['上课地点'] ?? '',
        attr: info['课程属性'] ?? '',
        credits: info['课程学分'] ?? '',
      ));
    } else {
      cells.add(CourseCell(name: td.text.trim()));
    }
  }
  return cells;
}

List<TimetableRow> parseTimetable(String html) {
  final doc = html_parser.parse(html);
  final tables = doc.querySelectorAll('table');
  if (tables.isEmpty) return [];
  final table = tables.reduce((a, b) => a.querySelectorAll('tr').length >= b.querySelectorAll('tr').length ? a : b);
  final rows = <TimetableRow>[];
  for (final tr in table.querySelectorAll('tr')) {
    final cells = _cellsOf(tr);
    if (cells.every((c) => c.isEmpty)) continue;
    if (cells.length >= 8) {
      rows.add(TimetableRow(section: cells[0].name, cells: cells.sublist(1, 8)));
    }
  }
  return rows;
}

String _col(List<String> row, int i) => i < row.length ? row[i].trim() : '';

List<Grade> parseGrades(String html) {
  final doc = html_parser.parse(html);
  final tables = doc.querySelectorAll('table');
  if (tables.isEmpty) return [];
  final rows = tables.first.querySelectorAll('tr');
  if (rows.isEmpty) return [];
  final headers = rows.first.querySelectorAll('th,td').map((e) => e.text.trim()).toList();
  int idx(List<String> names) {
    for (var i = 0; i < headers.length; i++) {
      if (names.contains(headers[i])) return i;
    }
    return -1;
  }
  final iTerm = idx(['开课学期']), iName = idx(['课程名称']), iGrade = idx(['成绩']),
        iAttr = idx(['课程属性', '课程性质', '课程类别']), iCredit = idx(['学分']);
  final out = <Grade>[];
  for (final tr in rows.skip(1)) {
    final cells = tr.querySelectorAll('th,td').map((e) => e.text.trim()).toList();
    if (cells.isEmpty || cells.every((c) => c.isEmpty)) continue;
    out.add(Grade(
      term: iTerm >= 0 ? _col(cells, iTerm) : '',
      name: iName >= 0 ? _col(cells, iName) : '',
      grade: iGrade >= 0 ? _col(cells, iGrade) : '',
      attr: iAttr >= 0 ? _col(cells, iAttr) : '',
      credit: iCredit >= 0 ? _col(cells, iCredit) : '',
    ));
  }
  return out;
}

List<Exam> parseExams(String html) {
  final doc = html_parser.parse(html);
  final tables = doc.querySelectorAll('table');
  if (tables.isEmpty) return [];
  final rows = tables.first.querySelectorAll('tr');
  if (rows.isEmpty) return [];
  final headers = rows.first.querySelectorAll('th,td').map((e) => e.text.trim()).toList();
  int idx(List<String> names) {
    for (var i = 0; i < headers.length; i++) {
      if (names.contains(headers[i])) return i;
    }
    return -1;
  }
  final iType = idx(['考试类型']), iName = idx(['课程名称']), iTime = idx(['考试时间']),
        iLoc = idx(['考试地点']), iTeacher = idx(['任课/负责老师', '任课老师', '教师']);
  final out = <Exam>[];
  for (final tr in rows.skip(1)) {
    final cells = tr.querySelectorAll('th,td').map((e) => e.text.trim()).toList();
    if (cells.isEmpty || cells.every((c) => c.isEmpty)) continue;
    out.add(Exam(
      type: iType >= 0 ? _col(cells, iType) : '',
      name: iName >= 0 ? _col(cells, iName) : '',
      time: iTime >= 0 ? _col(cells, iTime) : '',
      location: iLoc >= 0 ? _col(cells, iLoc) : '',
      teacher: iTeacher >= 0 ? _col(cells, iTeacher) : '',
    ));
  }
  return out;
}

List<String> parseClassrooms(String html) {
  final doc = html_parser.parse(html);
  final tables = doc.querySelectorAll('table');
  if (tables.isEmpty) return [];
  final rows = tables.first.querySelectorAll('tr');
  final out = <String>[];
  for (final tr in rows.skip(1)) {
    final cells = tr.querySelectorAll('th,td').map((e) => e.text.trim()).toList();
    if (cells.isEmpty) continue;
    var name = cells.first;
    name = name.replaceFirst(RegExp(r'\s*\(\d+\s*/\s*\d+\)\s*$'), '');
    if (name.isNotEmpty) out.add(name);
  }
  return out;
}

String extractTerm(String text) {
  final m = RegExp(r'(\d{4}-\d{4}-[123])').firstMatch(text);
  if (m != null) return m.group(1)!;
  final m2 = RegExp(r'(\d{4})-(\d{4})[^0-9]{0,8}?([一二三])').firstMatch(text);
  if (m2 != null) {
    const cn = {'一': '1', '二': '2', '三': '3'};
    return '${m2.group(1)}-${m2.group(2)}-${cn[m2.group(3)]}';
  }
  return '';
}

int? extractWeek(String text) {
  final m = RegExp(r'第\s*(\d{1,2})\s*周').firstMatch(text);
  if (m == null) return null;
  final w = int.parse(m.group(1)!);
  return w > 0 ? w : null;
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd app && flutter test test/parser_test.dart`
Expected: 全部 PASS。

- [ ] **Step 5: 实现网络请求部分**（追加到 `api_client.dart`）

```dart
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final Map<String, String> _cookies = {};

  void _saveCookies(http.Response r) {
    for (final c in r.headers['set-cookie']?.split(',') ?? const <String>[]) {
      final kv = c.trim().split(';').first;
      final i = kv.indexOf('=');
      if (i > 0) _cookies[kv.substring(0, i).trim()] = kv.substring(i + 1).trim();
    }
  }

  Map<String, String> _headers({String referer = '', bool xhr = false}) => {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/146.0.0.0 Mobile Safari/537.36',
    'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    if (referer.isNotEmpty) 'Referer': referer,
    if (xhr) 'X-Requested-With': 'XMLHttpRequest',
  };

  Future<bool> online() async {
    try {
      final r = await _client.get(Uri.parse('$baseUrl/'), headers: _headers()).timeout(const Duration(seconds: 4));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> login(String username, String password) async {
    final seedR = await _client.post(
      Uri.parse('$baseUrl/Logon.do?method=logon&flag=sess'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 12));
    _saveCookies(seedR);
    final seed = seedR.body.trim();
    if (seed.isEmpty) throw Exception('登录失败：加密种子为空，请确认已连接校园网');
    final encoded = encodeLogin(username, password, seed);
    await _client.post(
      Uri.parse('$baseUrl/Logon.do?method=logon'),
      headers: _headers(),
      body: {'userAccount': username, 'userPassword': password, 'RANDOMCODE': '', 'encoded': encoded},
    ).timeout(const Duration(seconds: 12));
    if (!await checkLogin()) throw Exception('账号或密码错误（也可能是加密算法不匹配）');
  }

  Future<bool> checkLogin() async {
    try {
      final r = await _client.get(Uri.parse('$baseUrl/jsxsd/framework/xsMain.jsp'), headers: _headers())
          .timeout(const Duration(seconds: 12));
      return !r.request!.url.path.contains('Logon.do') && (r.body.contains('xsMain') || r.body.contains('本周课表') || r.body.contains('退出'));
    } catch (_) {
      return false;
    }
  }

  Future<String> getCurrentTerm() async {
    for (final path in ['jsxsd/framework/xsMain_new.jsp', 'jsxsd/framework/xsMain.jsp', 'jsxsd/kbxx/jsjy_query', 'jsxsd/xsks/xsksap_query']) {
      try {
        final r = await _client.get(Uri.parse('$baseUrl/$path'), headers: _headers()).timeout(const Duration(seconds: 12));
        final t = extractTerm(r.body);
        if (t.isNotEmpty) return t;
      } catch (_) {}
    }
    return '';
  }

  Future<List<TimetableRow>> fetchTimetable(String date) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/jsxsd/framework/main_index_loadkb.jsp'),
      headers: _headers(referer: '$baseUrl/jsxsd/framework/xsMain_new.jsp', xhr: true),
      body: {'rq': date},
    ).timeout(const Duration(seconds: 12));
    return parseTimetable(r.body);
  }

  Future<List<Grade>> fetchGrades() async {
    final r = await _client.post(
      Uri.parse('$baseUrl/jsxsd/kscj/cjcx_list'),
      headers: _headers(referer: '$baseUrl/jsxsd/kscj/cjcx_query'),
      body: {'kksj': '', 'kcxz': '', 'kcmc': '', 'xsfs': 'all'},
    ).timeout(const Duration(seconds: 12));
    return parseGrades(r.body);
  }

  Future<List<Exam>> fetchExams() async {
    final term = await getCurrentTerm();
    final r = await _client.post(
      Uri.parse('$baseUrl/jsxsd/xsks/xsksap_list'),
      headers: _headers(referer: '$baseUrl/jsxsd/xsks/xsksap_query'),
      body: {'xqlbmc': '', 'xnxqid': term, 'kc': '', 'ksjs': '', 'jkls': ''},
    ).timeout(const Duration(seconds: 12));
    return parseExams(r.body);
  }

  Future<List<Building>> fetchBuildings(String campusId) async {
    final r = await _client.get(
      Uri.parse('$baseUrl/jsxsd/kbxx/jsjy_processAjax?xqid=$campusId&requestType=jxl'),
      headers: _headers(),
    ).timeout(const Duration(seconds: 12));
    final json = jsonDecode(r.body);
    final out = <Building>[];
    void walk(dynamic v) {
      if (v is List) {
        for (final item in v) {
          if (item is Map) {
            final id = (item['jxlid'] ?? item['id'] ?? item['dm'] ?? '').toString();
            final name = (item['jxlmc'] ?? item['name'] ?? item['mc'] ?? '').toString();
            if (id.isNotEmpty || name.isNotEmpty) out.add(Building(id: id, name: name));
          } else if (item is List && item.length >= 2) {
            out.add(Building(id: item[0].toString(), name: item[1].toString()));
          }
        }
      } else if (v is Map) {
        v.values.forEach(walk);
      }
    }
    walk(json);
    return out;
  }

  Future<List<String>> queryClassrooms({
    required String campus, required String building, required String term,
    required String weekFrom, required String weekTo,
    required String dayFrom, required String dayTo,
    required String jcFrom, required String jcTo,
  }) async {
    final r = await _client.post(
      Uri.parse('$baseUrl/jsxsd/kbxx/jsjy_query2'),
      headers: _headers(referer: '$baseUrl/jsxsd/kbxx/jsjy_query'),
      body: {
        'typewhere': 'jszq', 'xnxqh': term, 'xqbh': campus, 'jxqbh': '', 'jxlbh': building,
        'jsbh': '', 'bjfh': '=', 'rnrs': '', 'jszt': '8', 'zc': weekFrom, 'zc2': weekTo,
        'xq': dayFrom, 'xq2': dayTo, 'jc': jcFrom, 'jc2': jcTo, 'jsjylx': '',
      },
    ).timeout(const Duration(seconds: 12));
    return parseClassrooms(r.body);
  }
}
```

- [ ] **Step 6: 提交**

```bash
git add app/lib/services/api_client.dart app/test/parser_test.dart
git commit -m "feat: ApiClient 请求与解析（含 fixture 测试）"
```

---

## Task 5：缓存服务（TDD）

**Files:**
- Create: `app/lib/services/cache_service.dart`、`app/test/cache_test.dart`

**说明：** 键值表：`key TEXT PRIMARY KEY, value TEXT, updated_at REAL`。课表按周一日期为键 `timetable_<yyyy-MM-dd>`；成绩 `grades`；考试 `exams`；`last_daily_update` 存日期字符串；TTL：课表/考试 30 天，成绩不设限。

- [ ] **Step 1: 写失败测试** `app/test/cache_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/services/cache_service.dart';

void main() {
  test('保存并读取 JSON', () async {
    final c = CacheService.inMemory();
    await c.saveJson('grades', ['a', 1]);
    expect(await c.loadJson('grades'), ['a', 1]);
  });
  test('30 天课表缓存过期', () async {
    final c = CacheService.inMemory();
    await c.saveJson('timetable_2026-08-17', [1], updatedAt: DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch);
    expect(await c.loadJson('timetable_2026-08-17', ttlDays: 30), null);
  });
  test('成绩不设限', () async {
    final c = CacheService.inMemory();
    await c.saveJson('grades', [1], updatedAt: DateTime.now().subtract(const Duration(days: 200)).millisecondsSinceEpoch);
    expect(await c.loadJson('grades'), [1]);
  });
  test('清除全部', () async {
    final c = CacheService.inMemory();
    await c.saveJson('grades', [1]);
    await c.clearAll();
    expect(await c.loadJson('grades'), null);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd app && flutter test test/cache_test.dart`
Expected: FAIL（类未定义）。

- [ ] **Step 3: 实现**

`app/lib/services/cache_service.dart`:
```dart
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class CacheService {
  CacheService(this._db);
  final Database _db;

  static Future<CacheService> open(String dirPath) async {
    final db = await openDatabase(p.join(dirPath, 'cache.db'), version: 1,
        onCreate: (db, _) => db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT, updated_at REAL)'));
    return CacheService(db);
  }

  static Future<CacheService> inMemory() async {
    final db = await openDatabase(inMemoryDatabasePath, version: 1,
        onCreate: (db, _) => db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT, updated_at REAL)'));
    return CacheService(db);
  }

  Future<void> saveJson(String key, Object value, {int? updatedAt}) async {
    await _db.insert('kv', {
      'key': key,
      'value': jsonEncode(value),
      'updated_at': (updatedAt ?? DateTime.now().millisecondsSinceEpoch).toDouble(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<dynamic> loadJson(String key, {int ttlDays = 0}) async {
    final rows = await _db.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final updated = rows.first['updated_at'] as num;
    if (ttlDays > 0) {
      final ageDays = (DateTime.now().millisecondsSinceEpoch - updated.toInt()) / 86400000;
      if (ageDays > ttlDays) {
        await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
        return null;
      }
    }
    return jsonDecode(rows.first['value'] as String);
  }

  Future<int?> updatedAt(String key) async {
    final rows = await _db.query('kv', columns: ['updated_at'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : (rows.first['updated_at'] as num).toInt();
  }

  Future<void> clearAll() => _db.delete('kv');
  Future<void> close() => _db.close();
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd app && flutter test test/cache_test.dart`
Expected: 全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add app/lib/services/cache_service.dart app/test/cache_test.dart
git commit -m "feat: sqflite 缓存服务（TTL/清理）"
```

---

## Task 6：AuthService（安全存储与退出清理）

**Files:**
- Create: `app/lib/services/auth_service.dart`

- [ ] **Step 1: 实现**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cache_service.dart';

class AuthPrefs {
  static const kRemember = 'remember_password';
  static const kAutoLogin = 'auto_login';
}

class AuthService {
  AuthService({FlutterSecureStorage? storage, CacheService? cache})
      : _storage = storage ?? const FlutterSecureStorage(),
        _cache = cache;
  final FlutterSecureStorage _storage;
  final CacheService? _cache;

  Future<void> saveAccount(String username, String password) async {
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'password', value: password);
  }

  Future<({String username, String password})?> loadAccount() async {
    final u = await _storage.read(key: 'username');
    final p = await _storage.read(key: 'password');
    if (u == null || p == null) return null;
    return (username: u, password: p);
  }

  Future<void> clearAccount() async {
    await _storage.delete(key: 'username');
    await _storage.delete(key: 'password');
  }

  Future<void> setRemember(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(AuthPrefs.kRemember, v);
  }

  Future<bool> getRemember() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(AuthPrefs.kRemember) ?? false;
  }

  Future<void> setAutoLogin(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(AuthPrefs.kAutoLogin, v);
  }

  Future<bool> getAutoLogin() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(AuthPrefs.kAutoLogin) ?? false;
  }

  Future<void> logoutAll() async {
    await clearAccount();
    await setRemember(false);
    await setAutoLogin(false);
    await _cache?.clearAll();
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add app/lib/services/auth_service.dart
git commit -m "feat: 认证服务（安全存储/退出全清）"
```

---

## Task 7：Riverpod 状态层

**Files:**
- Create: `app/lib/providers/app_state.dart`、`auth_state.dart`、`data_state.dart`

- [ ] **Step 1: 实现 app_state（在线/启动分支）**

`app/lib/providers/app_state.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final onlineProvider = FutureProvider<bool>((ref) => ref.watch(apiClientProvider).online());
```

- [ ] **Step 2: 实现 auth_state**

`app/lib/providers/auth_state.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import 'app_state.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService(cache: ref.watch(cacheServiceProvider)));
final cacheServiceProvider = Provider<CacheService>((ref) => throw UnimplementedError('在 main.dart 覆盖注入'));

class AuthState {
  final bool loggedIn;
  final String username;
  final String? error;
  const AuthState({this.loggedIn = false, this.username = '', this.error});
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<bool> login(String username, String password, {required bool remember, required bool autoLogin}) async {
    final api = ref.read(apiClientProvider);
    final auth = ref.read(authServiceProvider);
    try {
      await api.login(username, password);
    } catch (e) {
      state = AuthState(error: _message(e));
      return false;
    }
    await auth.setRemember(remember);
    await auth.setAutoLogin(autoLogin && remember);
    if (remember) {
      await auth.saveAccount(username, password);
    } else {
      await auth.clearAccount();
    }
    state = AuthState(loggedIn: true, username: username);
    return true;
  }

  Future<bool> tryAutoLogin() async {
    final auth = ref.read(authServiceProvider);
    if (!await auth.getRemember() || !await auth.getAutoLogin()) return false;
    final acc = await auth.loadAccount();
    if (acc == null) return false;
    return login(acc.username, acc.password, remember: true, autoLogin: true);
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logoutAll();
    state = const AuthState();
  }

  String _message(Object e) {
    final s = e.toString();
    if (s.contains('TimeoutException')) return '连接超时，请检查网络后重试';
    if (s.contains('账号或密码')) return '账号或密码错误';
    if (s.contains('无法连接')) return s.replaceFirst('Exception: ', '');
    return '无法连接教务系统，请确认已连接校园网';
  }
}
```

- [ ] **Step 3: 实现 data_state（每日更新 + 手动刷新）**

`app/lib/providers/data_state.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exam.dart';
import '../models/grade.dart';
import '../models/timetable_row.dart';
import '../services/api_client.dart';
import '../services/cache_service.dart';
import 'app_state.dart';

final dataStateProvider = NotifierProvider<DataNotifier, DataState>(DataNotifier.new);

class DataState {
  final List<TimetableRow> timetable;
  final String timetableWeek; // 周一日期
  final List<Grade> grades;
  final List<Exam> exams;
  final bool loading;
  final String? notice;
  const DataState({
    this.timetable = const [], this.timetableWeek = '',
    this.grades = const [], this.exams = const [],
    this.loading = false, this.notice,
  });
  DataState copyWith({List<TimetableRow>? timetable, String? timetableWeek, List<Grade>? grades,
    List<Exam>? exams, bool? loading, String? notice}) => DataState(
    timetable: timetable ?? this.timetable, timetableWeek: timetableWeek ?? this.timetableWeek,
    grades: grades ?? this.grades, exams: exams ?? this.exams,
    loading: loading ?? this.loading, notice: notice ?? this.notice);
}

String _monday(DateTime d) {
  final w = d.weekday;
  final m = d.subtract(Duration(days: w - 1));
  return '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

class DataNotifier extends Notifier<DataState> {
  @override
  DataState build() => const DataState();

  Future<void> dailyRefreshIfNeeded() async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final last = await cache.loadJson('last_daily_update');
    if (last == today) return;
    state = state.copyWith(loading: true);
    final week = _monday(DateTime.now());
    try {
      final tt = await api.fetchTimetable(week);
      await cache.saveJson('timetable_$week', tt.map((r) => ({
        'section': r.section,
        'cells': r.cells.map((c) => c.toJson()).toList(),
      })).toList());
      state = state.copyWith(timetable: tt, timetableWeek: week);
    } catch (_) {}
    try {
      final g = await api.fetchGrades();
      await cache.saveJson('grades', g.map((e) => e.toJson()).toList());
      state = state.copyWith(grades: g);
    } catch (_) {}
    try {
      final e = await api.fetchExams();
      await cache.saveJson('exams', e.map((x) => x.toJson()).toList());
      state = state.copyWith(exams: e);
    } catch (_) {}
    await cache.saveJson('last_daily_update', today);
    state = state.copyWith(loading: false);
  }

  Future<void> loadTimetable(String monday) async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    final key = 'timetable_$monday';
    final cached = await cache.loadJson(key, ttlDays: 30);
    if (cached != null) {
      state = state.copyWith(
        timetable: (cached as List).map((r) => TimetableRow(
          section: r['section'] as String,
          cells: (r['cells'] as List).map((c) => CourseCellLike.fromJson(c)).toList(),
        )).toList(),
        timetableWeek: monday);
      return;
    }
    try {
      final tt = await api.fetchTimetable(monday);
      await cache.saveJson(key, tt.map((r) => ({
        'section': r.section,
        'cells': r.cells.map((c) => c.toJson()).toList(),
      })).toList());
      state = state.copyWith(timetable: tt, timetableWeek: monday);
    } catch (_) {
      state = state.copyWith(timetable: const [], timetableWeek: monday, notice: '该周暂无缓存，联网后可查看');
    }
  }

  Future<void> refreshGrades() async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    state = state.copyWith(loading: true);
    try {
      final g = await api.fetchGrades();
      await cache.saveJson('grades', g.map((e) => e.toJson()).toList());
      state = state.copyWith(grades: g, loading: false, notice: null);
    } catch (_) {
      state = state.copyWith(loading: false, notice: '获取失败，已显示缓存数据');
    }
  }

  Future<void> refreshExams() async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(apiClientProvider);
    state = state.copyWith(loading: true);
    try {
      final e = await api.fetchExams();
      await cache.saveJson('exams', e.map((x) => x.toJson()).toList());
      state = state.copyWith(exams: e, loading: false, notice: null);
    } catch (_) {
      state = state.copyWith(loading: false, notice: '获取失败，已显示缓存数据');
    }
  }

  Future<void> loadFromCache() async {
    final cache = ref.read(cacheServiceProvider);
    final week = _monday(DateTime.now());
    final tt = await cache.loadJson('timetable_$week', ttlDays: 30);
    final g = await cache.loadJson('grades');
    final e = await cache.loadJson('exams');
    state = state.copyWith(
      timetable: tt == null ? const [] : (tt as List).map((r) => TimetableRow(
        section: r['section'] as String,
        cells: (r['cells'] as List).map((c) => CourseCellLike.fromJson(c)).toList(),
      )).toList(),
      timetableWeek: week,
      grades: g == null ? const [] : (g as List).map((x) => Grade.fromJson(x)).toList(),
      exams: e == null ? const [] : (e as List).map((x) => Exam.fromJson(x)).toList(),
    );
  }
}

// 别名，避免与模型导入冲突
typedef CourseCellLike = CourseCellPlaceholder;
class CourseCellPlaceholder {
  static fromJson(Map<String, dynamic> j) => null;
}
```

> 注意：上面 `CourseCellLike` 是占位，执行时把占位块替换为对 `CourseCell.fromJson` 的直接调用，并正确导入 `../models/course_cell.dart`；`timetable_row.dart` 的序列化反序列化在 Task 8 的辅助函数中统一完成。

- [ ] **Step 4: 提交**

```bash
git add app/lib/providers
git commit -m "feat: Riverpod 状态层（在线/登录/数据与每日刷新）"
```

---

## Task 8：主题与共享组件

**Files:**
- Create: `app/lib/theme.dart`、`app/lib/widgets/capsule_nav.dart`、`top_bar.dart`、`offline_banner.dart`、`course_card.dart`、`grade_card.dart`、`exam_card.dart`、`room_card.dart`、`empty_view.dart`

- [ ] **Step 1: 实现主题** `app/lib/theme.dart`

```dart
import 'package:flutter/material.dart';

const kPrimary = Color(0xFF3B82F6);
const kPrimaryDark = Color(0xFF2563EB);
const kBgTop = Color(0xFFE8F1FF);
const kBgBottom = Color(0xFFF7F9FD);
const kTextMain = Color(0xFF1F2937);
const kTextMuted = Color(0xFF6B7280);

ThemeData buildTheme() {
  final base = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kPrimary), useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBgBottom,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
  );
}

// 课程 8 色（与桌面版一致）
const coursePalette = [
  (bg: Color(0xFFEFF6FF), border: Color(0xFFBFDBFE), name: Color(0xFF1E3A8A)),
  (bg: Color(0xFFF0FDF4), border: Color(0xFFBBF7D0), name: Color(0xFF14532D)),
  (bg: Color(0xFFFEF2F2), border: Color(0xFFFECACA), name: Color(0xFF7F1D1D)),
  (bg: Color(0xFFFFF7ED), border: Color(0xFFFED7AA), name: Color(0xFF7C2D12)),
  (bg: Color(0xFFF5F3FF), border: Color(0xFFDDD6FE), name: Color(0xFF4C1D95)),
  (bg: Color(0xFFFDF2F8), border: Color(0xFFFBCFE8), name: Color(0xFF831843)),
  (bg: Color(0xFFF0F9FF), border: Color(0xFFBAE6FD), name: Color(0xFF0C4A6E)),
  (bg: Color(0xFFFEFCE8), border: Color(0xFFFDE68A), name: Color(0xFF713F12)),
];

({Color bg, Color border, Color name}) courseColor(String name) {
  var h = 0;
  for (final c in name.codeUnits) { h = (h * 31 + c) & 0x7fffffff; }
  return coursePalette[h % coursePalette.length];
}
```

- [ ] **Step 2: 实现胶囊导航** `app/lib/widgets/capsule_nav.dart`

```dart
import 'package:flutter/material.dart';
import '../theme.dart';

class CapsuleNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const CapsuleNav({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const labels = ['课表', '成绩', '考试', '教室'];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFEAF1FF), Color(0xFFF4F7FF)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDBE6FB)),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(child: GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: i == index ? const LinearGradient(colors: [Color(0xFF7DB4FF), kPrimary]) : null,
                borderRadius: BorderRadius.circular(18),
                boxShadow: i == index ? [BoxShadow(color: kPrimary.withValues(alpha: .28), blurRadius: 6)] : null,
              ),
              child: Text(labels[i], textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: i == index ? FontWeight.w700 : FontWeight.w400,
                  color: i == index ? Colors.white : const Color(0xFF5B6B85))),
            ),
          )),
      ]),
    );
  }
}
```

- [ ] **Step 3: 实现顶部栏** `app/lib/widgets/top_bar.dart`

```dart
import 'package:flutter/material.dart';
import '../theme.dart';

class TopBar extends StatelessWidget {
  final String title;
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final String userName;
  final VoidCallback onUserTap;
  const TopBar({super.key, required this.title, this.showRefresh = false, this.onRefresh,
    required this.userName, required this.onUserTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800,
          foreground: Paint()..shader = const LinearGradient(colors: [Color(0xFF1E3A8A), kPrimary])
            .createShader(const Rect.fromLTWH(0, 0, 160, 24)),
        ))),
        if (showRefresh)
          IconButton(icon: const Icon(Icons.refresh, size: 20, color: kPrimary), onPressed: onRefresh),
        GestureDetector(
          onTap: onUserTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFD6E4FB)),
            ),
            child: Text(userName, style: const TextStyle(fontSize: 11, color: Color(0xFF1E3A8A), fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: 实现离线横幅** `app/lib/widgets/offline_banner.dart`

```dart
import 'package:flutter/material.dart';

class OfflineBanner extends StatelessWidget {
  final String text;
  const OfflineBanner({super.key, this.text = '离线模式 · 显示缓存数据'});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFED7AA)),
    ),
    child: Text(text, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11, color: Color(0xFF7C2D12))),
  );
}
```

- [ ] **Step 5: 实现课程卡 + 详情弹窗** `app/lib/widgets/course_card.dart`

```dart
import 'package:flutter/material.dart';
import '../models/course_cell.dart';
import '../theme.dart';

class CourseCard extends StatelessWidget {
  final CourseCell cell;
  const CourseCard({super.key, required this.cell});

  @override
  Widget build(BuildContext context) {
    final c = courseColor(cell.name);
    return GestureDetector(
      onTap: () => showDialog(context: context, builder: (_) => _CourseDetailDialog(cell: cell)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: c.bg, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(cell.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.name, height: 1.3)),
          const SizedBox(height: 3),
          Text(cell.location, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: Color(0xFF556677), height: 1.3)),
        ]),
      ),
    );
  }
}

class _CourseDetailDialog extends StatelessWidget {
  final CourseCell cell;
  const _CourseDetailDialog({required this.cell});
  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v) => Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF2F9)))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        Text(v, style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937), fontWeight: FontWeight.w600)),
      ]),
    );
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(cell.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)))),
            IconButton(icon: const Icon(Icons.close, size: 18, color: Color(0xFF6B7280)), onPressed: () => Navigator.pop(context)),
          ]),
          row('上课时间', cell.name.isNotEmpty ? '见课表节次' : ''),
          row('上课地点', cell.location),
          row('课程学分', cell.credits),
          row('课程属性', cell.attr),
        ]),
      ),
    );
  }
}
```

> 注意：`上课时间` 字段在课表接口 title 中可取（`上课时间：1-2节`），执行 Task 9 时给 `CourseCell` 增加 `time` 字段并解析，弹窗改显示该字段；此处先用占位文案，Task 9 一并修正。

- [ ] **Step 6: 实现成绩卡/考试卡/教室卡/空状态**

`app/lib/widgets/grade_card.dart`:
```dart
import 'package:flutter/material.dart';
import '../models/grade.dart';
import '../theme.dart';

class GradeCard extends StatelessWidget {
  final Grade grade;
  const GradeCard({super.key, required this.grade});
  @override
  Widget build(BuildContext context) {
    final badge = grade.grade;
    final bg = badge.contains('优') ? const Color(0xFFF0FDF4) : badge.contains('良') ? const Color(0xFFF0F9FF)
      : badge.contains('中') ? const Color(0xFFFFF7ED) : badge.contains('不及格') ? const Color(0xFFFEF2F2)
      : const Color(0xFFEFF6FF);
    final fg = badge.contains('优') ? const Color(0xFF14532D) : badge.contains('良') ? const Color(0xFF0C4A6E)
      : badge.contains('中') ? const Color(0xFF7C2D12) : badge.contains('不及格') ? const Color(0xFF7F1D1D)
      : const Color(0xFF1E3A8A);
    return Container(
      padding: const EdgeInsets.all(11),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEEF1F6))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(grade.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextMain)),
          const SizedBox(height: 3),
          Text('${grade.term} · ${grade.attr} · ${grade.credit}学分',
            style: const TextStyle(fontSize: 10, color: Color(0xFF9AA3AD))),
        ])),
        Container(width: 38, height: 38, alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(color: fg.withValues(alpha: .3))),
          child: Text(badge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg))),
      ]),
    );
  }
}
```

`app/lib/widgets/exam_card.dart`:
```dart
import 'package:flutter/material.dart';
import '../models/exam.dart';

class ExamCard extends StatelessWidget {
  final Exam exam;
  final bool done;
  const ExamCard({super.key, required this.exam, required this.done});
  @override
  Widget build(BuildContext context) {
    final dim = done;
    final text = dim ? const Color(0xFF9AA3AD) : const Color(0xFF1F2937);
    return Container(
      padding: const EdgeInsets.all(11),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: dim ? const Color(0xFFF5F5F6) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: dim ? const Color(0xFFECECEE) : const Color(0xFFEEF1F6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(exam.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: dim ? const Color(0xFFEEF1F6) : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: dim ? const Color(0xFFE2E6EE) : const Color(0xFFBBF7D0))),
            child: Text(dim ? '已考' : '未考', style: TextStyle(fontSize: 10, color: dim ? const Color(0xFF9AA3AD) : const Color(0xFF16A34A))),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${exam.type} · ${exam.time}', style: TextStyle(fontSize: 10, color: dim ? const Color(0xFF9AA3AD) : const Color(0xFF6B7280))),
        const SizedBox(height: 3),
        Text('${exam.location} · ${exam.teacher}', style: TextStyle(fontSize: 10, color: dim ? const Color(0xFF9AA3AD) : const Color(0xFF6B7280))),
      ]),
    );
  }
}
```

`app/lib/widgets/room_card.dart`:
```dart
import 'package:flutter/material.dart';

class RoomCard extends StatelessWidget {
  final String name;
  const RoomCard({super.key, required this.name});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFFF0F6FF), Color(0xFFEAF2FF)]),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFD6E4FB)),
    ),
    child: Column(children: [
      Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E3A8A))),
      const SizedBox(height: 4),
      const Text('● 空闲中', style: TextStyle(fontSize: 9, color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
    ]),
  );
}
```

`app/lib/widgets/empty_view.dart`:
```dart
import 'package:flutter/material.dart';

class EmptyView extends StatelessWidget {
  final String text;
  const EmptyView({super.key, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF9AA3AD)))),
  );
}
```

- [ ] **Step 7: 提交**

```bash
git add app/lib/theme.dart app/lib/widgets
git commit -m "feat: 主题与共享组件"
```

---

## Task 9：登录页

**Files:**
- Create: `app/lib/pages/login_page.dart`
- Modify: `app/lib/models/course_cell.dart`（增加 time 字段并同步解析，见 Step 2 说明）

- [ ] **Step 1: 实现登录页**

`app/lib/pages/login_page.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_state.dart';
import '../theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool remember = false;
  bool autoLogin = false;
  bool submitting = false;

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入学号和密码')));
      return;
    }
    setState(() => submitting = true);
    final ok = await ref.read(authStateProvider.notifier)
        .login(_user.text.trim(), _pass.text, remember: remember, autoLogin: autoLogin);
    if (!mounted) return;
    setState(() => submitting = false);
    final err = ref.read(authStateProvider).error;
    if (!ok && err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F1FF), Color(0xFFF7F9FD)]),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 30),
            Container(width: 64, height: 64, alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF7DB4FF), kPrimaryDark]),
                borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.local_florist, color: Colors.white, size: 34)),
            const SizedBox(height: 12),
            const Text('华电教务助手', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A))),
            const SizedBox(height: 4),
            const Text('请使用教务系统账号登录', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 26),
            _field(_user, '学号', obscure: false),
            const SizedBox(height: 12),
            _field(_pass, '密码', obscure: true),
            const SizedBox(height: 16),
            Row(children: [
              _check('记住账号密码', remember, (v) => setState(() => remember = v)),
              const SizedBox(width: 18),
              _check('自动登录', autoLogin && remember, (v) {
                if (!remember) return;
                setState(() => autoLogin = v);
              }),
            ]),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: kPrimary, padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(submitting ? '登录中…' : '登 录',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            const Text('需连接校园网或 VPN', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {required bool obscure}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E9F0))),
    child: TextField(controller: c, obscureText: obscure, decoration: InputDecoration(
      hintText: hint, border: InputBorder.none, hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9AA3AD))),
    ),
  );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 15, height: 15, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value ? kPrimary : Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: value ? kPrimary : const Color(0xFFCBD5E1))),
        child: value ? const Icon(Icons.check, size: 11, color: Colors.white) : null),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF374151))),
    ]),
  );
}
```

- [ ] **Step 2: CourseCell 增加 time 字段**

`app/lib/models/course_cell.dart` 增加 `final String time;`，构造函数默认 `this.time = ''`，`fromJson/toJson` 同步；`api_client.dart` 解析 title 时读取 `info['上课时间']`；`course_card.dart` 弹窗 `row('上课时间', cell.time)` 替换占位文案。

- [ ] **Step 3: 提交**

```bash
git add app/lib/pages/login_page.dart app/lib/models/course_cell.dart app/lib/widgets/course_card.dart app/lib/services/api_client.dart
git commit -m "feat: 登录页与课程详情时间字段"
```

---

## Task 10：课表页

**Files:**
- Create: `app/lib/pages/timetable_page.dart`

- [ ] **Step 1: 实现**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/timetable_row.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/course_card.dart';

class TimetablePage extends ConsumerWidget {
  const TimetablePage({super.key});

  static const sections = ['1-2', '3-4', '5-6', '7-8', '9-10'];
  static const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dataStateProvider);
    final week = state.timetableWeek;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left, color: kPrimary), onPressed: week.isEmpty ? null : () => _shift(ref, -1)),
          Expanded(child: Column(children: [
            Text('第 ${_weekOf(week)} 周', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextMain)),
            Text(week, style: const TextStyle(fontSize: 9, color: kTextMuted)),
          ])),
          IconButton(icon: const Icon(Icons.chevron_right, color: kPrimary), onPressed: week.isEmpty ? null : () => _shift(ref, 1)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          const SizedBox(width: 22),
          for (final d in weekdays) Expanded(child: Center(child: Text(d, style: TextStyle(
            fontSize: 10, color: d == '六' || d == '日' ? const Color(0xFFDC2626) : const Color(0xFF6B7280))))),
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(child: state.timetable.isEmpty
        ? const EmptyView(text: '暂无课表，联网后自动更新')
        : _grid(state.timetable)),
    ]);
  }

  void _shift(WidgetRef ref, int delta) {
    final cur = ref.read(dataStateProvider).timetableWeek;
    if (cur.isEmpty) return;
    final d = DateTime.parse(cur).add(Duration(days: 7 * delta));
    ref.read(dataStateProvider.notifier).loadTimetable(_mondayStr(d));
  }

  int _weekOf(String monday) => monday.isEmpty ? 0 : DateTime.parse(monday).difference(DateTime(2026, 2, 23)).inDays ~/ 7 + 1;

  String _mondayStr(DateTime d) {
    final m = d.subtract(Duration(days: d.weekday - 1));
    return '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
  }

  Widget _grid(List<TimetableRow> rows) {
    final bySection = {for (final r in rows) r.section: r};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(children: [
        for (final s in sections)
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 22, child: Center(child: Text(s, style: const TextStyle(fontSize: 8, color: Color(0xFF9AA3AD))))),
              const SizedBox(width: 2),
              for (var i = 0; i < 7; i++)
                Expanded(child: _cell(bySection[s], i)),
            ]),
          )),
      ]),
    );
  }

  Widget _cell(TimetableRow? row, int col) {
    final cell = row != null && col < row.cells.length ? row.cells[col] : null;
    if (cell == null || cell.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(left: 2), child: CourseCard(cell: cell));
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add app/lib/pages/timetable_page.dart
git commit -m "feat: 课表页（周视图/切周/课程卡）"
```

---

## Task 11：成绩页与考试页

**Files:**
- Create: `app/lib/pages/grades_page.dart`、`app/lib/pages/exams_page.dart`

- [ ] **Step 1: 实现成绩页**（含筛选、排序、平均学分绩）

`app/lib/pages/grades_page.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/grade.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/grade_card.dart';

int gradeScore(String g) {
  const map = {'优': 95, '良': 85, '中': 75, '及格': 65, '不及格': 55};
  final n = int.tryParse(g);
  return n ?? map[g.trim()] ?? 0;
}

double gpa(List<Grade> grades) {
  var credits = 0.0, scores = 0.0;
  for (final g in grades) {
    if (!g.attr.startsWith('必修')) continue;
    final cr = double.tryParse(g.credit) ?? 0;
    final sc = gradeScore(g.grade);
    credits += cr;
    scores += cr * sc;
  }
  return credits == 0 ? 0 : scores / credits;
}

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});
  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  String term = '全部学期';
  String query = '';
  String attr = '全部属性';
  String sort = '';
  bool desc = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dataStateProvider);
    final terms = <String>{'全部学期', for (final g in state.grades) g.term};
    final attrs = <String>{'全部属性', for (final g in state.grades) g.attr};
    var list = state.grades.where((g) =>
      (term == '全部学期' || g.term == term) &&
      (attr == '全部属性' || g.attr == attr) &&
      (query.isEmpty || g.name.contains(query))).toList();
    if (sort == '学期') list.sort((a, b) => desc ? b.term.compareTo(a.term) : a.term.compareTo(b.term));
    if (sort == '成绩') list.sort((a, b) => desc ? gradeScore(b.grade).compareTo(gradeScore(a.grade)) : gradeScore(a.grade).compareTo(gradeScore(b.grade)));
    if (sort == '学分') list.sort((a, b) => desc ? (double.tryParse(b.credit) ?? 0).compareTo(double.tryParse(a.credit) ?? 0) : (double.tryParse(a.credit) ?? 0).compareTo(double.tryParse(b.credit) ?? 0));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kPrimary, kPrimaryDark]),
            borderRadius: BorderRadius.circular(999)),
          child: Text('必修 ${state.grades.where((g) => g.attr.startsWith('必修')).length} 门 · 平均学分绩 ${gpa(state.grades).toStringAsFixed(6)}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Row(children: [
          _dropdown(term, terms.toList(), (v) => setState(() => term = v)),
          const SizedBox(width: 6),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E9F0))),
            child: TextField(onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(hintText: '搜索课程', border: InputBorder.none,
                hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9AA3AD)))),
          )),
          const SizedBox(width: 6),
          _dropdown(attr, attrs.toList(), (v) => setState(() => attr = v)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          for (final s in ['学期', '成绩', '学分'])
            GestureDetector(onTap: () => setState(() {
              if (sort == s) { desc = !desc; } else { sort = s; desc = false; }
            }), child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('$s ${sort == s ? (desc ? '▼' : '▲') : ''}',
                style: TextStyle(fontSize: 10, color: sort == s ? kPrimary : const Color(0xFF9AA3AD), fontWeight: sort == s ? FontWeight.w700 : FontWeight.w400)),
            )),
        ]),
      ),
      Expanded(child: list.isEmpty
        ? const EmptyView(text: '暂无成绩数据')
        : ListView.builder(padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            itemCount: list.length, itemBuilder: (_, i) => GradeCard(grade: list[i]))),
    ]);
  }

  Widget _dropdown(String value, List<String> items, ValueChanged<String> onChanged) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E9F0))),
    child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      value: value, isDense: true, items: [for (final it in items) DropdownMenuItem(value: it, child: Text(it, style: const TextStyle(fontSize: 11)))],
      onChanged: (v) => v != null ? onChanged(v) : null)),
  );
}
```

- [ ] **Step 2: 实现考试页**

`app/lib/pages/exams_page.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exam.dart';
import '../providers/data_state.dart';
import '../widgets/exam_card.dart';

class ExamsPage extends ConsumerWidget {
  const ExamsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(dataStateProvider).exams;
    if (exams.isEmpty) return const EmptyView(text: '暂无考试安排');
    final now = DateTime.now();
    return ListView.builder(padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      itemCount: exams.length,
      itemBuilder: (_, i) {
        final e = exams[i];
        final done = _parseTime(e.time)?.isBefore(now) ?? false;
        return ExamCard(exam: e, done: done);
      });
  }

  DateTime? _parseTime(String s) {
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!),
      int.parse(m.group(4)!), int.parse(m.group(5)!));
  }
}
```

- [ ] **Step 3: 提交**

```bash
git add app/lib/pages/grades_page.dart app/lib/pages/exams_page.dart
git commit -m "feat: 成绩页与考试页"
```

---

## Task 12：空闲教室页

**Files:**
- Create: `app/lib/pages/classrooms_page.dart`

- [ ] **Step 1: 实现**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/building.dart';
import '../providers/data_state.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/room_card.dart';

class ClassroomsPage extends ConsumerStatefulWidget {
  const ClassroomsPage({super.key});
  @override
  ConsumerState<ClassroomsPage> createState() => _ClassroomsPageState();
}

class _ClassroomsPageState extends ConsumerState<ClassroomsPage> {
  String campus = '2';
  String building = '';
  String day = '1';
  String jcFrom = '03';
  String jcTo = '04';
  List<Building> buildings = [];
  List<String> rooms = [];
  bool loading = false;
  String? error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadBuildings();
    _query();
  }

  Future<void> _loadBuildings() async {
    try {
      final b = await ref.read(apiClientProvider).fetchBuildings(campus);
      if (!mounted) return;
      setState(() { buildings = b; building = b.isNotEmpty ? b.first.id : ''; });
      _query();
    } catch (_) {}
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _query);
  }

  Future<void> _query() async {
    if (building.isEmpty) return;
    setState(() { loading = true; error = null; });
    try {
      final term = await ref.read(apiClientProvider).getCurrentTerm();
      final r = await ref.read(apiClientProvider).queryClassrooms(
        campus: campus, building: building, term: term,
        weekFrom: '1', weekTo: '20', dayFrom: day, dayTo: day,
        jcFrom: jcFrom, jcTo: jcTo);
      if (!mounted) return;
      setState(() { rooms = r; loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { rooms = []; loading = false; error = '离线或网络异常，空闲教室不可用'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E9F0)), boxShadow: const [BoxShadow(color: Color(0x0F3B82F6), blurRadius: 10)]),
        child: Row(children: [
          _cond('校区', ['1', '2'], ['一校区', '二校区'], campus, (v) { campus = v; _loadBuildings(); }),
          const SizedBox(width: 8),
          Expanded(child: _cond('教学楼', [for (final b in buildings) b.id], [for (final b in buildings) b.name], building, (v) { building = v; _onChanged(); })),
          const SizedBox(width: 8),
          _cond('星期', ['1', '2', '3', '4', '5', '6', '7'], ['一', '二', '三', '四', '五', '六', '日'], day, (v) { day = v; _onChanged(); }),
          const SizedBox(width: 8),
          _cond('节次', ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10'], ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'], jcFrom, (v) { jcFrom = v; _onChanged(); }),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('共 ${rooms.length} 间空闲教室', style: const TextStyle(fontSize: 10, color: kTextMuted)),
          Text('第16周 · 周${'一二三四五六日'[int.tryParse(day) != null && int.parse(day) >= 1 && int.parse(day) <= 7 ? int.parse(day) - 1 : 0]} · $jcFrom-$jcTo节',
            style: const TextStyle(fontSize: 9, color: Color(0xFF9AA3AD))),
        ]),
      ),
      Expanded(child: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
          ? EmptyView(text: error!)
          : rooms.isEmpty
            ? const EmptyView(text: '该条件下暂无空闲教室')
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 9, crossAxisSpacing: 9, childAspectRatio: 1.9),
                itemCount: rooms.length, itemBuilder: (_, i) => RoomCard(name: rooms[i]))),
    ]);
  }

  Widget _cond(String label, List<String> values, List<String> names, String current, ValueChanged<String> onChanged) {
    final idx = values.indexOf(current);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF9AA3AD))),
      const SizedBox(height: 2),
      DropdownButton<String>(
        value: current, isDense: true, underline: const SizedBox.shrink(),
        items: [for (var i = 0; i < values.length; i++) DropdownMenuItem(value: values[i], child: Text(names[i], style: const TextStyle(fontSize: 11)))],
        onChanged: (v) => v != null ? onChanged(v) : null),
    ]);
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add app/lib/pages/classrooms_page.dart
git commit -m "feat: 空闲教室页"
```

---

## Task 13：应用外壳与启动流程

**Files:**
- Create: `app/lib/main.dart`、`app/lib/app.dart`
- Modify: `app/lib/providers/auth_state.dart`（注入 CacheService 实现）

- [ ] **Step 1: main.dart（初始化缓存 + 安全存储）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'app.dart';
import 'providers/app_state.dart';
import 'providers/auth_state.dart';
import 'services/cache_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final cache = await CacheService.open(dir.path);
  runApp(ProviderScope(overrides: [
    cacheServiceProvider.overrideWithValue(cache),
  ], child: const HdjwApp()));
}
```

- [ ] **Step 2: app.dart（启动分支：在线自动登录 / 离线直进 / 登录页）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pages/classrooms_page.dart';
import 'pages/exams_page.dart';
import 'pages/grades_page.dart';
import 'pages/login_page.dart';
import 'pages/timetable_page.dart';
import 'providers/app_state.dart';
import 'providers/auth_state.dart';
import 'providers/data_state.dart';
import 'theme.dart';
import 'widgets/capsule_nav.dart';
import 'widgets/offline_banner.dart';
import 'widgets/top_bar.dart';

class HdjwApp extends StatelessWidget {
  const HdjwApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '华电教务助手',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const _Gate(),
  );
}

class _Gate extends ConsumerStatefulWidget {
  const _Gate();
  @override
  ConsumerState<_Gate> createState() => _GateState();
}

enum _Phase { boot, login, main }

class _GateState extends ConsumerState<_Gate> {
  _Phase phase = _Phase.boot;
  bool offline = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final online = await ref.read(onlineProvider.future).catchError((_) => false);
    final auth = ref.read(authStateProvider.notifier);
    if (online) {
      final ok = await auth.tryAutoLogin();
      if (ok) {
        await ref.read(dataStateProvider.notifier).dailyRefreshIfNeeded();
        if (mounted) setState(() => phase = _Phase.main);
      } else {
        if (mounted) setState(() => phase = _Phase.login);
      }
    } else {
      await ref.read(dataStateProvider.notifier).loadFromCache();
      final hasCache = ref.read(dataStateProvider).timetable.isNotEmpty ||
          ref.read(dataStateProvider).grades.isNotEmpty ||
          ref.read(dataStateProvider).exams.isNotEmpty;
      if (hasCache) {
        if (mounted) setState(() { phase = _Phase.main; offline = true; });
      } else {
        if (mounted) setState(() => phase = _Phase.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (phase) {
      _Phase.boot => const Scaffold(body: Center(child: CircularProgressIndicator())),
      _Phase.login => const LoginPage(),
      _Phase.main => _MainShell(offline: offline),
    };
  }
}

class _MainShell extends ConsumerStatefulWidget {
  final bool offline;
  const _MainShell({required this.offline});
  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int tab = 0;

  static const titles = ['我的课表', '课程成绩', '考试安排', '空闲教室'];

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('退出登录', style: TextStyle(fontSize: 16)),
      content: const Text('退出将清除全部本地数据（缓存、账号密码），确定吗？', style: TextStyle(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok == true) {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const TimetablePage(), const GradesPage(), const ExamsPage(), const ClassroomsPage()];
    final user = ref.watch(authStateProvider).username;
    final state = ref.watch(dataStateProvider);
    return Scaffold(
      body: SafeArea(child: Column(children: [
        TopBar(
          title: titles[tab],
          showRefresh: tab != 3,
          onRefresh: tab == 0 ? () => _refreshTimetable() : tab == 1 ? () => ref.read(dataStateProvider.notifier).refreshGrades() : () => ref.read(dataStateProvider.notifier).refreshExams(),
          userName: user.isEmpty ? '未登录' : '$user · 班级',
          onUserTap: () => showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: const Text('关于', style: TextStyle(fontSize: 14)), onTap: () { Navigator.pop(context); _about(); }),
            ListTile(title: const Text('退出登录', style: TextStyle(fontSize: 14, color: Colors.red)), onTap: _logout),
          ]))),
        ),
        if (widget.offline) const OfflineBanner(),
        if (state.notice != null) OfflineBanner(text: state.notice!),
        Expanded(child: IndexedStack(index: tab, children: pages)),
        CapsuleNav(index: tab, onTap: (i) => setState(() => tab = i)),
      ])),
    );
  }

  void _about() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('华电教务助手', style: TextStyle(fontSize: 17)),
      content: const Text('华北电力大学教务系统助手\n版本 1.0.0\n数据来自 jwxt.ncepu.edu.cn', style: TextStyle(fontSize: 12)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('好的'))],
    ));
  }

  void _refreshTimetable() {
    final week = ref.read(dataStateProvider).timetableWeek;
    if (week.isNotEmpty) ref.read(dataStateProvider.notifier).loadTimetable(week);
  }
}
```

- [ ] **Step 3: 注入 CacheService 到 auth_state**

把 `app/lib/providers/auth_state.dart` 的 `cacheServiceProvider` 从 `throw UnimplementedError` 改为由 `app_state.dart` 导出并在 main.dart override 后直接 `ref.watch`（即删除原占位行，保留 override 注入）。同时 `DataNotifier.loadTimetable` 等反序列化处把 Task 7 的 `CourseCellLike` 占位改为直接使用 `CourseCell.fromJson` 并删除占位类。

- [ ] **Step 4: 提交**

```bash
git add app/lib/main.dart app/lib/app.dart app/lib/providers
git commit -m "feat: 应用外壳与启动流程（在线/离线/登录分支）"
```

---

## Task 14：Widget 测试

**Files:**
- Create: `app/test/widget_test.dart`（覆盖默认模板测试）

- [ ] **Step 1: 写测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/theme.dart';

void main() {
  test('课程配色稳定', () {
    expect(courseColor('数据结构'), courseColor('数据结构'));
  });
  test('8 色调色板数量', () {
    expect(coursePalette.length, 8);
  });
}
```

- [ ] **Step 2: 运行**

Run: `cd app && flutter test`
Expected: 全部测试 PASS（含前序 Task 的所有测试）。

- [ ] **Step 3: 提交**

```bash
git add app/test/widget_test.dart
git commit -m "test: 主题与课程配色测试"
```

---

## Task 15：静态检查与真机/模拟器验证

**Files:**
- 无新增

- [ ] **Step 1: 静态分析**

Run: `cd app && flutter analyze`
Expected: No issues found（若有 warning 按提示修复）。

- [ ] **Step 2: 创建模拟器并运行**

Run（若无 AVD）:
```bash
flutter emulators --create --name hdjw_test
flutter emulators --launch hdjw_test
```
或在 Android Studio Device Manager 手动创建；启动后：
```bash
flutter run
```
Expected: App 启动显示登录页；在校园网环境下输入真实账号可登录并看到课表/成绩/考试；断网（关闭模拟器网络）重启 App 应进入离线模式显示缓存。

- [ ] **Step 3: 提交（如有修复）**

```bash
git add -A
git commit -m "fix: 联调修复"
```

---

## Task 16：打包 release APK

**Files:**
- Create: `app/android/key.properties`（本地生成，不入库）

- [ ] **Step 1: 生成签名密钥**

Run（按提示填写；密码与信息仅本地保存）:
```bash
keytool -genkey -v -keystore app/android/hdjw.jks -keyalg RSA -keysize 2048 -validity 10000 -alias hdjw
```

- [ ] **Step 2: 配置签名** `app/android/key.properties`

```properties
storePassword=<上一步设置的密码>
keyPassword=<上一步设置的密码>
keyAlias=hdjw
storeFile=hdjw.jks
```

- [ ] **Step 3: 修改 `app/android/app/build.gradle.kts`**：在 android 块前读入签名：

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```
在 `buildTypes` 中加 release 签名配置；`git add` 时用 `app/android/.gitignore` 排除 `key.properties` 与 `hdjw.jks`。

- [ ] **Step 4: 打包**

Run:
```bash
cd app
flutter build apk --release
```
Expected: `app/build/app/outputs/flutter-apk/app-release.apk` 生成。

- [ ] **Step 5: 提交**

```bash
git add app/android/app/build.gradle.kts app/android/.gitignore
git commit -m "build: 配置 release 签名与打包"
```

---

## 自查结论

- **Spec 覆盖：** 五功能页面（Task 9-12）、离线与缓存（Task 5/7/13）、每日更新与手动刷新（Task 7/13）、登录与安全（Task 3/6/9）、TTL（Task 5）、退出全清（Task 6/13）、视觉样式（Task 8-12 对应主题/组件）、测试（Task 3/4/5/14/15）、发布（Task 16）。无缺项。
- **占位符：** Task 7 的 `CourseCellLike` 与 Task 9 的“上课时间”占位均有显式修正步骤（Task 9 Step 2、Task 13 Step 3），其余无占位。
- **类型一致性：** 模型字段、Provider 方法名、缓存键（`timetable_<日期>`/`grades`/`exams`/`last_daily_update`）在任务间一致。
