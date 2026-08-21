import 'package:flutter/material.dart';

import '../models/grade.dart';
import '../theme.dart';

class GradeCard extends StatelessWidget {
  final Grade grade;
  const GradeCard({super.key, required this.grade});

  @override
  Widget build(BuildContext context) {
    final badge = grade.grade;
    final bg = badge.contains('优')
        ? const Color(0xFFF0FDF4)
        : badge.contains('良')
            ? const Color(0xFFF0F9FF)
            : badge.contains('中')
                ? const Color(0xFFFFF7ED)
                : badge.contains('不及格')
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFEFF6FF);
    final fg = badge.contains('优')
        ? const Color(0xFF14532D)
        : badge.contains('良')
            ? const Color(0xFF0C4A6E)
            : badge.contains('中')
                ? const Color(0xFF7C2D12)
                : badge.contains('不及格')
                    ? const Color(0xFF7F1D1D)
                    : const Color(0xFF1E3A8A);
    return Container(
      padding: const EdgeInsets.all(11),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF1F6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grade.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kTextMain),
                ),
                const SizedBox(height: 3),
                Text(
                  '${grade.term} · ${grade.attr} · ${grade.credit}学分',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF9AA3AD)),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: fg.withValues(alpha: .3)),
            ),
            child: Text(
              badge,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
