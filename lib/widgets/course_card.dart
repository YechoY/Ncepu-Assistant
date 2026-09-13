import 'package:flutter/material.dart';

import '../models/course_cell.dart';
import '../theme.dart';
import 'mac_card.dart';

class CourseCard extends StatelessWidget {
  final CourseCell cell;
  const CourseCard({super.key, required this.cell});

  @override
  Widget build(BuildContext context) {
    final c = courseColor(cell.name);
    return MacCard(
      radius: 12,
      background: c.bg,
      accent: c.border, // 左侧强调条用该课配色的边框色
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: () => showDialog(
        context: context,
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
        border: Border(top: BorderSide(color: Color(0xFFEEF2F9))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            k,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          Text(
            v,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
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
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF6B7280),
                  ),
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
