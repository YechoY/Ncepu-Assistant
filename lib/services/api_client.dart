import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/building.dart';
import '../models/course_cell.dart';
import '../models/exam.dart';
import '../models/full_course.dart';
import '../models/grade.dart';
import '../models/timetable_row.dart';

String encodeLogin(String username, String password, String dataStr) {
  final String sep;
  if (dataStr.contains('#')) {
    sep = '#';
  } else if (dataStr.contains(';')) {
    sep = ';';
  } else if (dataStr.contains('|')) {
    sep = '|';
  } else {
    throw ArgumentError(
      '无法解析登录种子: ${dataStr.length > 60 ? dataStr.substring(0, 60) : dataStr}',
    );
  }
  final parts = dataStr.split(sep);
  var scode = parts[0];
  final sxh = parts[1];
  final code = '$username%%%$password';
  final buf = StringBuffer();
  for (var i = 0; i < code.length; i++) {
    final n = i < sxh.length && int.tryParse(sxh[i]) != null
        ? int.parse(sxh[i])
        : 0;
    buf.write(code[i]);
    // 与桌面版 Python _make_encoded 完全一致：scode[:n] 越界时自动取剩余全部（Python 切片行为），
    // 不能加 scode.length >= n 的判断，否则会漏掉字符导致 encoded 和服务器期望不一致。
    final take = n > scode.length ? scode.length : n;
    if (take > 0) {
      buf.write(scode.substring(0, take));
      scode = scode.substring(take);
    }
  }
  return buf.toString();
}

const baseUrl = 'https://jwxt.ncepu.edu.cn';

String _decode(http.Response r) {
  final ct = (r.headers['content-type'] ?? '').toLowerCase();
  if (ct.contains('gbk') || ct.contains('gb2312') || ct.contains('gb18030')) {
    return gbk.decode(r.bodyBytes);
  }
  return utf8.decode(r.bodyBytes, allowMalformed: true);
}

Element? _pickTable(Document doc) {
  final tables = doc.querySelectorAll('table');
  if (tables.isEmpty) return null;
  var best = tables.first;
  for (final t in tables.skip(1)) {
    if (t.querySelectorAll('tr').length > best.querySelectorAll('tr').length)
      best = t;
  }
  return best;
}

List<CourseCell> _cellsOf(Element tr) {
  final cells = <CourseCell>[];
  for (final td in tr.querySelectorAll('th,td')) {
    // 对齐桌面版 _cell_info：取 td 自身或子元素中最长的 title（完整课程信息所在）
    var title = td.attributes['title'] ?? '';
    for (final el in td.querySelectorAll('[title]')) {
      final t = el.attributes['title'] ?? '';
      if (t.length > title.length) title = t;
    }
    if (title.contains('课程名称')) {
      final info = <String, String>{};
      for (final line
          in title
              .replaceAll('<br/>', '\n')
              .replaceAll('<br>', '\n')
              .split('\n')) {
        final i = line.indexOf('：');
        if (i > 0)
          info[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
      cells.add(
        CourseCell(
          name: info['课程名称'] ?? '',
          location: info['上课地点'] ?? '',
          attr: info['课程属性'] ?? '',
          credits: info['课程学分'] ?? '',
          time: info['上课时间'] ?? '',
        ),
      );
    } else {
      cells.add(CourseCell(name: td.text.trim()));
    }
  }
  return cells;
}

List<TimetableRow> parseTimetable(String html) {
  final doc = html_parser.parse(html);
  final table = _pickTable(doc);
  if (table == null) return [];
  final rows = <TimetableRow>[];
  for (final tr in table.querySelectorAll('tr')) {
    final cells = _cellsOf(tr);
    if (cells.every((c) => c.isEmpty)) continue;
    // 对齐桌面版：返回所有有内容的行，不做 length>=8 的严格过滤，避免合并单元格丢行。
    // 第 1 格为节次/表头标识，其余作为周一..周日；若不足 8 格则把已有格子放进 cells。
    final first = cells.isNotEmpty ? cells[0].name.trim() : '';

    // 只过滤真正的表头行（周/节次 | 星期一...），不误伤"第一大节"这种正常节次标识
    if (first == '周/节次' ||
        first.contains('星期') ||
        first.contains('时间') ||
        first.contains('节次')) {
      continue;
    }
    final body = cells.length >= 2 ? cells.sublist(1) : const <CourseCell>[];
    rows.add(TimetableRow(section: first, cells: body));
  }
  return rows;
}

String _col(List<String> row, int i) => i < row.length ? row[i].trim() : '';

/// 清洗「备注」行文本：压平空白、按分号拆成条目、去空与「无」。
String _cleanRemark(String raw) {
  var t = raw.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty || t == '无') return '';
  return t
      .split(';')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .join('\n');
}

/// 解析「学期全部课表」页面（xskb_list.do 返回的 HTML）。
/// 结构与单周课表完全不同：
/// - 表格 id="kbtable"，7 列=周一..周日，5 行=第一..五大节，最后一行"备注"单独取出；
///   备注行列出本学期不占格子的课程（课程设计/分散进行等）；
/// - 每格里有两个 div：kbcontent1(简版) 与 kbcontent(详版，display:none)；
///   详版含老师、分组名称等更多信息，这里解析详版；
/// - 一格可能有多门课，用一行"----------"分隔（跨周占同一格不同周次）；
/// - 每门课字段：第 1 段是课程编号，第 2 段是课程名，其余靠 `<font title='...'>` 标注
///   （周次(节次)/教室/老师/分组名称）。空格子内容为 `&nbsp;`。
({List<FullCourse> courses, String remark}) parseFullTimetable(String html) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('#kbtable');
  if (table == null) return (courses: const [], remark: '');
  final result = <FullCourse>[];
  var remark = '';
  final trs = table.querySelectorAll('tr');
  var section = 0; // 第几大节，随含有效节次表头的行递增
  for (final tr in trs) {
    // 行首的 <th> 文本决定这是哪一大节；"备注"行单独提取展示
    final th = tr.querySelector('th');
    final thText = th?.text.trim() ?? '';
    if (thText.contains('备注')) {
      remark = _cleanRemark(
        tr.querySelectorAll('td').map((e) => e.text).join(' '),
      );
      continue;
    }
    if (!thText.contains('大节')) continue; // 跳过表头行（星期一.. 那行没有"大节"）
    section++;
    final tds = tr.querySelectorAll('td');
    for (var day = 0; day < tds.length && day < 7; day++) {
      // 优先取详版 div.kbcontent；取不到再退回简版 div.kbcontent1
      final detail =
          tds[day].querySelector('.kbcontent') ??
          tds[day].querySelector('.kbcontent1');
      if (detail == null) continue;
      // 用 innerHtml 保留 <br> 与 <font title> 结构，便于按段解析
      final inner = detail.innerHtml;
      for (final course in _parseFullCell(inner, day + 1, section)) {
        result.add(course);
      }
    }
  }
  return (courses: result, remark: remark);
}

/// 解析一个格子的 innerHtml，可能含多门课（用一行 "----" 分隔）。
List<FullCourse> _parseFullCell(String innerHtml, int day, int section) {
  final trimmed = innerHtml.replaceAll('&nbsp;', ' ').trim();
  if (trimmed.isEmpty) return const [];
  // 按“至少 4 个连字符”的分隔行拆分多门课（HTML 里是 ----------------------）
  final blocks = trimmed.split(RegExp(r'-{4,}'));
  final courses = <FullCourse>[];
  for (final block in blocks) {
    final c = _parseFullCourseBlock(block, day, section);
    if (c != null) courses.add(c);
  }
  return courses;
}

/// 解析单门课的 HTML 片段。
FullCourse? _parseFullCourseBlock(String blockHtml, int day, int section) {
  // 先抽出所有 <font title='X'>Y</font>，按 title 归类。
  // 注意：html 包重新序列化 innerHtml 时属性会变成双引号，故正则同时兼容单/双引号。
  final fontRe = RegExp(
    '''<font[^>]*title=(?:'([^']*)'|"([^"]*)")[^>]*>(.*?)</font>''',
    dotAll: true,
  );
  var weeks = '';
  var location = '';
  var teacher = '';
  var group = '';
  final fonts = fontRe.allMatches(blockHtml);
  for (final m in fonts) {
    final title = m.group(1) ?? m.group(2) ?? '';
    final value = _stripTags(m.group(3) ?? '');
    if (title.contains('周次')) {
      weeks = value;
    } else if (title.contains('教室')) {
      location = value;
    } else if (title.contains('老师')) {
      teacher = value;
    } else if (title.contains('分组')) {
      group = value;
    }
  }
  // 去掉所有 <font>...</font> 段，剩下的按 <br> 切开：第1段=课程编号，第2段=课程名
  final withoutFonts = blockHtml.replaceAll(fontRe, '');
  final segs = withoutFonts
      .split(RegExp(r'<br\s*/?>', caseSensitive: false))
      .map(_stripTags)
      .where((s) => s.trim().isNotEmpty)
      .toList();
  var code = '';
  var name = '';
  if (segs.isNotEmpty) code = segs[0].trim();
  if (segs.length >= 2) name = segs[1].trim();
  // 课程编号形如 20910311-3；若第1段不像编号，则可能整段就是课程名
  if (name.isEmpty && code.isNotEmpty && !RegExp(r'^\d').hasMatch(code)) {
    name = code;
    code = '';
  }
  if (name.isEmpty) return null; // 空格子
  return FullCourse(
    name: name,
    location: location,
    teacher: teacher,
    weeks: weeks,
    group: group,
    code: code,
    day: day,
    section: section,
  );
}

/// 去掉一段 HTML 里的所有标签，返回纯文本。
String _stripTags(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 强智教务系统在「没有数据」时，列表表格会返回一行占位：
///   <tr><td colspan="N">未查询到数据</td></tr>
/// 这里统一识别这种占位行（单格且文本是"未查询到数据/无数据/暂无数据"），
/// 供各列表解析跳过，避免生成一条字段全空的脏记录（表现为空白卡片/空行）。
bool _isNoDataRow(List<String> cells) {
  if (cells.length != 1) return false;
  final t = cells.first.trim();
  return t.contains('未查询到数据') || t.contains('无数据') || t.contains('暂无数据');
}

List<Grade> parseGrades(String html) {
  final doc = html_parser.parse(html);
  final table = _pickTable(doc);
  if (table == null) return [];
  final rows = table.querySelectorAll('tr');
  if (rows.isEmpty) return [];
  final headers = rows.first
      .querySelectorAll('th,td')
      .map((e) => e.text.trim())
      .toList();
  // 精确匹配：表头文字必须等于候选名之一。
  int idx(List<String> names) {
    for (var i = 0; i < headers.length; i++) {
      if (names.contains(headers[i])) return i;
    }
    return -1;
  }

  // 包含匹配：只要表头「含有」任一候选关键字即命中。
  // 用于成绩列——教务系统有时把表头写成「成绩111」这类带后缀的形式，
  // 精确匹配会漏掉，改用 contains 更稳。
  // exclude：排除关键字。成绩表里「成绩标识」列也含「成绩」二字，
  // 万一它排在「成绩」列前面会被误命中，用 exclude 把这类列跳过。
  int idxContains(List<String> keywords, {List<String> exclude = const []}) {
    for (var i = 0; i < headers.length; i++) {
      if (exclude.any((e) => headers[i].contains(e))) continue;
      for (final k in keywords) {
        if (headers[i].contains(k)) return i;
      }
    }
    return -1;
  }

  final iTerm = idx(['开课学期']);
  final iName = idx(['课程名称']);
  final iGrade = idxContains(['成绩'], exclude: ['成绩标识']);
  final iAttr = idx(['课程属性', '课程性质', '课程类别']);
  final iCredit = idx(['学分']);
  final out = <Grade>[];
  for (final tr in rows.skip(1)) {
    final cells = tr
        .querySelectorAll('th,td')
        .map((e) => e.text.trim())
        .toList();
    if (cells.isEmpty || cells.every((c) => c.isEmpty)) continue;
    if (_isNoDataRow(cells)) continue; // 「未查询到数据」占位行 → 跳过
    out.add(
      Grade(
        term: iTerm >= 0 ? _col(cells, iTerm) : '',
        name: iName >= 0 ? _col(cells, iName) : '',
        grade: iGrade >= 0 ? _col(cells, iGrade) : '',
        attr: iAttr >= 0 ? _col(cells, iAttr) : '',
        credit: iCredit >= 0 ? _col(cells, iCredit) : '',
      ),
    );
  }
  return out;
}

List<Exam> parseExams(String html) {
  final doc = html_parser.parse(html);
  final table = _pickTable(doc);
  if (table == null) return [];
  final rows = table.querySelectorAll('tr');
  if (rows.isEmpty) return [];
  final headers = rows.first
      .querySelectorAll('th,td')
      .map((e) => e.text.trim())
      .toList();
  int idx(List<String> names) {
    for (var i = 0; i < headers.length; i++) {
      if (names.contains(headers[i])) return i;
    }
    return -1;
  }

  // 表头容错匹配：精确没命中时，退化为「包含」匹配（应对带空格/前后缀的表头）。
  int idxLoose(List<String> keywords) {
    final exact = idx(keywords);
    if (exact >= 0) return exact;
    for (var i = 0; i < headers.length; i++) {
      for (final k in keywords) {
        if (headers[i].contains(k)) return i;
      }
    }
    return -1;
  }

  final iType = idxLoose(['考试类型', '考试性质']);
  final iName = idxLoose(['课程名称', '课程']);
  final iTime = idxLoose(['考试时间', '时间']);
  final iLoc = idxLoose(['考试地点', '地点', '考场']);
  final iTeacher = idxLoose(['任课/负责老师', '任课老师', '教师']);
  final out = <Exam>[];
  for (final tr in rows.skip(1)) {
    final cells = tr
        .querySelectorAll('th,td')
        .map((e) => e.text.trim())
        .toList();
    if (cells.isEmpty || cells.every((c) => c.isEmpty)) continue;
    if (_isNoDataRow(cells)) continue; // 「未查询到数据」占位行 → 跳过
    final exam = Exam(
      type: iType >= 0 ? _col(cells, iType) : '',
      name: iName >= 0 ? _col(cells, iName) : '',
      time: iTime >= 0 ? _col(cells, iTime) : '',
      location: iLoc >= 0 ? _col(cells, iLoc) : '',
      teacher: iTeacher >= 0 ? _col(cells, iTeacher) : '',
    );
    // 跳过没有任何有效内容的行：避免出现「课程名/时间/地点全空」的空白卡片
    // （通常是表头没匹配上或分隔行导致）。
    if (exam.name.isEmpty && exam.time.isEmpty && exam.location.isEmpty) {
      continue;
    }
    out.add(exam);
  }
  return out;
}

List<String> parseClassrooms(String html) {
  final doc = html_parser.parse(html);
  final table = _pickTable(doc);
  if (table == null) return [];
  final rows = table.querySelectorAll('tr');
  final out = <String>[];
  for (final tr in rows.skip(1)) {
    final cells = tr
        .querySelectorAll('th,td')
        .map((e) => e.text.trim())
        .toList();
    if (cells.isEmpty) continue;
    if (_isNoDataRow(cells)) continue; // 「未查询到数据」占位行 → 跳过
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

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final Map<String, String> _cookies = {};

  void _saveCookies(http.Response r) {
    // set-cookie 可能有多条，每条之间由逗号分隔，但 cookie 值/Expires 本身也可能含逗号，
    // 简单 split(',') 会误拆。这里改用逐条解析，取第一条 '=' 之前的名字作为 key。
    final cookies = r.headers['set-cookie'] == null
        ? const <String>[]
        : _splitSetCookie(r.headers['set-cookie']!);
    for (final c in cookies) {
      final kv = c.trim().split(';').first;
      final i = kv.indexOf('=');
      if (i > 0) {
        final name = kv.substring(0, i).trim();
        final value = kv.substring(i + 1).trim();
        if (name.toLowerCase() == 'expires' ||
            name.toLowerCase() == 'domain' ||
            name.toLowerCase() == 'path' ||
            name.toLowerCase() == 'max-age' ||
            name.toLowerCase() == 'samesite' ||
            name.toLowerCase() == 'secure' ||
            name.toLowerCase() == 'httponly') {
          continue;
        }
        if (value.isNotEmpty) _cookies[name] = value;
      }
    }
  }

  // 解析可能含逗号的 set-cookie 头：只有在逗号后紧跟「name=」或「name="」时才算新的 cookie 开头，
  // 否则视为上一个 cookie 值的一部分（例如 Expires=...GMT, ... 中的逗号）。
  List<String> _splitSetCookie(String header) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuote = false;
    var lastSliceStart = 0;
    final parts = <String>[];
    for (var i = 0; i < header.length; i++) {
      final ch = header[i];
      if (ch == '"') inQuote = !inQuote;
      if (ch == ',' && !inQuote) {
        parts.add(header.substring(lastSliceStart, i));
        lastSliceStart = i + 1;
      }
    }
    parts.add(header.substring(lastSliceStart));
    for (final p in parts) {
      // 每个 slice 应该以 cookie 名开头（name=value），否则它是上一个 slice 的尾巴，拼回去
      if (RegExp(r'^\s*[^=;,=\s]+=').hasMatch(p) ||
          RegExp(r'^\s*[^=;,=\s]+="').hasMatch(p)) {
        out.add(p);
      } else if (out.isNotEmpty) {
        out[out.length - 1] = '${out.last},$p';
      } else {
        buf.write(p);
      }
    }
    if (buf.isNotEmpty && out.isNotEmpty)
      out[out.length - 1] = '${out.last},$buf';
    return out;
  }

  Map<String, String> _headers({String referer = '', bool xhr = false}) => {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/146.0.0.0 Mobile Safari/537.36',
    // 桌面版 requests.Session post(data=...) 会自动带这个头；Flutter http 传 Map body 不会，
    // 教务系统可能因缺少表单 Content-Type 而拒绝登录 POST，返回"出错页面"。
    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    if (referer.isNotEmpty) 'Referer': referer,
    if (xhr) 'X-Requested-With': 'XMLHttpRequest',
  };

  Future<bool> online() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/'), headers: _headers())
          .timeout(const Duration(seconds: 4));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> login(String username, String password) async {
    // 先清空旧会话 Cookie：退出登录/会话过期后旧 JSESSIONID 可能仍被服务端认可，
    // 若带着旧 Cookie 做 checkLogin，即使密码错误也会被误判为登录成功。
    _cookies.clear();
    // 第一步：取加密种子
    final seedR = await _client
        .post(
          Uri.parse('$baseUrl/Logon.do?method=logon&flag=sess'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 12));
    _saveCookies(seedR);
    final seed = _decode(seedR).trim();
    if (seed.isEmpty) throw Exception('登录失败：加密种子为空，请确认已连接校园网');
    final encoded = encodeLogin(username, password, seed);

    // 第二步：正式登录。对齐桌面版 requests.Session 的行为：
    // 首次 POST Logon.do（返回 302），随后用 GET 自动跟随重定向链（LoginToXk 等），
    // 每步都收集 set-cookie，保证 JSESSIONID 会话真正建立。
    final formBody =
        'userAccount=${Uri.encodeQueryComponent(username)}'
        '&userPassword=${Uri.encodeQueryComponent(password)}'
        '&RANDOMCODE='
        '&encoded=${Uri.encodeQueryComponent(encoded)}';
    var currentUri = Uri.parse('$baseUrl/Logon.do?method=logon');
    var isPost = true;
    http.Response? loginR;
    for (var i = 0; i < 8; i++) {
      final req = http.Request(isPost ? 'POST' : 'GET', currentUri)
        ..headers.addAll(_headers(referer: '$baseUrl/Logon.do?method=logon'))
        ..followRedirects = false;
      if (isPost) req.body = formBody;
      final resp = await _client.send(req).timeout(const Duration(seconds: 12));
      loginR = await http.Response.fromStream(resp);
      _saveCookies(loginR);
      // 302 -> 用 GET 跟进 Location（requests 默认跟随行为），并继续带上 cookies
      if (loginR.statusCode == 301 ||
          loginR.statusCode == 302 ||
          loginR.statusCode == 303 ||
          loginR.statusCode == 307 ||
          loginR.statusCode == 308) {
        final loc = loginR.headers['location'];
        if (loc == null || loc.isEmpty) break;
        currentUri = Uri.parse(loc);
        isPost = false; // 重定向后转 GET 跟随
        continue;
      }
      // 非重定向即结束
      break;
    }

    if (!await checkLogin()) throw Exception('账号或密码错误（也可能是加密算法不匹配）');
  }

  /// 清空本地会话 Cookie（退出登录时调用）。
  /// 注意：App 内的「退出」并未通知教务系统销毁服务端会话，旧 JSESSIONID
  /// 在服务端超时前仍然有效；必须把它从本地清掉，否则后续请求会顶着旧身份。
  void clearSession() => _cookies.clear();

  Future<bool> checkLogin() async {
    try {
      final r = await _client
          .get(
            Uri.parse('$baseUrl/jsxsd/framework/xsMain.jsp'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 12));
      final url = r.request?.url.toString() ?? '';
      final body = _decode(r);

      // 被重定向回登录页则未登录
      if (url.contains('Logon.do')) return false;
      // 出错页面：服务端返回的「出错页面」说明会话无效/未登录，直接判定失败
      if (body.contains('出错页面') ||
          body.contains('出错') && body.contains('flag')) {
        return false;
      }
      // 真正登入成功的标志：登录成功后的主页特征（必须有真实内容，不能是错误页）
      final markers = [
        '本周课表',
        '退出',
        '欢迎',
        'xsMain_new',
        'jsxsd/framework/xsMain.jsp',
      ];
      for (final m in markers) {
        if (body.contains(m)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getCurrentTerm() async {
    for (final path in [
      'jsxsd/framework/xsMain_new.jsp',
      'jsxsd/framework/xsMain.jsp',
      'jsxsd/kbxx/jsjy_query',
      'jsxsd/xsks/xsksap_query',
    ]) {
      try {
        final r = await _client
            .get(Uri.parse('$baseUrl/$path'), headers: _headers())
            .timeout(const Duration(seconds: 12));
        final t = extractTerm(_decode(r));
        if (t.isNotEmpty) return t;
      } catch (_) {}
    }
    return '';
  }

  Future<int?> fetchCurrentWeek() async {
    for (final path in [
      'jsxsd/framework/xsMain_new.jsp',
      'jsxsd/framework/xsMain.jsp',
    ]) {
      try {
        final r = await _client
            .get(Uri.parse('$baseUrl/$path'), headers: _headers())
            .timeout(const Duration(seconds: 12));
        final body = _decode(r);
        var w = extractWeek(body);
        // 优先用 html 解析 li_showWeek 元素（对齐桌面版 get_semester_info，更可靠）
        if (w == null) {
          try {
            final doc = html_parser.parse(body);
            final nodes = doc.querySelectorAll('[id="li_showWeek"]');
            if (nodes.isNotEmpty) {
              final text = nodes.first.text;
              w = extractWeek(text);
            }
          } catch (_) {}
        }

        if (w != null) return w;
      } catch (_) {}
    }
    return null;
  }

  /// 返回 (当前周, 本学期总周数)，取自 xsMain_new.jsp 的 li_showWeek（第X周/共Y周）。
  Future<({int current, int? total})?> fetchSemesterInfo() async {
    for (final path in [
      'jsxsd/framework/xsMain_new.jsp',
      'jsxsd/framework/xsMain.jsp',
    ]) {
      try {
        final r = await _client
            .get(Uri.parse('$baseUrl/$path'), headers: _headers())
            .timeout(const Duration(seconds: 12));
        final body = _decode(r);
        final doc = html_parser.parse(body);
        final nodes = doc.querySelectorAll('[id="li_showWeek"]');
        if (nodes.isNotEmpty) {
          final text = nodes.first.text;
          final nums = RegExp(r'(\d{1,3})\s*周')
              .allMatches(text)
              .map((m) => int.parse(m.group(1)!))
              .where((n) => n > 0)
              .toList();
          if (nums.isNotEmpty) {
            final current = nums[0];
            final total = nums.length > 1 ? nums[1] : null;

            return (current: current, total: total);
          }
        }
        // 兜底：整页正则
        final all = RegExp(r'(\d{1,3})\s*周')
            .allMatches(body)
            .map((m) => int.parse(m.group(1)!))
            .where((n) => n > 0)
            .toList();
        if (all.isNotEmpty) {
          final current = all.first;
          final total = all.length > 1 ? all[1] : null;
          return (current: current, total: total);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<({String name, String sid, String className})> fetchUserInfo() async {
    for (final path in [
      'jsxsd/framework/xsMain_new.jsp',
      'jsxsd/framework/xsMain.jsp',
    ]) {
      try {
        final r = await _client
            .get(Uri.parse('$baseUrl/$path'), headers: _headers())
            .timeout(const Duration(seconds: 12));
        final text = _decode(r)
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ');
        var name = '';
        final mWelcome = RegExp(
          r'欢迎[^0-9A-Za-z]{0,6}?([\u4e00-\u9fa5]{2,4})\s*(?:同学|，|,)',
        ).firstMatch(text);
        if (mWelcome != null) {
          name = mWelcome.group(1)!;
        } else {
          final mName = RegExp(r'(?:姓名|学生姓名)[:：\s]*([\u4e00-\u9fa5]{2,4})')
              .firstMatch(text);
          if (mName != null) name = mName.group(1)!;
        }
        final mSid = RegExp(r'(?:学生编号|学号)[:：\s]*([0-9A-Za-z]{4,})')
            .firstMatch(text);
        final mClass = RegExp(
          r'(?:班级名称|班级)[:：\s]*([\u4e00-\u9fa5A-Za-z0-9\-]{2,20})',
        ).firstMatch(text);
        return (
          name: name,
          sid: mSid?.group(1) ?? '',
          className: mClass?.group(1) ?? '',
        );
      } catch (_) {}
    }
    return (name: '', sid: '', className: '');
  }

  Future<List<TimetableRow>> fetchTimetable(String date) async {
    final r = await _client
        .post(
          Uri.parse('$baseUrl/jsxsd/framework/main_index_loadkb.jsp'),
          headers: _headers(
            referer: '$baseUrl/jsxsd/framework/xsMain_new.jsp',
            xhr: true,
          ),
          body: {'rq': date},
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(r);

    return parseTimetable(body);
  }

  /// 拉取「学期全部课表」。GET xskb_list.do；[term] 为学年学期(xnxq01id)，
  /// 传空则由服务器返回当前学期。返回解析后的整学期课程列表与表尾「备注」。
  Future<({List<FullCourse> courses, String remark})> fetchFullTimetable({
    String term = '',
  }) async {
    final uri = term.isEmpty
        ? Uri.parse('$baseUrl/jsxsd/xskb/xskb_list.do')
        : Uri.parse('$baseUrl/jsxsd/xskb/xskb_list.do?xnxq01id=$term');
    final r = await _client
        .get(
          uri,
          headers: _headers(referer: '$baseUrl/jsxsd/framework/xsMain.jsp'),
        )
        .timeout(const Duration(seconds: 12));
    return parseFullTimetable(_decode(r));
  }

  Future<List<Grade>> fetchGrades() async {
    final r = await _client
        .post(
          Uri.parse('$baseUrl/jsxsd/kscj/cjcx_list'),
          headers: _headers(referer: '$baseUrl/jsxsd/kscj/cjcx_query'),
          body: {'kksj': '', 'kcxz': '', 'kcmc': '', 'xsfs': 'all'},
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(r);

    return parseGrades(body);
  }

  /// 查询考试安排。
  /// [term] 为指定学期（xnxqid，如 2025-2026-2）；传空则查当前学期（服务器默认）。
  Future<List<Exam>> fetchExams({String? term}) async {
    final xnxqid = term ?? await getCurrentTerm();

    final r = await _client
        .post(
          Uri.parse('$baseUrl/jsxsd/xsks/xsksap_list'),
          headers: _headers(referer: '$baseUrl/jsxsd/xsks/xsksap_query'),
          body: {
            'xqlbmc': '',
            'xnxqid': xnxqid,
            'kc': '',
            'ksjs': '',
            'jkls': '',
          },
        )
        .timeout(const Duration(seconds: 12));
    final body = _decode(r);

    return parseExams(body);
  }

  Future<List<Building>> fetchBuildings(String campusId) async {
    final r = await _client
        .get(
          Uri.parse(
            '$baseUrl/jsxsd/kbxx/jsjy_processAjax?xqid=$campusId&requestType=jxl',
          ),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 12));
    // 教务接口常返回 GBK 编码，必须走 _decode 处理编码，否则 jsonDecode 乱码/失败导致教学楼下拉空白
    final text = _decode(r);

    dynamic json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      return <Building>[];
    }
    final out = <Building>[];

    // 遍历并提取 {id, name} 对，兼容数组/对象/嵌套结构，键名大小写不敏感
    void extractPair(dynamic obj) {
      if (obj is Map) {
        final lower = <String, dynamic>{};
        for (final e in obj.entries) {
          lower['${e.key}'.toLowerCase()] = e.value;
        }
        final idVal =
            lower['jxlid'] ??
            lower['id'] ??
            lower['dm'] ??
            lower['bh'] ??
            lower['jxl_id'] ??
            lower['value'] ??
            lower['code'] ??
            lower['jsid'];
        final nameVal =
            lower['jxlmc'] ??
            lower['dmmc'] ??
            lower['name'] ??
            lower['mc'] ??
            lower['jxl_name'] ??
            lower['jxlname'] ??
            lower['text'] ??
            lower['label'] ??
            lower['jsmc'];
        if (idVal != null || nameVal != null) {
          final id = (idVal ?? '').toString();
          final name = (nameVal ?? id).toString();
          if (id.isNotEmpty || name.isNotEmpty)
            out.add(Building(id: id, name: name));
        }
      } else if (obj is List) {
        for (final item in obj) {
          if (item is List && item.length >= 2) {
            final id = item[0].toString();
            final name = item[1].toString();
            if (id.isNotEmpty || name.isNotEmpty)
              out.add(Building(id: id, name: name));
          } else {
            extractPair(item);
          }
        }
      }
    }

    extractPair(json);

    // 兜底：若顶层是 "楼号->楼名" 的映射（所有 key 数字、所有 value 字符串），直接按映射提取
    if (out.isEmpty && json is Map && json.isNotEmpty) {
      final allNum = json.keys.every(
        (k) => '$k'.isNotEmpty && RegExp(r'^\d+$').hasMatch('$k'),
      );
      final allStr = json.values.every((v) => v is String && v.isNotEmpty);
      if (allNum && allStr) {
        json.forEach((k, v) {
          final id = '$k';
          final name = '$v';
          if (id.isNotEmpty && name.isNotEmpty)
            out.add(Building(id: id, name: name));
        });
      }
    }

    // 二校区按文档固定顺序排序（踩坑17：教十一楼→教九楼B座→教十楼B座→教八楼B座→其他）
    if (campusId == '2') {
      const priority = ['教十一楼', '教九楼B座', '教十楼B座', '教八楼B座'];
      final ordered = <Building>[];
      for (final p in priority) {
        for (final b in out) {
          if (b.name == p && !ordered.contains(b)) ordered.add(b);
        }
      }
      for (final b in out) {
        if (!ordered.contains(b)) ordered.add(b);
      }
      out
        ..clear()
        ..addAll(ordered);
    }

    return out;
  }

  Future<List<String>> queryClassrooms({
    required String campus,
    required String building,
    required String term,
    required String weekFrom,
    required String weekTo,
    required String dayFrom,
    required String dayTo,
    required String jcFrom,
    required String jcTo,
  }) async {
    final r = await _client
        .post(
          Uri.parse('$baseUrl/jsxsd/kbxx/jsjy_query2'),
          headers: _headers(referer: '$baseUrl/jsxsd/kbxx/jsjy_query'),
          body: {
            'typewhere': 'jszq',
            'xnxqh': term,
            'xqbh': campus,
            'jxqbh': '',
            'jxlbh': building,
            'jsbh': '',
            'bjfh': '=',
            'rnrs': '',
            'jszt': '8',
            'zc': weekFrom,
            'zc2': weekTo,
            'xq': dayFrom,
            'xq2': dayTo,
            'jc': jcFrom,
            'jc2': jcTo,
            'jsjylx': '',
          },
        )
        .timeout(const Duration(seconds: 12));
    return parseClassrooms(_decode(r));
  }
}
