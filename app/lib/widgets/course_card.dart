import 'package:flutter/material.dart';

import '../models/course_cell.dart';
import '../theme.dart';
import 'glass_card.dart';
import 'mac_card.dart';

class CourseCard extends StatelessWidget {
  final CourseCell cell;

  /// 页面层做过「按天冲突消解」后的颜色；不传则按课程名哈希兜底。
  final ({Color bg, Color border, Color name})? color;
  const CourseCard({super.key, required this.cell, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? courseColor(cell.name);
    return MacCard(
      radius: 12,
      background: c.bg,
      accent: c.border, // 左侧强调条用该课配色的边框色
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: () => showDialog(
        context: context,
        barrierColor: const Color(0x402E3350),
        builder: (_) => _CourseDetailDialog(cell: cell),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cell.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c.name,
              height: 1.15,
            ),
          ),
          if (cell.location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                cell.location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF44515F),
                  height: 1.1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CourseDetailDialog extends StatelessWidget {
  final CourseCell cell;
  const _CourseDetailDialog({required this.cell});

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v) => Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kGlassGridLine)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 12, color: kTextMuted)),
          Text(
            v,
            style: const TextStyle(
              fontSize: 12,
              color: kTextMain,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 34),
      child: GlassCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cell.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: kTextMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            row('上课时间', cell.time),
            row('上课地点', cell.location),
            row('课程学分', cell.credits),
            row('课程属性', cell.attr),
          ],
        ),
      ),
    );
  }
}
