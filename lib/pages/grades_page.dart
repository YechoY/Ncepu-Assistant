import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grade.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/empty_view.dart';
import '../widgets/glass_dropdown.dart';
import '../widgets/grade_card.dart';
import '../widgets/gradient_text.dart';
import '../widgets/reveal.dart';

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

  // —— 勾选计算模式：开启后学分绩按手动勾选的必修课实时计算；退出即清空 ——
  bool selectMode = false;

  /// 勾选的课程（Grade 未重写 ==，按对象同一性判等；列表元素即数据源对象，可安全用 Set）。
  final Set<Grade> selected = {};

  /// 学期快捷勾选：勾选某学期 = 一次性选中/移出该学期全部必修课。
  Set<String> checkedTerms = {};

  /// 某学期的全部必修课。
  Iterable<Grade> _mustOfTerm(String t, List<Grade> grades) =>
      grades.where((g) => g.term == t && g.attr.startsWith('必修'));

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dataStateProvider);
    final terms = <String>{'全部学期', for (final g in state.grades) g.term};
    final attrs = <String>{'全部属性', for (final g in state.grades) g.attr};
    // 勾选模式：学期下拉变成选课工具（不再过滤显示），但勾了哪些学期就让列表
    // 只显示哪些学期，方便核对；搜索框/属性筛选仍只管显示——被筛出视野的
    // 已勾课程依旧计入计算。
    final termNames = terms.where((t) => t != '全部学期').toList();
    var list = state.grades.where((g) {
      if (selectMode) {
        if (checkedTerms.isNotEmpty && !checkedTerms.contains(g.term)) {
          return false;
        }
      } else if (term != '全部学期' && g.term != term) {
        return false;
      }
      if (attr != '全部属性' && g.attr != attr) return false;
      if (query.isNotEmpty && !g.name.contains(query)) return false;
      return true;
    }).toList();
    if (sort == '学期') {
      list.sort(
        (a, b) => desc ? b.term.compareTo(a.term) : a.term.compareTo(b.term),
      );
    }
    if (sort == '成绩') {
      list.sort(
        (a, b) => desc
            ? gradeScore(b.grade).compareTo(gradeScore(a.grade))
            : gradeScore(a.grade).compareTo(gradeScore(b.grade)),
      );
    }
    if (sort == '学分') {
      list.sort(
        (a, b) => desc
            ? (double.tryParse(b.credit) ?? 0).compareTo(
                double.tryParse(a.credit) ?? 0,
              )
            : (double.tryParse(a.credit) ?? 0).compareTo(
                double.tryParse(b.credit) ?? 0,
              ),
      );
    }

    // 学期「部分选中」：该学期必修只勾了一部分 → 学期勾选框显示 "-"。
    final partialTerms = <String>{};
    for (final t in termNames) {
      final must = _mustOfTerm(t, state.grades).toList();
      if (must.isEmpty) continue;
      final n = must.where(selected.contains).length;
      if (n > 0 && n < must.length) partialTerms.add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: GradientText(
                      text: selectMode
                          ? '已选 ${selected.length} 门 · 必修平均学分绩 ${gpa(selected.toList()).toStringAsFixed(4)}'
                          : '必修 ${state.grades.where((g) => g.attr.startsWith('必修')).length} 门 · 平均学分绩 ${gpa(state.grades).toStringAsFixed(4)}',
                      fontSize: 12,
                    ),
                  ),
                ),
                _selectToggle(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Row(
            children: [
              selectMode
                  // 勾选模式：学期下拉变多选工具，勾选 = 快速选中该学期全部必修。
                  ? GlassDropdown(
                      value: checkedTerms.isEmpty
                          ? '选择学期'
                          : checkedTerms.join(' · '),
                      items: termNames,
                      multi: true,
                      multiValues: checkedTerms,
                      multiPartial: partialTerms,
                      // 面板传来新的学期集合：与当前差量比对，
                      // 新勾的学期 → 必修全加入；取消的学期 → 必修全移出。
                      onMultiChanged: (v) => setState(() {
                        for (final t in v.difference(checkedTerms)) {
                          selected.addAll(_mustOfTerm(t, state.grades));
                        }
                        for (final t in checkedTerms.difference(v)) {
                          selected.removeAll(_mustOfTerm(t, state.grades));
                        }
                        checkedTerms = v;
                      }),
                    )
                  : _dropdown(
                      term,
                      terms.toList(),
                      (v) => setState(() => term = v),
                    ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: '搜索课程',
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 11, color: kTextMuted),
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
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      if (sort == s) {
                        desc = !desc;
                      } else {
                        sort = s;
                        desc = false;
                      }
                    }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: sort == s
                            ? kPrimaryContainer
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: sort == s
                              ? kPrimarySoft
                              : Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$s ${sort == s ? (desc ? '▼' : '▲') : ''}',
                          style: TextStyle(
                            fontSize: 10,
                            color: sort == s ? kPrimary : kTextMuted,
                            fontWeight: sort == s
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
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
                  // 入场淡入做缓冲：卡片本身是静态磨砂（无实时模糊），滑动流畅。
                  itemBuilder: (_, i) => Reveal(
                    duration: const Duration(milliseconds: 320),
                    offset: const Offset(0, 14),
                    minScale: 0.98,
                    child: GradeCard(
                      grade: list[i],
                      // 只有必修可勾（学分绩只统计必修）；非必修卡片无勾选框。
                      selectable: selectMode && list[i].attr.startsWith('必修'),
                      selected: selectMode && selected.contains(list[i]),
                      onToggle: () => setState(() {
                        selected.contains(list[i])
                            ? selected.remove(list[i])
                            : selected.add(list[i]);
                      }),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _dropdown(
    String value,
    List<String> items,
    ValueChanged<String> onChanged,
  ) => GlassDropdown(value: value, items: items, onChanged: onChanged);

  /// 胶囊行右侧的勾选模式开关：开启 = 学分绩改按勾选课程实时计算；
  /// 关闭即清空全部勾选（学期勾选 + 课程勾选），回到默认「全部必修」口径。
  Widget _selectToggle() {
    return GestureDetector(
      onTap: () => setState(() {
        selectMode = !selectMode;
        if (!selectMode) {
          selected.clear();
          checkedTerms = {};
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: kSpring,
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: selectMode ? kPrimary : Colors.white.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: selectMode ? kPrimary : Colors.white.withValues(alpha: 0.65),
          ),
        ),
        child: Icon(
          Icons.checklist_rounded,
          size: 17,
          color: selectMode ? Colors.white : kTextMuted,
        ),
      ),
    );
  }
}
