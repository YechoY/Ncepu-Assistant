import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

class CapsuleNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const CapsuleNav({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const labels = ['课表', '成绩', '考试', '教室'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: GlassCard(
        radius: 22,
        opacity: 0.12,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      gradient: i == index
                          ? const LinearGradient(colors: [Color(0xFF7DB4FF), kPrimary])
                          : null,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: i == index
                          ? [BoxShadow(color: kPrimary.withValues(alpha: .28), blurRadius: 6)]
                          : null,
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w400,
                        color: i == index ? Colors.white : const Color(0xFF5B6B85),
                      ),
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
