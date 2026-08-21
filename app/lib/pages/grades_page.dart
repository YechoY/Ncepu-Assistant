import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grade.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/empty_view.dart';
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
    var list = state.grades
        .where((g) =>
            (term == '全部学期' || g.term == term) &&
            (attr == '全部属性' || g.attr == attr) &&
            (query.isEmpty || g.name.contains(query)))
        .toList();
    if (sort == '学期') {
      list.sort((a, b) => desc ? b.term.compareTo(a.term) : a.term.compareTo(b.term));
    }
    if (sort == '成绩') {
      list.sort((a, b) =>
          desc ? gradeScore(b.grade).compareTo(gradeScore(a.grade)) : gradeScore(a.grade).compareTo(gradeScore(b.grade)));
    }
    if (sort == '学分') {
      list.sort((a, b) => desc
          ? (double.tryParse(b.credit) ?? 0).compareTo(double.tryParse(a.credit) ?? 0)
          : (double.tryParse(a.credit) ?? 0).compareTo(double.tryParse(b.credit) ?? 0));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimary, kPrimaryDark]),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '必修 ${state.grades.where((g) => g.attr.startsWith('必修')).length} 门 · 平均学分绩 ${gpa(state.grades).toStringAsFixed(6)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Row(
            children: [
              _dropdown(term, terms.toList(), (v) => setState(() => term = v)),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E9F0)),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: '搜索课程',
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 11, color: Color(0xFF9AA3AD)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _dropdown(attr, attrs.toList(), (v) => setState(() => attr = v)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              for (final s in ['学期', '成绩', '学分'])
                GestureDetector(
                  onTap: () => setState(() {
                    if (sort == s) {
                      desc = !desc;
                    } else {
                      sort = s;
                      desc = false;
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '$s ${sort == s ? (desc ? '▼' : '▲') : ''}',
                      style: TextStyle(
                        fontSize: 10,
                        color: sort == s ? kPrimary : const Color(0xFF9AA3AD),
                        fontWeight: sort == s ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyView(text: '暂无成绩数据')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                  itemCount: list.length,
                  itemBuilder: (_, i) => GradeCard(grade: list[i]),
                ),
        ),
      ],
    );
  }

  Widget _dropdown(String value, List<String> items, ValueChanged<String> onChanged) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E9F0)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            items: [
              for (final it in items)
                DropdownMenuItem(value: it, child: Text(it, style: const TextStyle(fontSize: 11))),
            ],
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ),
      );
}
