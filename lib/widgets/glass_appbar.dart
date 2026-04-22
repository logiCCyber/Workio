import 'dart:ui';
import 'package:flutter/material.dart';

class GlassAppBarTitle extends StatelessWidget {
  final Widget? leading;                 // слева (например back)
  final IconData? titleIcon;             // иконка рядом с текстом
  final String title;                    // заголовок
  final List<Widget> actions;            // кнопки справа
  final double blur;                     // сила блюра (как в Worker details)
  final double heightExtra;              // +10 как у тебя

  const GlassAppBarTitle({
    super.key,
    this.leading,
    this.titleIcon,
    required this.title,
    this.actions = const [],
    this.blur = 18,
    this.heightExtra = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: Stack(
        children: [
          // 1) BLUR
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(),
          ),

          // 2) GLASS PANEL
          Container(
            height: kToolbarHeight + heightExtra,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.14),
                  Colors.white.withOpacity(0.06),
                  Colors.black.withOpacity(0.22),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.12),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  // LEFT: leading (optional)
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 6),
                  ],

                  // TITLE ICON (optional)
                  if (titleIcon != null) ...[
                    Icon(titleIcon, size: 18, color: Colors.white70),
                    const SizedBox(width: 10),
                  ],

                  // TITLE TEXT
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ),

                  // RIGHT: actions
                  ...actions,
                ],
              ),
            ),
          ),

          // 3) TOP HIGHLIGHT LINE
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
