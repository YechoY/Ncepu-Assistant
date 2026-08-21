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
