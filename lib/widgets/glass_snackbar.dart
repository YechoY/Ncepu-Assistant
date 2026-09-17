import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

/// 玻璃风格轻提示：静态磨砂浮卡，替代默认的黑色 SnackBar。
void showGlassSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      content: GlassCard(
        radius: 16,
        live: false,
        // 静态磨砂必须显式用 kFrostAlpha；GlassCard 默认 opacity 是实时玻璃
        // 的 kGlassAlpha(0.58)，浮层上会太透、透出底下内容显得杂乱。
        opacity: kFrostAlpha,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 17, color: kPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: kTextMain,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
