import 'package:flutter/material.dart';

class AnimatedGreenDivider extends StatefulWidget {
  const AnimatedGreenDivider({super.key});

  @override
  State<AnimatedGreenDivider> createState() => _AnimatedGreenDividerState();
}

class _AnimatedGreenDividerState extends State<AnimatedGreenDivider>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _opacity = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          color: Colors.greenAccent,
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.6),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}
