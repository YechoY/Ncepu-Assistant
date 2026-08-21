class Exam {
  final String type, name, time, location, teacher;
  const Exam({
    required this.type,
    required this.name,
    required this.time,
    required this.location,
    required this.teacher,
  });
  factory Exam.fromJson(Map<String, dynamic> j) => Exam(
    type: j['type'] as String? ?? '',
    name: j['name'] as String? ?? '',
    time: j['time'] as String? ?? '',
    location: j['location'] as String? ?? '',
    teacher: j['teacher'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    'time': time,
    'location': location,
    'teacher': teacher,
  };
}
