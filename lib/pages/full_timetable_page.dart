import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/full_course.dart';
import '../providers/app_state.dart';
import '../providers/data_state.dart' show formatUpdatedAt;
import '../theme.dart';
import '../widgets/glass_background.dart';
import '../widgets/mac_card.dart';

/// 周次显示：在接口原文（如 "1-12(周)"）前加「上课周次：」前缀。
String _formatWeeks(String raw) => '上课周次：$raw';

/// 「查看全部课表」页面：展示本学期整学期课表（xskb_list.do）。
/// 网格 7 列(周一..周日) × 5 行(第一..五大节)，每格可能有多门课（跨周）。
/// 外层卡片只显示课程名 + 上课地点；点击卡片弹出详情（老师/周次/教室/分组/编号）。
class FullTimetablePage extends ConsumerStatefulWidget {
  const FullTimetablePage({super.key});

  @override
  ConsumerState<FullTimetablePage> createState() => _FullTimetablePageState();
}

class _FullTimetablePageState extends ConsumerState<FullTimetablePage> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _sections = ['第一大节', '第二大节', '第三大节', '第四大节', '第五大节'];
  static const _colW = 116.0;
  static const _secW = 33.0;
  static const _cardSlot = 76.0; // 单张课程卡高度（含卡间距）；整行高度 = 该节最多课程数 × 此值
  static const _hGap = 3.0; // 列水平间距（左右各一半）
  static const _rowGap = 8.0; // 行之间的竖直间距
  static const _headerH = 28.0; // 星期表头行高（左右两侧共用以对齐）

  /// 五行统一的行高：取「整张表」所有格子中课程数最多的张数 × 单卡高度。
  /// 不能按每行各自的课程数伸缩——否则像第五大节这种整节无课的行会明显比
  /// 上面有课的行矮一截，左右两列错位、视觉不齐。全表统一后五行始终等高，
  /// 某格有多门跨周课时五行一起加高。
  double get _rowH {
    var maxCount = 1;
    for (var s = 1; s <= 5; s++) {
      for (var day = 1; day <= 7; day++) {
        final n = _at(day, s).length;
        if (n > maxCount) maxCount = n;
      }
    }
    return maxCount * _cardSlot;
  }

  // 整学期课表缓存键：页面只查当前学期，故用固定键；联网成功会持续续期。
  static const _cacheKey = 'full_timetable_current';
  // 缓存有效期：7 天内进入页面直接用缓存、不联网；超过 7 天才后台静默自动刷新。
  // 其余情况一律靠右上角刷新按钮手动更新。
  static const _cacheMaxAge = Duration(days: 7);

  bool _loading = true;
  bool _refreshing = false; // 已有内容时的联网刷新中（后台静默或手动）
  String? _error;
  List<FullCourse> _courses = [];
  int? _updatedAt; // 缓存键的最后写入时间（毫秒），用于顶栏显示更新时间

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 缓存优先：有非空缓存立即渲染，且 7 天内不再自动联网；仅当缓存超过 7 天
  /// （或读不到写入时间）时才后台静默刷新一次。无缓存才转圈等联网结果。
  /// 想随时更新可点右上角刷新按钮手动触发。离线（非校园网）也能看到缓存课表。
  Future<void> _load() async {
    final cache = ref.read(cacheServiceProvider);
    final cached = await cache.loadJson(_cacheKey, ttlDays: 30);
    final cachedAt = await cache.updatedAt(_cacheKey);
    final cachedList = cached is List
        ? cached
              .map((e) => FullCourse.fromJson(e as Map<String, dynamic>))
              .toList()
        : <FullCourse>[];
    if (!mounted) return;
    if (cachedList.isNotEmpty) {
      final stale =
          cachedAt == null ||
          DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(cachedAt),
              ) >
              _cacheMaxAge;
      setState(() {
        _courses = cachedList;
        _updatedAt = cachedAt;
        _loading = false;
        _refreshing = stale;
      });
      if (stale) await _fetch(); // 仅缓存超 7 天才自动更新
    } else {
      await _fetch(); // 无缓存：保持转圈，等联网结果
    }
  }

  /// 联网获取整学期课表并写缓存。
  /// [manual] 为 true（点刷新按钮）时失败会弹提示；后台静默刷新失败不打扰。
  /// 会话失效时接口会返回登录页并解析为空列表，此时若本地已有数据则不覆盖、不写缓存。
  Future<void> _fetch({bool manual = false}) async {
    try {
      final api = ref.read(apiClientProvider);
      final list = await api.fetchFullTimetable(); // 仅当前学期
      if (!mounted) return;
      if (list.isEmpty && _courses.isNotEmpty) {
        throw StateError('返回为空，疑似会话失效'); // 走 catch 保留好数据
      }
      if (list.isNotEmpty) {
        await ref
            .read(cacheServiceProvider)
            .saveJson(_cacheKey, list.map((e) => e.toJson()).toList());
      }
      setState(() {
        _courses = list;
        _error = null;
        _loading = false;
        _refreshing = false;
      });
      // 取缓存实际写入时间作为「更新时间」展示。
      if (list.isNotEmpty && mounted) {
        final at = await ref.read(cacheServiceProvider).updatedAt(_cacheKey);
        setState(() => _updatedAt = at);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
      if (_courses.isEmpty) {
        setState(() => _error = '获取失败，请确认已连接校园网后重试');
      } else if (manual) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('刷新失败，已显示缓存数据')));
      }
    }
  }

  /// 点刷新按钮：强制联网重查（不走缓存捷径），失败保留已显示内容。
  Future<void> _forceRefresh() async {
    if (_refreshing) return;
    setState(() {
      _error = null;
      _refreshing = true;
      if (_courses.isEmpty) _loading = true; // 无数据可显示时转圈等待
    });
    await _fetch(manual: true);
  }

  /// 取第 day(1..7) 天、第 section(1..5) 大节的课程（可能多门）。
  List<FullCourse> _at(int day, int section) =>
      _courses.where((c) => c.day == day && c.section == section).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 顶栏：返回 + 标题 + 刷新
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 18,
                        color: kPrimary,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '全部课表',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        Text(
                          '更新：${formatUpdatedAt(_updatedAt)}',
                          style: const TextStyle(
                            fontSize: 9,
                            color: kTextMuted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        size: 20,
                        color: kPrimary,
                      ),
                      onPressed: (_loading || _refreshing)
                          ? null
                          : _forceRefresh,
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(fontSize: 13, color: kTextMuted),
        ),
      );
    }
    if (_courses.isEmpty) {
      return const Center(
        child: Text(
          '本学期暂无课表信息',
          style: TextStyle(fontSize: 13, color: kTextMuted),
        ),
      );
    }
    // 左侧节次列固定不动；右侧 7 天区域可横向滚动。两者放在同一个纵向滚动里，
    // 因此上下滚动时左右同步、左侧节次列不会随横向滚动移动。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _leftColumn(), // 固定：节次列
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dayHeaderRow(),
                  for (var s = 1; s <= 5; s++) _dayRow(s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 固定在左侧的节次列：顶部占位对齐星期表头，其下每个大节一个框。
  Widget _leftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部占位：与右侧星期表头等高（表头文字 + 上下 padding 4*2 + 下方间距）
        const SizedBox(width: _secW, height: _headerH + _rowGap),
        for (var s = 1; s <= 5; s++)
          _GlassLabel(
            width: _secW,
            height: _rowH,
            margin: const EdgeInsets.only(bottom: _rowGap, right: _hGap),
            child: Text(
              // 逐字竖排（第/一/大/节），列窄也不挤
              _sections[s - 1].split('').join('\n'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B5563),
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }

  /// 右侧顶部的星期表头行。
  Widget _dayHeaderRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            _GlassLabel(
              width: _colW,
              height: _headerH,
              margin: const EdgeInsets.symmetric(horizontal: _hGap),
              child: Text(
                '周${_weekdays[i]}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: (i == 5 || i == 6)
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF1F2937),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 右侧某一大节的一行：7 天的课程格，行高五行统一（见 [_rowH]）。
  Widget _dayRow(int section) {
    final h = _rowH;
    return Padding(
      padding: const EdgeInsets.only(bottom: _rowGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var day = 1; day <= 7; day++)
            Container(
              width: _colW,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: _hGap),
              child: _cell(_at(day, section)),
            ),
        ],
      ),
    );
  }

  Widget _cell(List<FullCourse> courses) {
    if (courses.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _FullCourseCard(course: c),
          ),
      ],
    );
  }
}

/// 节次列 / 星期表头用的毛玻璃标签格。
///
/// 与课程卡（实色 MacCard）区分：标签要能透出背后的渐变底色，故用
/// BackdropFilter 做真模糊 + 较深的白色 tint + 细白高光描边。
/// 刻意不带 GlassCard 那种 32 大扩散阴影——一页有 12 个这种密集小格，
/// 大阴影互相叠加会显脏且增加绘制负担。
class _GlassLabel extends StatelessWidget {
  final Widget child;
  final double width;
  final double height;
  final EdgeInsetsGeometry margin;

  const _GlassLabel({
    required this.child,
    required this.width,
    required this.height,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 比原 0.35 更深的白 tint；叠上背景模糊后呈磨砂质感
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 外层课程卡：只展示课程名 + 上课地点，点击弹详情。
class _FullCourseCard extends StatelessWidget {
  final FullCourse course;
  const _FullCourseCard({required this.course});

  @override
  Widget build(BuildContext context) {
    final c = courseColor(course.name);
    return MacCard(
      radius: 12,
      background: c.bg,
      accent: c.border,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: () => showDialog(
        context: context,
        builder: (_) => _FullCourseDialog(course: course),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            course.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c.name,
              height: 1.15,
            ),
          ),
          if (course.location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                course.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF44515F),
                  height: 1.1,
                ),
              ),
            ),
          if (course.weeks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatWeeks(course.weeks),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: kPrimary,
                  height: 1.1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 点击卡片后的详情弹窗，展示全部字段。
class _FullCourseDialog extends StatelessWidget {
  final FullCourse course;
  const _FullCourseDialog({required this.course});

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v) {
      if (v.trim().isEmpty) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEEF2F9))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                k,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    const days = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const secs = ['', '第一大节', '第二大节', '第三大节', '第四大节', '第五大节'];
    final when =
        '${course.day >= 1 && course.day <= 7 ? days[course.day] : ''} ${course.section >= 1 && course.section <= 5 ? secs[course.section] : ''}'
            .trim();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF6B7280),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            row('上课时间', when),
            row('周次(节次)', course.weeks),
            row('上课地点', course.location),
            row('任课老师', course.teacher),
            row('分组名称', course.group),
            row('课程编号', course.code),
          ],
        ),
      ),
    );
  }
}
