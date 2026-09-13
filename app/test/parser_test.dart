import 'package:flutter_test/flutter_test.dart';
import 'package:hdjw_assistant/services/api_client.dart';

void main() {
  const kbHtml = '''
<html><body><table>
<tr><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
<tr><td>1-2</td>
  <td><p title="课程学分：4.0&lt;br/&gt;课程属性：必修&lt;br/&gt;课程名称：数据结构&lt;br/&gt;上课时间：1-2节&lt;br/&gt;上课地点：教十一302">数据结构..</p></td>
  <td></td><td></td><td></td><td></td><td></td><td></td></tr>
<tr><td>3-4</td><td></td>
  <td><p title="课程学分：5.5&lt;br/&gt;课程属性：必修&lt;br/&gt;课程名称：高等数学&lt;br/&gt;上课时间：3-4节&lt;br/&gt;上课地点：教九A105">高等数学..</p></td>
  <td></td><td></td><td></td><td></td><td></td><td></td></tr>
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
    expect(mon.time, '1-2节');
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

  // 真实服务器：没有考试时返回一行 <td colspan="9">未查询到数据</td> 占位行。
  const examEmptyHtml = '''
<table id="dataList">
<tr><th>序号</th><th>考试类型</th><th>课程编号</th><th>课程名称</th><th>考试时间</th><th>考试地点</th><th>任课/负责老师</th><th>主监考</th><th>说明</th><th>座位号</th></tr>
<tr><td colspan="9">未查询到数据</td></tr>
</table>''';

  test('解析考试：无数据占位行返回空列表', () {
    expect(parseExams(examEmptyHtml), isEmpty);
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

  // 学期全部课表（xskb_list.do）：id=kbtable，每格详版 div.kbcontent，
  // 单格可含多门课（用 ---- 分隔），字段在 <font title>。取自真实响应片段。
  const fullKbHtml = '''
<html><body>
<table id="kbtable">
<tr><th>&nbsp;</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
<tr>
  <th>第一大节&nbsp;</th>
  <td><div class="kbcontent1">x</div><div class="kbcontent" style="display:none;">20910311-3<br/>计算机网络<br/><font title='分组名称' color='red'>(课堂派GG2BPS)</font><br/><font title='老师'>李丽芬</font><br/><font title='周次(节次)'>1-12(周)</font><br/><font title='教室'>教十一楼C106</font><br/></div></td>
  <td><div class="kbcontent1">&nbsp;</div><div class="kbcontent" style="display:none;">&nbsp;</div></td>
  <td><div class="kbcontent">&nbsp;</div></td>
  <td><div class="kbcontent" style="display:none;">20910212-1<br/>软件工程B<br/><font title='老师'>陈晴</font><br/><font title='周次(节次)'>11-18(周)</font><br/><font title='教室'>教十一楼C102</font><br/>----------------------<br>20910252-1<br/>PYTHON程序设计<br/><font title='老师'>闫蕾</font><br/><font title='周次(节次)'>1-8(周)</font><br/><font title='教室'>教十楼A座603</font><br/></div></td>
  <td><div class="kbcontent">&nbsp;</div></td>
  <td><div class="kbcontent">&nbsp;</div></td>
  <td><div class="kbcontent">&nbsp;</div></td>
</tr>
<tr>
  <th>备注:</th><td colspan="7">无课表课程:</td>
</tr>
</table>
</body></html>''';

  test('解析学期全部课表', () {
    final list = parseFullTimetable(fullKbHtml);
    // 周一第一大节：计算机网络；周四第一大节：软件工程B + PYTHON程序设计
    expect(list.length, 3);
    final net = list.firstWhere((c) => c.name == '计算机网络');
    expect(net.day, 1);
    expect(net.section, 1);
    expect(net.location, '教十一楼C106');
    expect(net.teacher, '李丽芬');
    expect(net.weeks, '1-12(周)');
    expect(net.group, '(课堂派GG2BPS)');
    expect(net.code, '20910311-3');
    // 周四同一格两门课都要解出来
    final thu = list.where((c) => c.day == 4 && c.section == 1).toList();
    expect(thu.length, 2);
    expect(thu.map((c) => c.name), containsAll(['软件工程B', 'PYTHON程序设计']));
    final py = thu.firstWhere((c) => c.name == 'PYTHON程序设计');
    expect(py.location, '教十楼A座603');
    expect(py.weeks, '1-8(周)');
  });

  test('解析学期全部课表：非 kbtable 页面返回空', () {
    expect(parseFullTimetable('<html><body>no table</body></html>'), isEmpty);
  });
}
