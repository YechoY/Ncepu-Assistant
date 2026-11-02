import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

class TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String userName;
  final String? userClass; // 班级（胶囊内「·」后展示，可空）
  final VoidCallback onUserTap;
  final VoidCallback? onBack; // 内嵌返回按钮（学习服务用）
  const TopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.userName,
    this.userClass,
    required this.onUserTap,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: GlassCard(
        radius: 14,
        opacity: 0.14,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (onBack != null) ...[
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: kPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              // 标题 + 更新时间小字纵向排列，仍在同一个顶栏框内。
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [kInk, kPrimary],
                        ).createShader(const Rect.fromLTWH(0, 0, 160, 24)),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: kTextMuted),
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
            GestureDetector(
              onTap: onUserTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: kInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    // 姓名 · 班级 单行胶囊；班级过长时截断，姓名始终优先
                    if (userClass != null && userClass!.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '·',
                        style: TextStyle(
                          fontSize: 11,
                          color: kTextMuted.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          userClass!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: kTextMuted.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
