import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

class FadeSlideIn extends StatefulWidget {
  final Widget child;

  const FadeSlideIn({
    super.key,
    required this.child,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _play() {
    if (!_played) {
      _played = true;
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey(widget.child.hashCode),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.15) {
          _play();
        }
      },
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (_, child) {
          return Opacity(
            opacity: _animation.value,
            child: Transform.translate(
              offset: Offset(0, (1 - _animation.value) * 24),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
