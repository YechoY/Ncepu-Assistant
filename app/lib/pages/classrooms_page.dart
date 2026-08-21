import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/building.dart';
import '../providers/app_state.dart';
import '../theme.dart';
import '../widgets/empty_view.dart';
import '../widgets/room_card.dart';

class ClassroomsPage extends ConsumerStatefulWidget {
  const ClassroomsPage({super.key});
  @override
  ConsumerState<ClassroomsPage> createState() => _ClassroomsPageState();
}

class _ClassroomsPageState extends ConsumerState<ClassroomsPage> {
  static const _sectionPairs = ['01-02', '03-04', '05-06', '07-08', '09-10'];
  static const _sectionNames = ['1-2节', '3-4节', '5-6节', '7-8节', '9-10节'];
  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  String campus = '2';
  String building = '';
  String day = '1';
  String section = '03-04';
  List<Building> buildings = [];
  List<String> rooms = [];
  bool loading = false;
  String? error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadBuildings();
  }

  Future<void> _loadBuildings() async {
    try {
      final b = await ref.read(apiClientProvider).fetchBuildings(campus);
      if (!mounted) return;
      setState(() {
        buildings = b;
        building = b.isNotEmpty ? b.first.id : '';
      });
      _query();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        rooms = [];
        error = '离线或网络异常，空闲教室不可用';
      });
    }
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _query);
  }

  Future<void> _query() async {
    if (building.isEmpty) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final term = await api.getCurrentTerm();
      final parts = section.split('-');
      final r = await api.queryClassrooms(
        campus: campus,
        building: building,
        term: term,
        weekFrom: '1',
        weekTo: '20',
        dayFrom: day,
        dayTo: day,
        jcFrom: parts[0],
        jcTo: parts[1],
      );
      if (!mounted) return;
      setState(() {
        rooms = r;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        rooms = [];
        loading = false;
        error = '离线或网络异常，空闲教室不可用';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayIndex = int.tryParse(day);
    final dayName = dayIndex != null && dayIndex >= 1 && dayIndex <= 7
        ? _weekNames[dayIndex - 1]
        : '一';
    final sectionName = _sectionNames[_sectionPairs.indexOf(section)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E9F0)),
            boxShadow: const [BoxShadow(color: Color(0x0F3B82F6), blurRadius: 10)],
          ),
          child: Row(
            children: [
              _cond(
                '校区',
                ['1', '2'],
                ['一校区', '二校区'],
                campus,
                (v) {
                  campus = v;
                  _loadBuildings();
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cond(
                  '教学楼',
                  [for (final b in buildings) b.id],
                  [for (final b in buildings) b.name],
                  building,
                  (v) {
                    building = v;
                    _onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _cond(
                '星期',
                ['1', '2', '3', '4', '5', '6', '7'],
                _weekNames,
                day,
                (v) {
                  day = v;
                  _onChanged();
                },
              ),
              const SizedBox(width: 8),
              _cond(
                '节次',
                _sectionPairs,
                _sectionNames,
                section,
                (v) {
                  section = v;
                  _onChanged();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '共 ${rooms.length} 间空闲教室',
                style: const TextStyle(fontSize: 10, color: kTextMuted),
              ),
              Text(
                '周$dayName · $sectionName',
                style: const TextStyle(fontSize: 9, color: Color(0xFF9AA3AD)),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? EmptyView(text: error!)
                  : rooms.isEmpty
                      ? const EmptyView(text: '该条件下暂无空闲教室')
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 9,
                            crossAxisSpacing: 9,
                            childAspectRatio: 1.9,
                          ),
                          itemCount: rooms.length,
                          itemBuilder: (_, i) => RoomCard(name: rooms[i]),
                        ),
        ),
      ],
    );
  }

  Widget _cond(
    String label,
    List<String> values,
    List<String> names,
    String current,
    ValueChanged<String> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF9AA3AD))),
        const SizedBox(height: 2),
        DropdownButton<String>(
          value: current,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (var i = 0; i < values.length; i++)
              DropdownMenuItem(
                value: values[i],
                child: Text(names[i], style: const TextStyle(fontSize: 11)),
              ),
          ],
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ],
    );
  }
}
