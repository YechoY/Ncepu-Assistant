import 'package:flutter/material.dart';

class OfflineBanner extends StatelessWidget {
  final String text;
  const OfflineBanner({super.key, this.text = '离线模式 · 显示缓存数据'});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Color(0xFF7C2D12)),
        ),
      );
}
