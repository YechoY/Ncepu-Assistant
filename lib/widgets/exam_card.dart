import 'package:flutter/material.dart';

import '../models/exam.dart';
import '../theme.dart';
import 'glass_card.dart';

class ExamCard extends StatelessWidget {
  final Exam exam;
  final bool done;
  const ExamCard({super.key, required this.exam, required this.done});

  @override
  Widget build(BuildContext context) {
    // 未考 = 薄荷绿功能色，已考 = 中性灰（整卡弱化）。
    final accent = done ? const Color(0xFFB6BCC9) : const Color(0xFF5E9C80);
    final badgeBg = done ? const Color(0xFFEFF1F5) : const Color(0xFFE3F1EC);
    final badgeFg = done ? kTextMuted : const Color(0xFF4E8A70);
    final titleColor = done ? kTextMuted : kTextMain;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 18,
        live: false,
        opacity: kFrostAlpha,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    exam.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        done ? Icons.check_circle_outline : Icons.schedule,
                        size: 11,
                        color: badgeFg,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        done ? '已考' : '未考',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: badgeFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            _infoLine(Icons.event_note_outlined, '${exam.type} · ${exam.time}'),
            const SizedBox(height: 4),
            _infoLine(Icons.place_outlined, '${exam.location} · ${exam.teacher}'),
          ],
        ),
      ),
    );
  }

  Widget _infoLine(IconData icon, String text) {
    return Row(
      children: [
        const SizedBox(width: 13),
        Icon(icon, size: 12, color: kTextMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: kTextMuted),
          ),
        ),
      ],
    );
  }
}
