import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_keys.dart'; // где rootMessengerKey

class AppToast {
  static void show(
      String text, {
        IconData icon = Icons.info_rounded,
        Color accent = const Color(0xFF38BDF8), // blue
        Duration duration = const Duration(seconds: 2),
      }) {
    final ms = rootMessengerKey.currentState;
    if (ms == null) return;

    ms.hideCurrentSnackBar();

    ms.showSnackBar(
      SnackBar(
        duration: duration,
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        content: _GlassToast(text: text, icon: icon, accent: accent),
      ),
    );
  }

  static void success(String text) =>
      show(text, icon: Icons.check_circle_rounded, accent: const Color(0xFF34D399));

  static void warning(String text) =>
      show(text, icon: Icons.warning_rounded, accent: const Color(0xFFF59E0B));

  static void error(String text) =>
      show(text, icon: Icons.error_rounded, accent: const Color(0xFFFB7185));
}

class _GlassToast extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color accent;

  const _GlassToast({
    required this.text,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2F3036).withOpacity(0.92),
                const Color(0xFF24252B).withOpacity(0.90),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.22)),
                ),
                child: Icon(icon, color: accent.withOpacity(0.95), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.90),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
