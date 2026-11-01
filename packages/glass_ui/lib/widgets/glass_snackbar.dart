// widgets/glass_snackbar.dart —— 玻璃风顶部轻提示（OverlayEntry 实现，从顶部滑入）。

import 'package:flutter/material.dart';

import '../theme.dart';
import 'glass_card.dart';

OverlayEntry? _activeEntry;

/// 玻璃风格顶部轻提示：从屏幕顶部安全区下方向下滑入，3.5s 后自动滑出。
void showGlassSnackBar(BuildContext context, String message) {
  // 先移除旧的
  _activeEntry?.remove();
  _activeEntry = null;

  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (_) => _GlassSnackOverlay(
      message: message,
      onDismiss: () {
        if (_activeEntry != null) {
          _activeEntry!.remove();
          _activeEntry = null;
        }
      },
    ),
  );
  _activeEntry = entry;
  overlay.insert(entry);
}

class _GlassSnackOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;
  const _GlassSnackOverlay({required this.message, required this.onDismiss});

  @override
  State<_GlassSnackOverlay> createState() => _GlassSnackOverlayState();
}

class _GlassSnackOverlayState extends State<_GlassSnackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    // 插入后下一帧滑入
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
    // 3.2s 后滑出，滑出完再 dismiss
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      _ctrl.reverse();
      Future.delayed(const Duration(milliseconds: 260), () {
        widget.onDismiss();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) {
              return Transform.translate(
                offset: Offset(
                  0,
                  -50 * (1 - Curves.easeOut.transform(_ctrl.value)),
                ),
                child: Opacity(
                  opacity: _ctrl.value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: _GlassSnackCard(message: widget.message),
          ),
        ),
      ),
    );
  }
}

class _GlassSnackCard extends StatelessWidget {
  final String message;
  const _GlassSnackCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 16,
      live: false,
      opacity: kFrostAlpha,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 17, color: kPrimary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kTextMain,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
