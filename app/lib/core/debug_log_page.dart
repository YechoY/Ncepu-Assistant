// debug_log_page.dart —— 调试日志查看页（全局）。
//
// 功能：开关 / 实时日志流 / 复制 / 清空。
// 入口：ModuleNavPage 上的版本号暗门（点击 vX.Y.Z 即可进入）。

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
  final _scrollCtrl = ScrollController();
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    _enabled = AppDebugLog.instance.isEnabled;
    _tick();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    // 每秒刷新一次（简单轮询，16000 字符缓冲够用，不必复杂）
    while (mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _lastRefresh = DateTime.now());
      // 自动滚到底
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    }
  }

  Future<void> _setEnabled(bool v) async {
    await AppDebugLog.instance.setEnabled(v);
    if (!mounted) return;
    setState(() => _enabled = v);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(v ? '调试日志已开启，所有 HTTP 请求将被记录' : '调试日志已暂停记录（已记录的内容仍保留）'),
        ),
      );
    }
  }

  Future<void> _copy() async {
    final text = AppDebugLog.instance.read();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日志为空，无需复制')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('将清空所有已记录的调试日志，确定？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppDebugLog.instance.clear();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final logText = AppDebugLog.instance.read();
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
                            '调试日志',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kInk,
                            ),
                          ),
                          Text(
                            'App 级 HTTP 请求记录',
                            style: TextStyle(fontSize: 11.5, color: kTextMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 开关 + 操作栏
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: GlassCard(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _enabled
                            ? Icons.bug_report_rounded
                            : Icons.bug_report_outlined,
                        size: 18,
                        color: _enabled ? Colors.orange : kTextMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _enabled ? '日志记录中' : '日志已关闭',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _enabled ? Colors.orange : kTextMuted,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _enabled,
                        onChanged: _setEnabled,
                        activeColor: Colors.orange,
                      ),
                    ],
                  ),
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
                        label: const Text('复制全部'),
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
                        label: const Text('清空日志'),
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
              // 日志流
              Expanded(
                child: GlassCard(
                  radius: 18,
                  padding: const EdgeInsets.all(14),
                  live: false,
                  child: logText.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无日志\n开启开关后 HTTP 请求将实时显示在此',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: kTextMuted,
                              fontSize: 12.5,
                              height: 1.6,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          controller: _scrollCtrl,
                          child: SelectableText(
                            logText,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              color: kInk,
                              height: 1.45,
                            ),
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
