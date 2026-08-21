import 'package:flutter/material.dart';

const kPrimary = Color(0xFF3B82F6);
const kPrimaryDark = Color(0xFF2563EB);
const kBgTop = Color(0xFFE8F1FF);
const kBgBottom = Color(0xFFF7F9FD);
const kTextMain = Color(0xFF1F2937);
const kTextMuted = Color(0xFF6B7280);

ThemeData buildTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
    useMaterial3: true,
  );
  return base.copyWith(
    scaffoldBackgroundColor: kBgBottom,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
  );
}

// 课程 8 色（与桌面版一致）
const coursePalette = [
  (bg: Color(0xFFEFF6FF), border: Color(0xFFBFDBFE), name: Color(0xFF1E3A8A)),
  (bg: Color(0xFFF0FDF4), border: Color(0xFFBBF7D0), name: Color(0xFF14532D)),
  (bg: Color(0xFFFEF2F2), border: Color(0xFFFECACA), name: Color(0xFF7F1D1D)),
  (bg: Color(0xFFFFF7ED), border: Color(0xFFFED7AA), name: Color(0xFF7C2D12)),
  (bg: Color(0xFFF5F3FF), border: Color(0xFFDDD6FE), name: Color(0xFF4C1D95)),
  (bg: Color(0xFFFDF2F8), border: Color(0xFFFBCFE8), name: Color(0xFF831843)),
  (bg: Color(0xFFF0F9FF), border: Color(0xFFBAE6FD), name: Color(0xFF0C4A6E)),
  (bg: Color(0xFFFEFCE8), border: Color(0xFFFDE68A), name: Color(0xFF713F12)),
];

({Color bg, Color border, Color name}) courseColor(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return coursePalette[h % coursePalette.length];
}
