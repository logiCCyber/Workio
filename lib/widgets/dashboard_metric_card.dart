import 'package:flutter/material.dart';

class MetricRowData {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const MetricRowData({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });
}

class DashboardMetricCard extends StatelessWidget {
  final IconData topIcon;
  final Color topIconColor;

  /// Теперь используем их аккуратно:
  final String value; // большое значение (но нейтральное)
  final String title; // подпись сверху

  final List<Color> gradient;
  final List<MetricRowData> rows;

  /// можно выключить, если вообще не хочешь header
  final bool showHeader;

  const DashboardMetricCard({
    super.key,
    required this.topIcon,
    required this.topIconColor,
    required this.value,
    required this.title,
    required this.gradient,
    required this.rows,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        border: Border.all(color: Colors.white.withAlpha(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // верхняя иконка
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(topIcon, color: topIconColor, size: 18),
          ),

          if (showHeader) ...[
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                height: 1.05,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // капсулы (оставляем 3 как ты хочешь)
          ...rows.take(3).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MetricRow(r: r),
          )),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final MetricRowData r;
  const _MetricRow({required this.r});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(22)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: r.accent.withAlpha(38),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(r.icon, size: 16, color: r.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              r.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            r.value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
