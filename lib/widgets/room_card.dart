import 'package:flutter/material.dart';

class RoomCard extends StatelessWidget {
  final String name;
  const RoomCard({super.key, required this.name});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFF0F6FF), Color(0xFFEAF2FF)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD6E4FB)),
        ),
        child: Column(
          children: [
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '● 空闲中',
              style: TextStyle(fontSize: 9, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
}
