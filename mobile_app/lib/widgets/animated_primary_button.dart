import 'package:flutter/material.dart';

/// A reusable "advanced" button with gradient sweep + glow on press.
class AnimatedPrimaryButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double height;
  final double borderRadius;
  final List<Color> gradientColors;

  const AnimatedPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 52,
    this.borderRadius = 16,
    this.gradientColors = const [Color(0xFF2DD4BF), Color(0xFF16A34A)],
  });

  @override
  State<AnimatedPrimaryButton> createState() => _AnimatedPrimaryButtonState();
}

class _AnimatedPrimaryButtonState extends State<AnimatedPrimaryButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.onPressed == null) return;
    _controller.forward();
  }

  void _release() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        final glow = 18 * v;
        final scale = 1.0 - (0.02 * v);
        final alignmentX = -1 + (2 * v);

        return Transform.scale(
          scale: scale,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: widget.onPressed == null ? Colors.transparent : Colors.green.withOpacity(0.25),
                  blurRadius: glow,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                onTapDown: (_) => _press(),
                onTapCancel: _release,
                onTapUp: (_) => _release(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(alignmentX, 0),
                        end: Alignment(alignmentX + 1.2, 0),
                        colors: widget.gradientColors,
                      ),
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

