// theme.dart —— 全局主题、颜色常量、课程配色算法。
//
// 把「颜色」「主题」这类会到处复用的东西集中放一个文件，是很常见的做法：
// 改配色只需改这里一处，全 App 生效。
//
// 配色取向：浅色玻璃拟态。背景（GlassBackground）保持浅色渐变 + 柔光斑不动，
// 组件层用「高模糊半透明白 + 白色高光边 + 冷调柔影」的玻璃材质；
// 强调色取自雾蓝紫，课程色为一组低饱和粉彩（粉/蓝紫/薄荷/灰绿/天蓝/樱粉）。

import 'dart:ui';

import 'package:flutter/material.dart';

// ── 主色（雾蓝紫系）────────────────────────────────────────────
const kPrimary = Color(0xFF6E77B5); // 主色：实心按钮/选中态（白字对比约 4.5:1）
const kPrimaryDark = Color(0xFF5A62A0); // 深主色：按压/渐变端
const kPrimarySoft = Color(0xFFA4ABD6); // 柔主色：装饰光斑/淡彩
const kPrimaryContainer = Color(0xFFE7E9F7); // 极浅紫：选中底/浅色承托
const kInk = Color(0xFF454C84); // 墨紫：标题/链接/强调文字（替代旧深蓝 1E3A8A）
const kAccentPink = Color(0xFFF6BEC8); // 粉彩强调（周末等小面积点缀）

// ── 中性色 ────────────────────────────────────────────────────
const kBgTop = Color(0xFFE8F1FF); // 背景渐变上端（勿动：背景保持原样）
const kBgBottom = Color(0xFFF7F9FD); // 背景渐变下端
const kTextMain = Color(0xFF2E3350); // 主文字色（墨紫灰）
const kTextMuted = Color(0xFF7A8099); // 次要/灰文字色
const kWeekend = Color(0xFFC9707F); // 周末文字（柔和莓红，融入粉彩色系）

// ── 玻璃材质 token ────────────────────────────────────────────
// 浅色背景下玻璃白需要更高不透明度才能托住文字；真正的"透"靠模糊与高光边表达。
const kGlassTint = Color(0xFFFFFFFF);
const kGlassAlpha = 0.58; // 玻璃白默认透明度
const kFrostAlpha = 0.74; // 静态磨砂（无实时模糊）卡片的白不透明度：列表滚动性能优先时用
const kGlassBlur = 24.0; // 背景模糊 sigma（约等于 CSS backdrop-blur 50px）
const kGlassBorder = Color(0xB3FFFFFF); // 白色 70% 高光描边
const kGlassGridLine = Color(0x5998A4C4); // 网格线：雾蓝紫 35%
const kGlassShadow = Color(0x2E5B6691); // 冷调柔影（紫灰 18%）

/// 玻璃拟态统一动效曲线（对应 CSS cubic-bezier(0.16,1,0.3,1) 的 spring 手感）。
const Curve kSpring = Cubic(0.16, 1, 0.3, 1);
const Duration kSpringDur = Duration(milliseconds: 420);

/// 饱和度增强矩阵（约 1.6 倍）：叠在 BackdropFilter 上让透过玻璃的光斑更亮。
/// Flutter 没有 backdrop-saturate 的直接 API，用 ColorFilter.matrix 与 blur 组合。
final ColorFilter kGlassSaturate = ColorFilter.matrix(const <double>[
  1.4722,
  -0.4290,
  -0.0432,
  0,
  0,
  -0.1278,
  1.1710,
  -0.0432,
  0,
  0,
  -0.1278,
  -0.4290,
  1.5568,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

/// 高模糊 + 饱和度增强的背景滤镜（玻璃卡片统一使用）。
ImageFilter glassBlurFilter({double sigma = kGlassBlur}) => ImageFilter.compose(
  outer: kGlassSaturate,
  inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
);

// 构建全局 ThemeData：MaterialApp 会用它作为默认样式来源。
ThemeData buildTheme() {
  final base = ThemeData(
    // fromSeed：给一个「种子色」，Material 3 会自动推导出一整套协调的配色方案。
    colorScheme: ColorScheme.fromSeed(seedColor: kPrimarySoft),
    useMaterial3: true, // 启用 Material Design 3 风格
  );
  // copyWith：基于 base 复制一份，只覆盖想改的字段（Flutter 里大量用这种“不可变+复制修改”模式）。
  return base.copyWith(
    scaffoldBackgroundColor: kBgBottom, // 页面默认背景色
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ), // 透明无阴影顶栏
  );
}

// 课程 12 色：沿色环 30° 等分（2026-09-14 三次调整）。
// 之前 8 色版本仍出现「Python 课和网站课同色」——根因不是调色板数量，而是单纯
// 哈希取余无法避免碰撞（生日悖论：10 门课映射 12 个槽位，同色概率 >95%）。
// 现在颜色由页面层用 [assignCourseIndices] 做「按天冲突消解」分配（同一天的不同课
// 必不同色），哈希只决定初始偏好；调色板扩到 12 色给消解留出空间。
// 每个元素是一个「记录（record）」——Dart 3 的匿名结构体，(bg: ..., border: ..., name: ...)
// 分别是卡片背景色、边框色、课程名文字色。bg 取粉彩的浅色承托，border 用粉彩本体，
// name 用同色相的深色墨彩保证文字对比度。
const coursePalette = [
  (
    bg: Color(0xFFFDE0E3),
    border: Color(0xFFF098A3),
    name: Color(0xFF92414E),
  ), // 0 珊瑚红
  (
    bg: Color(0xFFFBE4D2),
    border: Color(0xFFF0B07A),
    name: Color(0xFF8E5522),
  ), // 1 暖橙
  (
    bg: Color(0xFFFBF0D0),
    border: Color(0xFFEBC96F),
    name: Color(0xFF87651C),
  ), // 2 琥珀黄
  (
    bg: Color(0xFFF6F6CE),
    border: Color(0xFFD6D77A),
    name: Color(0xFF717126),
  ), // 3 柠檬黄
  (
    bg: Color(0xFFE8F3D2),
    border: Color(0xFFB4D584),
    name: Color(0xFF4E7132),
  ), // 4 青柠绿
  (
    bg: Color(0xFFDEF0D8),
    border: Color(0xFF9BCB92),
    name: Color(0xFF3D6E45),
  ), // 5 嫩绿
  (
    bg: Color(0xFFD7F0E7),
    border: Color(0xFF87CBB6),
    name: Color(0xFF2E7260),
  ), // 6 薄荷绿
  (
    bg: Color(0xFFD6EEF1),
    border: Color(0xFF84C6D4),
    name: Color(0xFF2A6B78),
  ), // 7 蒂芙尼青
  (
    bg: Color(0xFFD8EBFA),
    border: Color(0xFF86BFE6),
    name: Color(0xFF2C628A),
  ), // 8 天蓝
  (
    bg: Color(0xFFDDE3F8),
    border: Color(0xFF96A3DC),
    name: Color(0xFF3E4987),
  ), // 9 钴蓝
  (
    bg: Color(0xFFEADFF8),
    border: Color(0xFFBFA5E2),
    name: Color(0xFF653D8B),
  ), // 10 蓝紫
  (
    bg: Color(0xFFFBDFF0),
    border: Color(0xFFE59AC4),
    name: Color(0xFF8B3C69),
  ), // 11 品红
];

/// 课程名 → 32 位哈希（FNV-1a + MurmurHash3 finalizer）。
/// 旧的 h*31 算法对中文课程名分布很差（UTF-16 码位高位聚集），
/// FNV 逐字节扩散 + 尾部雪崩混合让不同课名的下标尽可能拉开。
int courseHash(String name) {
  var h = 0x811c9dc5; // FNV offset basis
  for (final c in name.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF; // FNV prime
  }
  // MurmurHash3 fmix32：雪崩混合，让每一位输入影响所有输出位。
  h ^= h >> 16;
  h = (h * 0x85ebca6b) & 0xFFFFFFFF;
  h ^= h >> 13;
  h = (h * 0xc2b2ae35) & 0xFFFFFFFF;
  h ^= h >> 16;
  return h;
}

// 根据课程名「哈希」出一个稳定的配色（无冲突消解时的兜底）。
// 返回类型 ({Color bg, Color border, Color name}) 就是上面那种记录类型。
({Color bg, Color border, Color name}) courseColor(String name) =>
    coursePalette[courseHash(name) % coursePalette.length];

/// 按「同一天出现的不同课程必须不同色」的约束，为每门课分配调色板下标。
///
/// 入参 [courseDays]：课程名 → 该课出现在星期几（1..7）的集合。
/// 同一门课在一周内可能出现多天（如周一、周三），选色时要避开它所有出现天
/// 已占用的颜色；初始偏好由 [courseHash] 决定，冲突则顺序探测下一个颜色。
/// 结果稳定（按首次出现的星期排序），同名课始终拿到同一颜色。
Map<String, int> assignCourseIndices(Map<String, Set<int>> courseDays) {
  final names = courseDays.keys.toList()
    ..sort((a, b) {
      int earliest(Set<int> days) => days.reduce((x, y) => x < y ? x : y);
      final da = earliest(courseDays[a]!);
      final db = earliest(courseDays[b]!);
      return da != db ? da - db : a.compareTo(b);
    });
  final dayUsed = <int, Set<int>>{};
  final result = <String, int>{};
  final n = coursePalette.length;
  for (final name in names) {
    final days = courseDays[name]!;
    final forbidden = <int>{};
    for (final d in days) {
      forbidden.addAll(dayUsed[d] ?? const <int>{});
    }
    var idx = courseHash(name) % n;
    // 只有当天颜色没被占满时才探测（极端情况下退化为准许同色）。
    if (forbidden.length < n) {
      while (forbidden.contains(idx)) {
        idx = (idx + 1) % n;
      }
    }
    result[name] = idx;
    for (final d in days) {
      (dayUsed[d] ??= <int>{}).add(idx);
    }
  }
  return result;
}
