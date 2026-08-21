import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course_cell.dart';
import '../models/exam.dart';
import '../models/grade.dart';
import '../models/timetable_row.dart';
import 'app_state.dart';

final dataStateProvider = NotifierProvider<DataNotifier, DataState>(DataNotifier.new);

class DataState {
  final List<TimetableRow> timetable;
  final String timetableWeek; // 周一日期 yyyy-MM-dd
  final List<Grade> grades;
  final List<Exam> exams;
  final bool loading;
  final String? notice;
  const DataState({
    this.timetable = const [],
    this.timetableWeek = '',
    this.grades = const [],
    this.exams = const [],
    this.loading = false,
    this.notice,
  });
  DataState copyWith({
    List<TimetableRow>? timetable,
    String? timetableWeek,
    List<Grade>? grades,
    List<Exam>? exams,
    bool? loading,
    String? notice,
  }) =>
      DataState(
        timetable: timetable ?? this.timetable,
        timetableWeek: timetableWeek ?? this.timetableWeek,
        grades: grades ?? this.grades,
        exams: exams ?? this.exams,
        loading: loading ?? this.loading,
        notice: notice ?? this.notice,
      );
}

String mondayOf(DateTime d) {
  final m = d.subtract(Duration(days: d.weekday - 1));
  return '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> ttToJson(List<TimetableRow> rows) => rows
    .map((r) => {
          'section': r.section,
          'cells': r.cells.map((c) => c.toJson()).toList(),
        })
    .toList();

List<TimetableRow> ttFromJson(dynamic v) => (v as List)
    .map((r) => TimetableRow(
          section: r['section'] as String,
          cells: (r['cells'] as List)
              .map((c) => CourseCell.fromJson(c as Map<String, dynamic>))
              .toList(),
        ))
    .toList();

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
    final week = mondayOf(DateTime.now());
    try {
      final tt = await api.fetchTimetable(week);
      await cache.saveJson('timetable_$week', ttToJson(tt));
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
      state = state.copyWith(timetable: ttFromJson(cached), timetableWeek: monday);
      return;
    }
    try {
      final tt = await api.fetchTimetable(monday);
      await cache.saveJson(key, ttToJson(tt));
      state = state.copyWith(timetable: tt, timetableWeek: monday, notice: null);
    } catch (_) {
      state = state.copyWith(
        timetable: const [],
        timetableWeek: monday,
        notice: '该周暂无缓存，联网后可查看',
      );
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
    final week = mondayOf(DateTime.now());
    final tt = await cache.loadJson('timetable_$week', ttlDays: 30);
    final g = await cache.loadJson('grades');
    final e = await cache.loadJson('exams');
    state = state.copyWith(
      timetable: tt == null ? const [] : ttFromJson(tt),
      timetableWeek: week,
      grades: g == null
          ? const []
          : (g as List).map((x) => Grade.fromJson(x as Map<String, dynamic>)).toList(),
      exams: e == null
          ? const []
          : (e as List).map((x) => Exam.fromJson(x as Map<String, dynamic>)).toList(),
    );
  }
}
