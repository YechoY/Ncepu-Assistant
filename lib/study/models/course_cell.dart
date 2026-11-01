class CourseCell {
  final String name;
  final String location;
  final String attr;
  final String credits;
  final String time;
  const CourseCell({
    this.name = '',
    this.location = '',
    this.attr = '',
    this.credits = '',
    this.time = '',
  });
  bool get isEmpty => name.isEmpty && location.isEmpty && attr.isEmpty && credits.isEmpty;
  factory CourseCell.fromJson(Map<String, dynamic> j) => CourseCell(
    name: j['name'] as String? ?? '',
    location: j['location'] as String? ?? '',
    attr: j['attr'] as String? ?? '',
    credits: j['credits'] as String? ?? '',
    time: j['time'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'location': location,
    'attr': attr,
    'credits': credits,
    'time': time,
  };
}
