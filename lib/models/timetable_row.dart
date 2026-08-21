import 'course_cell.dart';

class TimetableRow {
  final String section; // 如 "1-2"
  final List<CourseCell> cells; // 7 列，周一..周日
  const TimetableRow({required this.section, required this.cells});
}
