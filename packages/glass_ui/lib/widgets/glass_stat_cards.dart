// widgets/glass_stat_cards.dart —— 记录页顶部的余额卡 / 消费统计卡（公共组件）。
//
// 洗衣记录与饮水消费记录共用同一规格：
// 余额卡 = 横向紧凑布局（40 渐变圆图标 + 标签/金额 + 右侧自定义区）；
// 统计卡 = 横排若干项、项间细线分隔（如「今日消费 | 本月消费」）。
// 模块差异只通过颜色参数（light/deep）与 [GlassBalanceCard.trailing] 表达。

import 'package:flutter/material.dart';
import '../theme.dart';
import 'glass_card.dart';

/// 余额卡：左 40 渐变圆图标 + 标签/金额，右侧 [trailing]（刷新按钮/钱包明细）。
class GlassBalanceCard extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color light; // 渐变亮端
  final Color deep; // 渐变深端（同时用于柔影）
  final Widget? trailing;
  const GlassBalanceCard({
    super.key,
    required this.label,
    required this.amount,
    required this.icon,
    required this.light,
    required this.deep,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      live: false,
      opacity: kFrostAlpha,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [light, deep]),
              boxShadow: [
                BoxShadow(
                  color: deep.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: kTextMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  amount,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kInk,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) const SizedBox(width: 8),
          ?trailing,
        ],
      ),
    );
  }
}

/// 一项统计（图标 + 标签 + 已格式化的值）。
class GlassStat {
  final IconData icon;
  final String label;
  final String value;
  const GlassStat({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// 统计卡：横排若干项，项间细线分隔。
class GlassStatsCard extends StatelessWidget {
  final List<GlassStat> stats;
  const GlassStatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      live: false,
      opacity: kFrostAlpha,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) Container(width: 1, height: 40, color: kGlassGridLine),
            Expanded(
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(stats[i].icon, size: 15, color: kTextMuted),
                      const SizedBox(width: 4),
                      Text(
                        stats[i].label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: kTextMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    stats[i].value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
