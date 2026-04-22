import 'dart:ui';
import 'package:flutter/material.dart';

class AppToast {
  static void success(BuildContext context, String text) {
    _show(context, text,
        icon: Icons.check_circle_rounded,
        accent: const Color(0xFF34D399) // AppPalette.green
    );
  }

  static void error(BuildContext context, String text) {
    _show(context, text,
        icon: Icons.error_rounded,
        accent: const Color(0xFFFB7185) // AppPalette.red/pink
    );
  }

  static void info(BuildContext context, String text) {
    _show(context, text,
        icon: Icons.info_rounded,
        accent: const Color(0xFF38BDF8) // AppPalette.blue
    );
  }

  static void _show(
      BuildContext context,
      String text, {
        required IconData icon,
        required Color accent,
      }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: EdgeInsets.zero,
        content: _GlassToast(
          text: text,
          icon: icon,
          accent: accent,
        ),
      ),
    );
  }
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
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2F3036).withOpacity(0.86),
                const Color(0xFF24252B).withOpacity(0.84),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: accent.withOpacity(0.14),
                blurRadius: 26,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.2,
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
