import 'package:flutter/material.dart';

enum WorktimeModalType { success, error, warning }

class WorktimeModal {
  static Future<void> show(
      BuildContext context, {
        required WorktimeModalType type,
        required String title,
        required String message,
        String buttonText = 'OK',
      }) async {
    final theme = Theme.of(context);

    // Цвета под твой стиль (dark + neon)
    final Color accent = switch (type) {
      WorktimeModalType.success => const Color(0xFF2CFF8F),
      WorktimeModalType.warning => const Color(0xFFFFC857),
      WorktimeModalType.error => const Color(0xFFFF4D4D),
    };

    final IconData icon = switch (type) {
      WorktimeModalType.success => Icons.check_circle_rounded,
      WorktimeModalType.warning => Icons.hourglass_bottom_rounded,
      WorktimeModalType.error => Icons.error_rounded,
    };

    // Можно bottom sheet (выглядит как iOS/modern)
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF111827),
                    Color(0xFF0B1220),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.55),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // маленький хэндл сверху
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Иконка
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withOpacity(0.12),
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Icon(icon, color: accent, size: 30),
                    ),
                    const SizedBox(height: 14),

                    // Заголовок
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Текст
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.92),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Кнопка (можешь заменить на свой зеленый gradient)
                    SizedBox(
                      width: double.infinity,
                      child: _GradientButton(
                        text: buttonText,
                        onTap: () => Navigator.of(context).pop(),
                        // если успех — зелёный градиент, если ошибка — красный, если варнинг — жёлтый
                        colors: switch (type) {
                          WorktimeModalType.success => const [
                            Color(0xFF6CFF8D),
                            Color(0xFF2E7D32),
                          ],
                          WorktimeModalType.warning => const [
                            Color(0xFFFFD166),
                            Color(0xFFB8860B),
                          ],
                          WorktimeModalType.error => const [
                            Color(0xFFFF6B6B),
                            Color(0xFFB00020),
                          ],
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final List<Color> colors;

  const _GradientButton({
    required this.text,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
