import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_colors.dart';

class HairHealthMetricsGuideScreen extends StatelessWidget {
  const HairHealthMetricsGuideScreen({
    super.key,
    this.strength,
    this.scalp,
    this.damage,
    this.fall,
  });

  final int? strength;
  final int? scalp;
  final int? damage;
  final int? fall;

  static const _entries = <_MetricGuide>[
    _MetricGuide(
      title: 'Hair Strength',
      color: Color(0xFF59C6B0),
      summary: 'How resilient your hair shafts are against breakage and thinning.',
      details:
          'Safe Hair estimates hair strength from your scalp scan by looking at shaft thickness, elasticity, and visible breakage. '
          'A higher score means your hair is stronger and more resistant to everyday stress from brushing, styling, and washing.',
      higherIsBetter: true,
      tips: [
        'Use a gentle shampoo and avoid harsh daily heat styling.',
        'Include protein-friendly care if your score is below 60%.',
        'Repeat scans every few weeks to track improvement.',
      ],
    ),
    _MetricGuide(
      title: 'Scalp Health',
      color: Color(0xFFB76BCA),
      summary: 'The overall condition of the skin where your hair grows.',
      details:
          'This score reflects oil balance, dryness, flaking, redness, and signs of irritation on the scalp. '
          'A healthier scalp gives hair a better environment to grow and reduces itchiness or visible dandruff.',
      higherIsBetter: true,
      tips: [
        'Keep the scalp clean but not over-washed.',
        'Avoid heavy products if you notice buildup or oiliness.',
        'See a doctor if redness or soreness persists.',
      ],
    ),
    _MetricGuide(
      title: 'Hair Damage Level',
      color: Color(0xFF7B9ACD),
      summary: 'How much chemical, heat, or environmental stress your hair shows.',
      details:
          'Damage is detected from dryness, rough texture, split ends, and weakened areas visible in your scan. '
          'A lower score is better here — it means less visible damage and healthier-looking strands.',
      higherIsBetter: false,
      tips: [
        'Reduce frequent bleaching, coloring, and high-heat tools.',
        'Use conditioner and leave-in moisture for dry ends.',
        'Trim damaged ends regularly to prevent further splitting.',
      ],
    ),
    _MetricGuide(
      title: 'Hair Fall Risk',
      color: Color(0xFFB7BD56),
      summary: 'How likely you are to experience noticeable shedding or thinning soon.',
      details:
          'This combines thinning patterns, weak follicles, and scalp stress signals from your latest analysis. '
          'A lower score means lower short-term fall risk. Higher values suggest you may benefit from earlier care or a specialist visit.',
      higherIsBetter: false,
      tips: [
        'Avoid tight hairstyles that pull on the roots.',
        'Manage stress and maintain a balanced diet with enough protein.',
        'Book a consultation if your score stays above 70%.',
      ],
    ),
  ];

  int? _valueFor(String title) {
    switch (title) {
      case 'Hair Strength':
        return strength;
      case 'Scalp Health':
        return scalp;
      case 'Hair Damage Level':
        return damage;
      case 'Hair Fall Risk':
        return fall;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.textDark),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Hair health explained',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'These four scores come from your AI scalp scan. Use them together to understand your hair condition — not just one number in isolation.',
              style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textDark),
            ),
          ),
          const SizedBox(height: 16),
          ..._entries.map((entry) {
            final value = _valueFor(entry.title);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GuideCard(entry: entry, value: value),
            );
          }),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.entry, this.value});

  final _MetricGuide entry;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final idealHint = entry.higherIsBetter
        ? 'Higher is better'
        : 'Lower is better';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(color: entry.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.summary,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF666666), height: 1.35),
                    ),
                  ],
                ),
              ),
              if (hasValue) ...[
                const SizedBox(width: 8),
                Column(
                  children: [
                    Text(
                      '$value%',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: value!.clamp(0, 100) / 100,
                        strokeWidth: 3,
                        backgroundColor: entry.color.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation(entry.color),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              idealHint,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: entry.color),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            entry.details,
            style: const TextStyle(fontSize: 14, color: Color(0xFF4B4B4B), height: 1.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tips',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          ...entry.tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: entry.color, fontWeight: FontWeight.w700)),
                  Expanded(
                    child: Text(
                      tip,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF5A5A5A), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGuide {
  const _MetricGuide({
    required this.title,
    required this.color,
    required this.summary,
    required this.details,
    required this.higherIsBetter,
    required this.tips,
  });

  final String title;
  final Color color;
  final String summary;
  final String details;
  final bool higherIsBetter;
  final List<String> tips;
}
