/// 学期全部课表里的一门课（来自 xskb_list.do 的详版 div，字段比单周课表更全）。
/// 外层卡片只展示 [name] + [location]；点击后展示全部字段。
class FullCourse {
  final String name; // 课程名称
  final String location; // 上课地点/教室
  final String teacher; // 任课老师
  final String weeks; // 周次(节次)，如 "1-12(周)"
  final String group; // 分组名称，如 "(课堂派GG2BPS)"，可能为空
  final String code; // 课程编号，如 "20910311-3"
  final int day; // 星期几：1=周一 … 7=周日
  final int section; // 第几大节：1..5

  const FullCourse({
    this.name = '',
    this.location = '',
    this.teacher = '',
    this.weeks = '',
    this.group = '',
    this.code = '',
    this.day = 0,
    this.section = 0,
  });

  bool get isEmpty => name.isEmpty;

  factory FullCourse.fromJson(Map<String, dynamic> j) => FullCourse(
        name: j['name'] as String? ?? '',
        location: j['location'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        weeks: j['weeks'] as String? ?? '',
        group: j['group'] as String? ?? '',
        code: j['code'] as String? ?? '',
        day: (j['day'] as num?)?.toInt() ?? 0,
        section: (j['section'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location,
        'teacher': teacher,
        'weeks': weeks,
        'group': group,
        'code': code,
        'day': day,
        'section': section,
      };
}
