import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/building.dart';
import '../providers/app_state.dart';
import '../providers/auth_state.dart';
import '../providers/data_state.dart';
import '../theme.dart';
import '../widgets/border_beam.dart';
import '../widgets/empty_view.dart';
import '../widgets/glass_dropdown.dart';
import '../widgets/room_card.dart';

class ClassroomsPage extends ConsumerStatefulWidget {
  const ClassroomsPage({super.key});
  @override
  ConsumerState<ClassroomsPage> createState() => _ClassroomsPageState();
}

class _ClassroomsPageState extends ConsumerState<ClassroomsPage> {
  // 节次自由起止：第 1 节～第 10 节（值为两位字符串，对齐接口 jc 参数）
  static const _sectionVals = [
    '01',
    '02',
    '03',
    '04',
    '05',
    '06',
    '07',
    '08',
    '09',
    '10',
  ];
  static const _sectionNames = [
    '第1节',
    '第2节',
    '第3节',
    '第4节',
    '第5节',
    '第6节',
    '第7节',
    '第8节',
    '第9节',
    '第10节',
  ];

  String campus = '2';
  String building = '';
  // 自定义时间段：
  // - dateFrom/dateTo：查询日期段（星期几由日期换算），限制在同一周内，默认今天~今天
  // - jcFrom/jcTo：第几节到第几节，可自由组合（如第 3~6 节），默认沿用时间规则那一对
  // - 周次不单独存：由起始日期相对「当前周基准」反算（见 _weekOf）
  late DateTime dateFrom;
  late DateTime dateTo;
  String jcFrom = '03';
  String jcTo = '04';
  // 周次换算基准：baseMonday 这一天对应学期第 baseWeek 周的周一。
  // 优先取 dataState 已缓存的 currentWeek/currentWeekBase；缺失时查询前联网校正。
  DateTime? baseMonday;
  int? baseWeek;
  List<Building> buildings = [];
  List<String> rooms = [];
  bool loading = false;
  String? error;
  DateTime? lastQueryAt; // 最近一次成功查询空闲教室的时间
  bool _autoLoading = false; // 是否已排一次自动补拉，避免 build 里重复触发

  @override
  void initState() {
    super.initState();
    _initDefaults();
    _initBase();
    _loadBuildings();
  }

  /// 仅保留日期（去掉时分秒），避免日期比较受当天时间干扰。
  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 某天所在周的周一（同样只保留日期）。
  DateTime _mondayOf(DateTime d) =>
      _dayOnly(d.subtract(Duration(days: d.weekday - 1)));

  /// 从 dataState 缓存初始化「当前周基准」；缓存要等启动流程载入，
  /// 没有也没关系——_weekOf 实时读 dataState，查询前还会联网兜底。
  void _initBase() {
    final ds = ref.read(dataStateProvider);
    if (ds.currentWeek != null && ds.currentWeekBase.isNotEmpty) {
      final m = DateTime.tryParse(ds.currentWeekBase);
      if (m != null) {
        baseMonday = m;
        baseWeek = ds.currentWeek;
      }
    }
  }

  /// 由任意日期反算它是学期第几周：基准周 + 两个周一相差的整周数。
  int _weekOf(DateTime d) {
    final ds = ref.read(dataStateProvider);
    DateTime? bm = baseMonday;
    if (bm == null && ds.currentWeekBase.isNotEmpty) {
      bm = DateTime.tryParse(ds.currentWeekBase);
    }
    bm ??= _mondayOf(DateTime.now());
    final bw = baseWeek ?? ds.currentWeek ?? 1;
    final diffWeeks = _mondayOf(d).difference(bm).inDays ~/ 7;
    return bw + diffWeeks;
  }

  /// 默认日期=今天，节次按当前时间：8点前1-2节，10点前3-4节，14:30前5-6节，16:10前7-8节，之后9-10节
  void _initDefaults() {
    final now = DateTime.now();
    dateFrom = _dayOnly(now);
    dateTo = dateFrom;

    final minutes = now.hour * 60 + now.minute;
    String pair;
    if (minutes < 8 * 60) {
      pair = '01-02';
    } else if (minutes < 10 * 60) {
      pair = '03-04';
    } else if (minutes < 14 * 60 + 30) {
      pair = '05-06';
    } else if (minutes < 16 * 60 + 10) {
      pair = '07-08';
    } else {
      pair = '09-10';
    }
    jcFrom = pair.substring(0, 2);
    jcTo = pair.substring(3, 5);
  }

  /// 拉取当前校区的教学楼列表。
  /// [query] 为 true 时（首次进入或切换校区）在加载完成后自动查询一次空闲教室。
  /// 进页面时会话可能尚未就绪导致首拉失败，这里做一次短延迟重试。
  Future<void> _loadBuildings({bool query = true}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final b = await ref.read(apiClientProvider).fetchBuildings(campus);
        if (!mounted) return;
        if (b.isEmpty && attempt == 0) {
          // 拿到空列表可能是会话未就绪，稍等重试一次。
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }
        setState(() {
          buildings = b;
          building = b.isNotEmpty ? b.first.id : '';
          if (b.isNotEmpty) error = null;
        });
        if (query && building.isNotEmpty) _query();
        return;
      } catch (_) {
        if (!mounted) return;
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 600));
          continue; // 首次失败：短暂等待后重试
        }
        setState(() {
          rooms = [];
          error = '离线或网络异常，空闲教室不可用';
        });
      }
    }
  }

  /// 周次按钮：日历任选一天 → 定位到那一周，并把日期段重置为「当天~当天」。
  Future<void> _pickWeek() async {
    final today = _dayOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: dateFrom,
      firstDate: today.subtract(const Duration(days: 140)),
      lastDate: today.add(const Duration(days: 140)),
      helpText: '选择日期（自动定位学期周次）',
    );
    if (picked == null || !mounted) return;
    setState(() {
      dateFrom = _dayOnly(picked);
      dateTo = dateFrom;
    });
  }

  /// 日期段选择。
  /// 起始日期：联动重算周次；结束日期若早于新起始或不在同一周，收回到当天。
  /// 结束日期：选择器范围限定为「起始日期 ~ 该周周日」，从交互上杜绝跨周/倒挂。
  Future<void> _pickDate({required bool isFrom}) async {
    final today = _dayOnly(DateTime.now());
    if (isFrom) {
      final picked = await showDatePicker(
        context: context,
        initialDate: dateFrom,
        firstDate: today.subtract(const Duration(days: 140)),
        lastDate: today.add(const Duration(days: 140)),
        helpText: '选择起始日期',
      );
      if (picked == null || !mounted) return;
      setState(() {
        dateFrom = _dayOnly(picked);
        final sunday = _mondayOf(dateFrom).add(const Duration(days: 6));
        if (dateTo.isBefore(dateFrom) || dateTo.isAfter(sunday)) {
          dateTo = dateFrom;
        }
      });
    } else {
      final first = dateFrom;
      final last = _mondayOf(dateFrom).add(const Duration(days: 6));
      final initial = dateTo.isBefore(first) || dateTo.isAfter(last)
          ? first
          : dateTo;
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first,
        lastDate: last,
        helpText: '选择结束日期（本周内）',
      );
      if (picked == null || !mounted) return;
      setState(() => dateTo = _dayOnly(picked));
    }
  }

  /// 节次起止联动：起 > 止 时把另一端拉齐，保证查询区间合法。
  /// 两位等宽字符串（'01'..'10'）可直接按字符串比较，等价数值比较。
  void _setJcFrom(String v) => setState(() {
    jcFrom = v;
    if (v.compareTo(jcTo) > 0) jcTo = v;
  });

  void _setJcTo(String v) => setState(() {
    jcTo = v;
    if (v.compareTo(jcFrom) < 0) jcFrom = v;
  });

  /// 手动查询（点查询按钮触发）
  Future<void> _query() async {
    // 教学楼可能因进页面时会话未就绪而没拉到（buildings 为空）。
    // 查询前先补拉一次，避免“教学楼没了、必须手动刷新”的情况。
    if (buildings.isEmpty) {
      await _loadBuildings(query: false);
    }
    if (building.isEmpty) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final term = await api.getCurrentTerm();
      // 当前周基准缺失（缓存还没载入）时联网查一次当前周并校正基准；
      // 再拿不到则 _weekOf 内部兜底为第 1 周。
      if (ref.read(dataStateProvider).currentWeek == null) {
        final w = await api.fetchCurrentWeek();
        if (w != null) {
          baseMonday = _mondayOf(DateTime.now());
          baseWeek = w;
        }
      }
      final week = _weekOf(dateFrom);
      // 与官网一致：zc == zc2 只查「选定的这一周」，而不是整学期 1~20 周都空闲。
      // 星期由日期段换算（DateTime.weekday：1=周一 … 7=周日）。
      final r = await api.queryClassrooms(
        campus: campus,
        building: building,
        term: term,
        weekFrom: '$week',
        weekTo: '$week',
        dayFrom: '${dateFrom.weekday}',
        dayTo: '${dateTo.weekday}',
        jcFrom: jcFrom,
        jcTo: jcTo,
      );
      if (!mounted) return;
      setState(() {
        rooms = r;
        loading = false;
        lastQueryAt = DateTime.now();
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
    // 关键时序问题：_MainShell 用 IndexedStack 一次性构建所有 Tab，
    // 所以本页 initState 在 App 刚打开、还停在课表页时就跑了 _loadBuildings()，
    // 那时后台自动登录/会话往往还没建立好，导致教学楼拉空、也没查询。
    // 这里监听登录态：一旦“登录成功”且教学楼仍为空，就自动补拉并查询一次。
    ref.listen(authStateProvider, (prev, next) {
      final justLoggedIn = (prev?.loggedIn ?? false) == false && next.loggedIn;
      if (justLoggedIn && buildings.isEmpty) {
        _loadBuildings(); // 会话已就绪，补拉教学楼并自动查询
      }
    });
    // 兜底：若已登录但教学楼仍为空（例如登录早于本页构建，listen 没捕获到跳变），
    // 在本帧渲染后补拉一次。_autoLoading 一旦置位就不再自动重触发，避免离线时
    // 每次 build 都发起网络请求造成空转；线上恢复由上面的 ref.listen 负责重触发。
    final loggedIn = ref.watch(authStateProvider).loggedIn;
    if (loggedIn && buildings.isEmpty && !loading && !_autoLoading) {
      _autoLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBuildings());
    }
    final week = _weekOf(dateFrom);
    // 日期段文案：同一天只显示一个日期，跨天显示「起-止」。
    String md(DateTime d) => '${d.month}/${d.day}';
    final dateRange = dateTo == dateFrom
        ? md(dateFrom)
        : '${md(dateFrom)}-${md(dateTo)}';
    final jcRange = '${int.parse(jcFrom)}-${int.parse(jcTo)}节';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: BorderBeam(
            radius: 14,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 35,
                    runSpacing: 13,
                    children: [
                      _cond('校区', ['1', '2'], ['一校区', '二校区'], campus, (v) {
                        if (v == campus) return;
                        setState(() => campus = v);
                        // 换校区只刷新教学楼列表（教学楼随校区变），不自动查询；
                        // 真正查询等用户点「查询」按钮。
                        _loadBuildings(query: false);
                      }),
                      _cond(
                        '教学楼',
                        [for (final b in buildings) b.id],
                        [for (final b in buildings) b.name],
                        building,
                        (v) {
                          if (v == building) return;
                          setState(() => building = v);
                        },
                      ),
                      // 周次：日历选一天自动定位学期周次
                      _weekChip(week),
                      // 日期段（星期由日期换算）：起/止，结束日期限定本周内
                      _dateChip('起', dateFrom, () => _pickDate(isFrom: true)),
                      _dateChip('止', dateTo, () => _pickDate(isFrom: false)),
                      // 节次段：第几节到第几节，1~10 自由起止
                      _cond(
                        '节次起',
                        _sectionVals,
                        _sectionNames,
                        jcFrom,
                        _setJcFrom,
                      ),
                      _cond('节次止', _sectionVals, _sectionNames, jcTo, _setJcTo),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 绿色小查询按钮：放在条件框右下角
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 96,
                      child: ElevatedButton.icon(
                        onPressed: loading ? null : _query,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                          shadowColor: const Color(0x6622C55E),
                        ),
                        icon: const Icon(
                          Icons.search,
                          size: 14,
                          color: Colors.white,
                        ),
                        label: const Text(
                          '查询',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              // 三等分：左=数量，中=更新时间(居中)，右=周次·节次
              Expanded(
                child: Text(
                  '共 ${rooms.length} 间空闲教室',
                  style: const TextStyle(fontSize: 10, color: kTextMuted),
                ),
              ),
              Expanded(
                child: Text(
                  '更新：${lastQueryAt == null ? '未查询' : formatUpdatedAt(lastQueryAt!.millisecondsSinceEpoch)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: kTextMuted),
                ),
              ),
              Expanded(
                child: Text(
                  '第$week周 · $dateRange · $jcRange',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF9AA3AD)),
                ),
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
    return GlassDropdown(
      label: label,
      value: current,
      items: values,
      displayNames: names,
      onChanged: onChanged,
    );
  }

  /// 玻璃风小按钮的通用外壳（样式对齐 GlassDropdown：半透明白 + 细白描边 + 柔和投影）。
  Widget _chipShell({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  /// 周次按钮：「第 N 周」+ 日历图标，点击弹日历选日期。
  Widget _weekChip(int week) {
    return _chipShell(
      onTap: _pickWeek,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 13,
            color: Color(0xFF6B7280),
          ),
          const SizedBox(width: 5),
          Text(
            '第$week周',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 日期段按钮：小标签（起/止）+ M/D + 下拉箭头。
  Widget _dateChip(String label, DateTime d, VoidCallback onTap) {
    return _chipShell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${d.month}/${d.day}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF6B7280)),
        ],
      ),
    );
  }
}
