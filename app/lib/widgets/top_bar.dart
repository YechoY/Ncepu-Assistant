import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

class TopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final Widget? trailing;
  final String userName;
  final String? userClass; // 班级（头像胶囊第二行，可空）
  final VoidCallback onUserTap;
  final VoidCallback? onBack; // 内嵌返回按钮（学习服务用）
  const TopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.showRefresh = false,
    this.onRefresh,
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
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: kInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (userClass != null && userClass!.isNotEmpty)
                      Text(
                        userClass!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: kTextMuted.withValues(alpha: 0.8),
                        ),
                      ),
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
