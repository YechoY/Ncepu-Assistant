import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

class RoomCard extends StatelessWidget {
  final String name;
  const RoomCard({super.key, required this.name});

  @override
  Widget build(BuildContext context) => GlassCard(
    radius: 18,
    live: false,
    opacity: kFrostAlpha,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        // 门牌图标：淡雾蓝紫圆底
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kPrimaryContainer,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.meeting_room_outlined,
            size: 18,
            color: kPrimary,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
              const SizedBox(height: 4),
              // 空闲状态：淡薄荷胶囊
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F1EC),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 5, color: Color(0xFF5E9C80)),
                    SizedBox(width: 4),
                    Text(
                      '空闲中',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFF4E8A70),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
