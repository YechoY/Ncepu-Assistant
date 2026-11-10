// debug_log_page.dart —— 调试日志查看页（全局）。
//
// 按日志类型着色：HTTP 蓝、BIZ 绿、错误红，卡片式分行展示。
// 入口：首页中间区域 debug 滑动开关旁的"日志"胶囊。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';

import 'package:glass_ui/theme.dart';
import 'package:glass_ui/widgets/glass_background.dart';
import 'package:glass_ui/widgets/glass_card.dart';
import 'package:glass_ui/widgets/glass_snackbar.dart';

class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});
  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  late bool _enabled;
  final ScrollController _scroll = ScrollController();
  bool _firstJumpDone = false;

  @override
  void initState() {
    super.initState();
    _enabled = AppDebugLog.instance.isEnabled;
    AppDebugLog.instance.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    AppDebugLog.instance.removeListener(_onLogChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (!mounted) return;
    setState(() {});
    _jumpToBottomIfFollowing();
  }

  /// 用户本来就在底部附近时才跟随滚动，翻阅历史时不打扰。
  void _jumpToBottomIfFollowing() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 120) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  /// 首次进入直接定位到底部（最新日志）。
  void _jumpToBottomOnce() {
    if (_firstJumpDone) return;
    _firstJumpDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _setEnabled(bool v) async {
    await AppDebugLog.instance.setEnabled(v);
    if (!mounted) return;
    setState(() => _enabled = v);
  }

  Future<void> _copy() async {
    final text = AppDebugLog.instance.read();
    if (text.isEmpty) {
      showGlassSnackBar(context, '日志为空');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showGlassSnackBar(context, '已复制到剪贴板');
    }
  }

  Future<void> _clear() async {
    await AppDebugLog.instance.clear();
    if (mounted) setState(() {});
  }

  Future<void> _export() async {
    final text = AppDebugLog.instance.read();
    if (text.isEmpty) {
      showGlassSnackBar(context, '日志为空');
      return;
    }
    final now = DateTime.now();
    final fname =
        'debug_log_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.txt';
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getDownloadsDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();
      await File('${dir.path}/$fname').writeAsString(text, encoding: utf8);
      if (!mounted) return;
      showGlassSnackBar(context, '已保存到 Download/$fname\n用文件管理器打开可选择打开方式');
    } catch (_) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        await File('${dir.path}/$fname').writeAsString(text, encoding: utf8);
        if (!mounted) return;
        showGlassSnackBar(context, '已保存到 ${dir.path}/$fname');
      } catch (_) {
        if (!mounted) return;
        showGlassSnackBar(context, '导出失败');
      }
    }
  }

  /// 工具按钮：统一白玻璃小胶囊（朴素风格，不用彩色描边）。
  Widget _toolButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: kGlassBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: kTextMain.withValues(alpha: 0.75)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kTextMain.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                            '调试日志',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
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
              // ── 操作按钮（统一玻璃小胶囊） ──────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _toolButton(Icons.save_alt_rounded, '导出', _export),
                    const SizedBox(width: 8),
                    _toolButton(Icons.copy_rounded, '复制', _copy),
                    const SizedBox(width: 8),
                    _toolButton(Icons.delete_outline_rounded, '清空', _clear),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ── 日志列表（终端风格纯文本行 + 滚动条） ────────────
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
                          controller: _scroll,
                          thickness: 4,
                          radius: const Radius.circular(2),
                          child: Builder(
                            builder: (_) {
                              _jumpToBottomOnce();
                              return ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.only(right: 4),
                                itemCount: lines.length,
                                itemBuilder: (_, i) => _LogLine(
                                  line: lines[i],
                                  prevLine: i > 0 ? lines[i - 1] : null,
                                ),
                              );
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

/// ── 单条日志：纯文本行（时间 + tag 着色，消息等宽可选中） ──────────
/// 终端风格：无卡片无图标，行间仅用细分隔线。
/// 同一秒内的连续日志省略重复时间戳；HTTP 行的状态码按区间着色、query 淡化。
class _LogLine extends StatelessWidget {
  final String line;
  final String? prevLine;
  const _LogLine({required this.line, this.prevLine});

  static const _errColor = Color(0xFFB85450);
  static const _okColor = Color(0xFF4A7F4E);
  static const _redirectColor = Color(0xFF3B6EAB);

  /// 按模块/类型给 tag 着色（HUISH 蓝 / LAUNDRY 粉 / BIZ 绿 / 错误红）。
  static Color _tagColor(String tag) {
    if (tag.contains('ERROR') || tag.contains('FAIL')) {
      return _errColor;
    }
    if (tag.contains('BIZ')) return _okColor;
    if (tag.contains('LAUNDRY')) return kLaundryDeep;
    if (tag.contains('HUISH')) return kHuishDeep;
    if (tag.contains('HTTP') || tag.contains('GET') || tag.contains('POST')) {
      return _redirectColor;
    }
    return kTextMuted;
  }

  static String? _timeOf(String line) {
    final m = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]').firstMatch(line);
    return m?.group(1);
  }

  /// 渲染消息体：HTTP 完成行（METHOD path?query → status · 耗时）分段着色，
  /// 其他行（BIZ 等）整行按错误与否着色。
  static List<InlineSpan> _msgSpans(String msg, bool hasError) {
    final m = RegExp(r'^([A-Z]+)\s+(\S+)\s+→\s+(\d{3}|FAIL)(.*)$')
        .firstMatch(msg);
    if (m == null) {
      return [
        TextSpan(
          text: msg,
          style: TextStyle(color: hasError ? _errColor : kInk),
        ),
      ];
    }
    final method = m.group(1)!;
    final url = m.group(2)!;
    final status = m.group(3)!;
    final rest = m.group(4)!; // ' · 96ms'
    final qi = url.indexOf('?');
    final path = qi < 0 ? url : url.substring(0, qi);
    final query = qi < 0 ? '' : url.substring(qi);
    final code = int.tryParse(status);
    final statusColor = code == null || code >= 400
        ? _errColor
        : code >= 300
        ? _redirectColor
        : _okColor;
    final dim = TextStyle(color: kTextMuted.withValues(alpha: 0.55));
    return [
      TextSpan(
        text: '$method ',
        style: const TextStyle(fontWeight: FontWeight.w700, color: kInk),
      ),
      TextSpan(
        text: path,
        style: const TextStyle(color: kInk),
      ),
      if (query.isNotEmpty) TextSpan(text: query, style: dim),
      TextSpan(
        text: ' → $status',
        style: TextStyle(fontWeight: FontWeight.w700, color: statusColor),
      ),
      TextSpan(text: rest, style: dim),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 解析格式: [HH:mm:ss] [TAG] message
    final match = RegExp(r'^\[(\d{2}:\d{2}:\d{2})\]\s*\[([^\]]+)\]\s*(.*)$')
        .firstMatch(line);
    final time = match?.group(1) ?? '';
    final tag = match?.group(2) ?? '';
    final msg = match?.group(3) ?? line;

    // 与上一条同秒 → 时间位置留白对齐，减少重复噪音
    final sameSecond =
        prevLine != null && time.isNotEmpty && _timeOf(prevLine!) == time;

    // msg 里 code=非0 / FAIL / 失败 标红
    final hasError =
        tag.contains('ERROR') ||
        tag.contains('FAIL') ||
        msg.contains('→ FAIL') ||
        RegExp(r'code\s*[!=]=?\s*(?!0\b)[-9]').hasMatch(msg) ||
        msg.contains('失败') ||
        msg.contains('错误');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kGlassGridLine, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sameSecond ? ' ' * 8 : time,
                style: TextStyle(
                  fontSize: 10,
                  color: kTextMuted.withValues(alpha: 0.6),
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tag,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _tagColor(tag),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText.rich(
            TextSpan(children: _msgSpans(msg, hasError)),
            style: const TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              height: 1.4,
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
              ? kTextMain.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.5),
          border: Border.all(
            color: active
                ? kTextMain.withValues(alpha: 0.45)
                : kPrimarySoft.withValues(alpha: 0.3),
          ),
        ),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? kTextMain : kTextMuted,
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
