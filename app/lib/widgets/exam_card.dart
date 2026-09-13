import 'package:flutter/material.dart';

import '../models/exam.dart';
import 'mac_card.dart';

class ExamCard extends StatelessWidget {
  final Exam exam;
  final bool done;
  const ExamCard({super.key, required this.exam, required this.done});

  @override
  Widget build(BuildContext context) {
    final dim = done;
    final text = dim ? const Color(0xFF9AA3AD) : const Color(0xFF1F2937);
    return MacCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      background: dim ? const Color(0xFFF6F7F8) : Colors.white,
      // 未考=绿色强调条，已考=灰色
      accent: dim ? const Color(0xFFD1D5DB) : const Color(0xFF22C55E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exam.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: dim ? const Color(0xFFEEF1F6) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: dim ? const Color(0xFFE2E6EE) : const Color(0xFFBBF7D0),
                  ),
                ),
                child: Text(
                  dim ? '已考' : '未考',
                  style: TextStyle(
                    fontSize: 10,
                    color: dim ? const Color(0xFF9AA3AD) : const Color(0xFF16A34A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${exam.type} · ${exam.time}',
            style: TextStyle(
              fontSize: 10,
              color: dim ? const Color(0xFF9AA3AD) : const Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${exam.location} · ${exam.teacher}',
            style: TextStyle(
              fontSize: 10,
              color: dim ? const Color(0xFF9AA3AD) : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
