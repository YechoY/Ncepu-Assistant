import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

class TopBar extends StatelessWidget {
  final String title;
  final String? subtitle; // 标题下方的小字（如“更新：今天 08:30”），可空
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final Widget? trailing; // 刷新按钮左侧的自定义动作（如“全部课表”入口），可空
  final String userName;
  final VoidCallback onUserTap;
  const TopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.showRefresh = false,
    this.onRefresh,
    this.trailing,
    required this.userName,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: GlassCard(
        radius: 14,
        opacity: 0.14,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              // 标题 + 更新时间小字纵向排列，仍在同一个顶栏框内。
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [Color(0xFF1E3A8A), kPrimary],
                        ).createShader(const Rect.fromLTWH(0, 0, 160, 24)),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(fontSize: 10, color: kTextMuted),
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
            if (showRefresh)
              IconButton(
                icon: const Icon(Icons.refresh, size: 20, color: kPrimary),
                onPressed: onRefresh,
              ),
            GestureDetector(
              onTap: onUserTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF1E3A8A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
