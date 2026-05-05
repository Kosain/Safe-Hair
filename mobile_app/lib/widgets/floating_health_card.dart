import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class FloatingHealthCard extends StatelessWidget {
  const FloatingHealthCard({super.key});

  static const List<_HealthMetric> _metrics = <_HealthMetric>[
    _HealthMetric(label: 'Hair Strength', value: 72, color: Color(0xFF59C6B0)),
    _HealthMetric(label: 'Scalp Health', value: 60, color: Color(0xFFB76BCA)),
    _HealthMetric(label: 'Hair Damage Level', value: 45, color: Color(0xFF7B9ACD)),
    _HealthMetric(label: 'Hair Fall Risk', value: 80, color: Color(0xFFB7BD56)),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF5A5A5A)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your hair health',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.textDark),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Last scan: Today',
                        style: TextStyle(fontSize: 13, color: Color(0xFF777777)),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: Color(0xFFE8E8E8), shape: BoxShape.circle),
                  child: const Icon(Icons.north_east_rounded, size: 18, color: Color(0xFF616161)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              itemCount: _metrics.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 7,
                crossAxisSpacing: 7,
                childAspectRatio: 1.88,
              ),
              itemBuilder: (context, index) => _MetricMiniCard(metric: _metrics[index]),
            ),
            const SizedBox(height: 10),
            const _ReminderCard(),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF1F1F1)),
            child: const Icon(Icons.notifications_none_rounded, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reminder', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                SizedBox(height: 2),
                Text(
                  'Today 10 AM\nApply Hair Organic Oil',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF666666), height: 1.2),
                ),
              ],
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: Color(0xFFE7EC74), shape: BoxShape.circle),
            child: const Icon(Icons.add_rounded, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

class _MetricMiniCard extends StatelessWidget {
  const _MetricMiniCard({required this.metric});

  final _HealthMetric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4B4B4B),
              height: 1.15,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${metric.value}%',
                    style: const TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  value: metric.value / 100,
                  strokeWidth: 3.3,
                  backgroundColor: metric.color.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation(metric.color),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthMetric {
  const _HealthMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}
