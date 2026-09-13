import 'package:flutter/material.dart';

import 'mac_card.dart';

class RoomCard extends StatelessWidget {
  final String name;
  const RoomCard({super.key, required this.name});

  @override
  Widget build(BuildContext context) => MacCard(
    radius: 14,
    // 背景交给下面的蓝白渐变，MacCard 只负责投影 + 高光描边
    background: Colors.transparent,
    padding: EdgeInsets.zero,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0F6FF), Color(0xFFEAF2FF)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '● 空闲中',
            style: TextStyle(
              fontSize: 9,
              color: Color(0xFF16A34A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
