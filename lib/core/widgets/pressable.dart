import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a tappable target with immediate touch feedback: a subtle scale-down
/// and dim while the finger is down, a light haptic on touch, and visual spring
/// back on release. Use for small icon buttons and chip-like targets where an
/// MechanicalInk splash would disappear.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const Pressable({super.key, required this.child, this.onTap});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  static const _feedbackDuration = Duration(milliseconds: 120);
  static const _pressedScale = 0.92;
  static const _pressedOpacity = 0.6;

  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return GestureDetector(
      onTapDown: enabled
          ? (_) {
              HapticFeedback.lightImpact();
              _setPressed(true);
            }
          : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? _pressedScale : 1.0,
        duration: _feedbackDuration,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? _pressedOpacity : 1.0,
          duration: _feedbackDuration,
          child: widget.child,
        ),
      ),
    );
  }
}
