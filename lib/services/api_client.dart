import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/building.dart';
import '../models/course_cell.dart';
import '../models/exam.dart';
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
    throw ArgumentError('无法解析登录种子: ${dataStr.length > 60 ? dataStr.substring(0, 60) : dataStr}');
  }
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

const baseUrl = 'https://jwxt.ncepu.edu.cn';

Element? _pickTable(Document doc) {
  final tables = doc.querySelectorAll('table');
  if (tables.isEmpty) return null;
  var best = tables.first;
  for (final t in tables.skip(1)) {
    if (t.querySelectorAll('tr').length > best.querySelectorAll('tr').length) best = t;
  }
  return best;
}

List<CourseCell> _cellsOf(Element tr) {
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
        time: info['上课时间'] ?? '',
      ));
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
    if (cells.length >= 8) {
      final first = cells[0].name.trim();
      if (first == '节次' || first.contains('星期') || first.contains('时间')) continue;
      rows.add(TimetableRow(section: cells[0].name, cells: cells.sublist(1, 8)));
    }
  }
  return rows;
}

String _col(List<String> row, int i) => i < row.length ? row[i].trim() : '';

List<Grade> parseGrades(String html) {
  final doc = html_parser.parse(html);
  final table = _pickTable(doc);
  if (table == null) return [];
  final rows = table.querySelectorAll('tr');
  if (rows.isEmpty) return [];
  final headers = rows.first.querySelectorAll('th,td').map((e) => e.text.trim()).toList();
  int idx(List<String> names) {
    for (var i = 0; i < headers.length; i++) {
      if (names.contains(headers[i])) return i;
    }
    return -1;
  }

  final iTerm = idx(['开课学期']);
  final iName = idx(['课程名称']);
  final iGrade = idx(['成绩']);
  final iAttr = idx(['课程属性', '课程性质', '课程类别']);
  final iCredit = idx(['学分']);
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
  final table = _pickTable(doc);
  if (table == null) return [];
  final rows = table.querySelectorAll('tr');
  if (rows.isEmpty) return [];
  final headers = rows.first.querySelectorAll('th,td').map((e) => e.text.trim()).toList();
  int idx(List<String> names) {
    for (var i = 0; i < headers.length; i++) {
      if (names.contains(headers[i])) return i;
    }
    return -1;
  }

  final iType = idx(['考试类型']);
  final iName = idx(['课程名称']);
  final iTime = idx(['考试时间']);
  final iLoc = idx(['考试地点']);
  final iTeacher = idx(['任课/负责老师', '任课老师', '教师']);
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
  final table = _pickTable(doc);
  if (table == null) return [];
  final rows = table.querySelectorAll('tr');
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
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/146.0.0.0 Mobile Safari/537.36',
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
    final seedR = await _client
        .post(
          Uri.parse('$baseUrl/Logon.do?method=logon&flag=sess'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 12));
    _saveCookies(seedR);
    final seed = seedR.body.trim();
    if (seed.isEmpty) throw Exception('登录失败：加密种子为空，请确认已连接校园网');
    final encoded = encodeLogin(username, password, seed);
    await _client
        .post(
          Uri.parse('$baseUrl/Logon.do?method=logon'),
          headers: _headers(),
          body: {
            'userAccount': username,
            'userPassword': password,
            'RANDOMCODE': '',
            'encoded': encoded,
          },
        )
        .timeout(const Duration(seconds: 12));
    if (!await checkLogin()) throw Exception('账号或密码错误（也可能是加密算法不匹配）');
  }

  Future<bool> checkLogin() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/jsxsd/framework/xsMain.jsp'), headers: _headers())
          .timeout(const Duration(seconds: 12));
      return !r.request!.url.path.contains('Logon.do') &&
          (r.body.contains('xsMain') || r.body.contains('本周课表') || r.body.contains('退出'));
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
        final t = extractTerm(r.body);
        if (t.isNotEmpty) return t;
      } catch (_) {}
    }
    return '';
  }

  Future<List<TimetableRow>> fetchTimetable(String date) async {
    final r = await _client
        .post(
          Uri.parse('$baseUrl/jsxsd/framework/main_index_loadkb.jsp'),
          headers: _headers(referer: '$baseUrl/jsxsd/framework/xsMain_new.jsp', xhr: true),
          body: {'rq': date},
        )
        .timeout(const Duration(seconds: 12));
    return parseTimetable(r.body);
  }

  Future<List<Grade>> fetchGrades() async {
    final r = await _client
        .post(
          Uri.parse('$baseUrl/jsxsd/kscj/cjcx_list'),
          headers: _headers(referer: '$baseUrl/jsxsd/kscj/cjcx_query'),
          body: {'kksj': '', 'kcxz': '', 'kcmc': '', 'xsfs': 'all'},
        )
        .timeout(const Duration(seconds: 12));
    return parseGrades(r.body);
  }

  Future<List<Exam>> fetchExams() async {
    final term = await getCurrentTerm();
    final r = await _client
        .post(
          Uri.parse('$baseUrl/jsxsd/xsks/xsksap_list'),
          headers: _headers(referer: '$baseUrl/jsxsd/xsks/xsksap_query'),
          body: {'xqlbmc': '', 'xnxqid': term, 'kc': '', 'ksjs': '', 'jkls': ''},
        )
        .timeout(const Duration(seconds: 12));
    return parseExams(r.body);
  }

  Future<List<Building>> fetchBuildings(String campusId) async {
    final r = await _client
        .get(
          Uri.parse('$baseUrl/jsxsd/kbxx/jsjy_processAjax?xqid=$campusId&requestType=jxl'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 12));
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
    return parseClassrooms(r.body);
  }
}
