import 'package:flutter/material.dart';

import '../models/grade.dart';
import '../theme.dart';
import 'glass_card.dart';

class GradeCard extends StatelessWidget {
  final Grade grade;
  const GradeCard({super.key, required this.grade});

  @override
  Widget build(BuildContext context) {
    final badge = grade.grade;
    // 等级色：优良中差四档功能色（柔和版），用于左侧竖条与右侧徽章。
    final bg = badge.contains('优')
        ? const Color(0xFFE8F5EC)
        : badge.contains('良')
        ? const Color(0xFFE3F0F9)
        : badge.contains('中')
        ? const Color(0xFFFBEFDF)
        : badge.contains('不及格')
        ? const Color(0xFFFBE6E6)
        : kPrimaryContainer;
    final fg = badge.contains('优')
        ? const Color(0xFF3E7D55)
        : badge.contains('良')
        ? const Color(0xFF3B7399)
        : badge.contains('中')
        ? const Color(0xFFB07432)
        : badge.contains('不及格')
        ? const Color(0xFFB85450)
        : kInk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 18,
        live: false,
        opacity: kFrostAlpha,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            // 等级色竖条
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    grade.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: kTextMain,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${grade.term} · ${grade.attr} · ${grade.credit}学分',
                    style: const TextStyle(fontSize: 10.5, color: kTextMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: fg.withValues(alpha: .35)),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
