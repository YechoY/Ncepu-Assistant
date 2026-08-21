import 'package:flutter/material.dart';

import '../theme.dart';

class TopBar extends StatelessWidget {
  final String title;
  final bool showRefresh;
  final VoidCallback? onRefresh;
  final String userName;
  final VoidCallback onUserTap;
  const TopBar({
    super.key,
    required this.title,
    this.showRefresh = false,
    this.onRefresh,
    required this.userName,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                foreground: Paint()
                  ..shader = const LinearGradient(colors: [Color(0xFF1E3A8A), kPrimary])
                      .createShader(const Rect.fromLTWH(0, 0, 160, 24)),
              ),
            ),
          ),
          if (showRefresh)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: kPrimary),
              onPressed: onRefresh,
            ),
          GestureDetector(
            onTap: onUserTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFD6E4FB)),
              ),
              child: Text(
                userName,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
