// debug_log_page.dart —— 调试日志查看页（全局）。
//
// 按日志类型着色：HTTP 蓝、BIZ 绿、错误红，卡片式分行展示。
// 入口：首页中间区域 debug 滑动开关旁的"日志"胶囊。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/debug_log.dart';
import '../theme.dart';
import '../widgets/glass_background.dart';
import '../widgets/glass_card.dart';

class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});
  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = AppDebugLog.instance.isEnabled;
  }

  Future<void> _setEnabled(bool v) async {
    await AppDebugLog.instance.setEnabled(v);
    if (!mounted) return;
    setState(() => _enabled = v);
  }

  Future<void> _copy() async {
    final text = AppDebugLog.instance.read();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日志为空')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
    }
  }

  Future<void> _clear() async {
    await AppDebugLog.instance.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final logText = AppDebugLog.instance.read();
    final lines = logText.isEmpty
        ? <String>[]
        : logText.split('\n').where((l) => l.isNotEmpty).toList();

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── 顶部栏 ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: kPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Debug Log',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kInk,
                            ),
                          ),
                          Text(
                            'HTTP 请求 / 业务响应',
                            style: TextStyle(fontSize: 11.5, color: kTextMuted),
                          ),
                        ],
                      ),
                    ),
                    _BuildSwitch(active: _enabled, onChanged: _setEnabled),
                  ],
                ),
              ),
              // ── 操作按钮 ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('复制'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kPrimary,
                          side: BorderSide(
                            color: kPrimary.withValues(alpha: 0.5),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clear,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                        ),
                        label: const Text('清空'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB85450),
                          side: BorderSide(
                            color: const Color(0xFFB85450)
                                .withValues(alpha: 0.4),
                          ),
                          backgroundColor: Colors.white.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ── 日志列表（现代化着色卡片 + 滚动条） ─────────────
              Expanded(
                child: GlassCard(
                  radius: 18,
                  padding: const EdgeInsets.all(8),
                  live: false,
                  child: lines.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无日志\n开启 debug 开关后请求将实时显示',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kTextMuted,
                              fontSize: 12.5,
                              height: 1.6,
                            ),
                          ),
                        )
                      : Scrollbar(
                          thickness: 4,
                          radius: const Radius.circular(2),
                          child: ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.only(right: 4),
                            itemCount: lines.length,
                            itemBuilder: (_, i) {
                              final line = lines[lines.length - 1 - i];
                              return _LogCard(line: line);
                            },
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── 解析单条日志行，着色展示 ─────────────────────────────────
class _LogCard extends StatelessWidget {
  final String line;
  const _LogCard({required this.line});

  @override
  Widget build(BuildContext context) {
    // 解析格式: [HH:mm:ss] [TAG] message
    final match = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]\s*\[([^\]]+)\]\s*(.*)$')
        .firstMatch(line);
    final time = match?.group(1) ?? '';
    final tag = match?.group(2) ?? '';
    final msg = match?.group(3) ?? line;

    // 按 tag 着色
    Color tagColor;
    Color tagBg;
    if (tag.contains('ERROR') || tag.contains('FAIL')) {
      tagColor = const Color(0xFFB85450);
      tagBg = const Color(0xFFB85450).withValues(alpha: 0.1);
    } else if (tag.contains('BIZ')) {
      tagColor = const Color(0xFF4A7F4E); // 绿
      tagBg = const Color(0xFF4A7F4E).withValues(alpha: 0.08);
    } else if (tag.contains('HTTP') ||
        tag.contains('GET') ||
        tag.contains('POST')) {
      tagColor = const Color(0xFF3B6EAB); // 蓝
      tagBg = const Color(0xFF3B6EAB).withValues(alpha: 0.08);
    } else if (tag.contains('BODY') || tag.contains('HUISH')) {
      tagColor = const Color(0xFF7B5BA0); // 紫
      tagBg = const Color(0xFF7B5BA0).withValues(alpha: 0.08);
    } else {
      tagColor = kTextMuted;
      tagBg = Colors.grey.withValues(alpha: 0.06);
    }

    // msg 里 code=非0 标红
    final hasError =
        RegExp(r'code\s*[!=]=?\s*(?!0\b)[-9]').hasMatch(msg) ||
        msg.contains('失败') ||
        msg.contains('错误');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 上排：时间 + tag 胶囊
          Row(
            children: [
              Icon(
                tag.contains('GET') || tag.contains('HTTP')
                    ? Icons.arrow_forward_ios_rounded
                    : tag.contains('BIZ') || tag.contains('BODY')
                    ? Icons.business_center_rounded
                    : tag.contains('ERROR') || tag.contains('FAIL')
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                size: 11,
                color: tagColor,
              ),
              const SizedBox(width: 4),
              Text(
                time,
                style: TextStyle(
                  fontSize: 10,
                  color: kTextMuted.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: tagColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // 下排：消息
          SelectableText(
            msg,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: hasError ? const Color(0xFFB85450) : kInk,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// 滑动开关组件（和首页 _DebugSwitch 样式一致）
class _BuildSwitch extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;
  const _BuildSwitch({required this.active, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: active ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: active
              ? Colors.orange.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.5),
          border: Border.all(
            color: active
                ? Colors.orange.withValues(alpha: 0.6)
                : kPrimarySoft.withValues(alpha: 0.3),
          ),
        ),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.orange : kTextMuted,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.bug_report_rounded,
            size: 13,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}
