// theme.dart —— 全局主题、颜色常量、课程配色算法。
//
// 把「颜色」「主题」这类会到处复用的东西集中放一个文件，是很常见的做法：
// 改配色只需改这里一处，全 App 生效。

import 'package:flutter/material.dart';

// 颜色常量。Color(0xFFxxxxxx) 里：
//   0x 表示十六进制；前两位 FF 是不透明度（Alpha，FF=完全不透明）；
//   后六位是 RGB。所以 0xFF3B82F6 = 不透明的 #3B82F6 蓝色。
// const = 编译期常量，性能最好，颜色这类固定值都应该用 const。
const kPrimary = Color(0xFF3B82F6); // 主色（蓝）
const kPrimaryDark = Color(0xFF2563EB); // 深主色
const kBgTop = Color(0xFFE8F1FF); // 背景渐变上端
const kBgBottom = Color(0xFFF7F9FD); // 背景渐变下端
const kTextMain = Color(0xFF1F2937); // 主文字色
const kTextMuted = Color(0xFF6B7280); // 次要/灰文字色

// 构建全局 ThemeData：MaterialApp 会用它作为默认样式来源。
ThemeData buildTheme() {
  final base = ThemeData(
    // fromSeed：给一个「种子色」，Material 3 会自动推导出一整套协调的配色方案。
    colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
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

// 课程 8 色（与桌面版一致）
// 每个元素是一个「记录（record）」——Dart 3 的匿名结构体，(bg: ..., border: ..., name: ...)
// 分别是卡片背景色、边框色、课程名文字色。三者搭配好，保证同一门课视觉统一。
// 背景用较深的浅色（约 Tailwind 100 档），比原来的 50 档更有存在感，同时仍能承托深色课名。
const coursePalette = [
  (bg: Color(0xFFDBEAFE), border: Color(0xFF93C5FD), name: Color(0xFF1E3A8A)), // 蓝
  (bg: Color(0xFFDCFCE7), border: Color(0xFF86EFAC), name: Color(0xFF14532D)), // 绿
  (bg: Color(0xFFFEE2E2), border: Color(0xFFFCA5A5), name: Color(0xFF7F1D1D)), // 红
  (bg: Color(0xFFFFEDD5), border: Color(0xFFFDBA74), name: Color(0xFF7C2D12)), // 橙
  (bg: Color(0xFFEDE9FE), border: Color(0xFFC4B5FD), name: Color(0xFF4C1D95)), // 紫
  (bg: Color(0xFFFCE7F3), border: Color(0xFFF9A8D4), name: Color(0xFF831843)), // 粉
  (bg: Color(0xFFE0F2FE), border: Color(0xFF7DD3FC), name: Color(0xFF0C4A6E)), // 天蓝
  (bg: Color(0xFFFEF9C3), border: Color(0xFFFDE047), name: Color(0xFF713F12)), // 黄
];

// 根据课程名「哈希」出一个稳定的配色。
// 思路：把课程名算成一个数字，再对调色板长度取余当作下标。
// 好处：同一门课名字不变 → 哈希不变 → 颜色永远一致；不同课大概率颜色不同。
// 返回类型 ({Color bg, Color border, Color name}) 就是上面那种记录类型。
({Color bg, Color border, Color name}) courseColor(String name) {
  var h = 0;
  // codeUnits：字符串每个字符的 UTF-16 编码值列表。
  for (final c in name.codeUnits) {
    // 经典的字符串哈希：h = h*31 + 字符码。
    // & 0x7fffffff 是按位与，作用是把结果限制在非负 int 范围内，防止溢出成负数。
    h = (h * 31 + c) & 0x7fffffff;
  }
  // % 取余，确保下标落在 0..palette.length-1 之间。
  return coursePalette[h % coursePalette.length];
}
