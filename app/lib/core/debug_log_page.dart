// debug_log_page.dart —— 调试日志查看页（全局）。
//
// 功能：滑动开关 / 实时日志流 / 复制 / 清空。
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
    // 每秒刷新读取最新日志（setState 触发 rebuild）
    final logText = AppDebugLog.instance.read();
    final lines = logText.isEmpty
        ? <String>[]
        : logText.split('\n').where((l) => l.isNotEmpty).toList();

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
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
                    // 滑动开关（和首页同步）
                    _BuildSwitch(active: _enabled, onChanged: _setEnabled),
                  ],
                ),
              ),
              // 操作按钮
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
              // 日志流（reverse: 最新在底部，自动滚动）
              Expanded(
                child: GlassCard(
                  radius: 18,
                  padding: const EdgeInsets.all(10),
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
                      : ListView.builder(
                          reverse: true,
                          itemCount: lines.length,
                          itemBuilder: (_, i) {
                            // reverse 后 i=0 是最新，倒序显示
                            final line = lines[lines.length - 1 - i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: SelectableText(
                                line,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: kInk,
                                  height: 1.4,
                                ),
                              ),
                            );
                          },
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
          child: Text(
            'D',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
