import 'dart:math' as math;

/// Maps free-text [condition] lines from the API to a simple severity label for the issues table.
String scalpConditionSeverityLabel(String condition) {
  final s = condition.toLowerCase();
  if (s.contains('advanced') || s.contains('significant') || s.contains('substantial')) return 'High';
  if (s.contains('early thinning') || s.contains('moderate loss') || s.contains('meaningful')) return 'Moderate';
  if (s.contains('moderate')) return 'Moderate';
  if (s.contains('generally healthy') || s.contains('minimal')) return 'Low';
  if (s.contains('frontal view:')) return 'Moderate';
  return 'Moderate';
}

/// When a saved report still has legacy issue text but updated numeric scores, avoid showing
/// "Low" severity next to very high damage/fall.
String scalpSeverityWithMetricsGuard(
  String issueText,
  String persistedSeverity,
  int damagePct,
  int fallPct,
) {
  final label = persistedSeverity.trim();
  if (fallPct >= 85 || damagePct >= 74) return 'High';
  if (fallPct >= 72 || damagePct >= 62) return 'Moderate';
  if (label.isNotEmpty && label != 'AI detected') return label;
  return scalpConditionSeverityLabel(issueText);
}

/// Prefer API [conditions] + [recommendations] so the UI is not stuck on an old Firestore `issues` snapshot.
List<Map<String, dynamic>> scalpReportIssuesTableFromDoc(
  Map<String, dynamic> d,
  List<String> cleanedRecs,
  int damagePct,
  int fallPct,
) {
  final summary = (d['summary'] is Map) ? Map<String, dynamic>.from(d['summary'] as Map) : <String, dynamic>{};
  final conditions = List<String>.from(summary['conditions'] ?? const <String>[]);
  final loc = summary['viewOrientation']?.toString() ?? summary['view_orientation']?.toString() ?? 'Scalp';
  final conf = '${summary['estimateReliabilityPercent'] ?? summary['estimate_reliability_percent'] ?? ''}';

  if (conditions.isNotEmpty) {
    return [
      for (var i = 0; i < conditions.length; i++)
        {
          'issue': conditions[i],
          'severity': scalpConditionSeverityLabel(conditions[i]),
          'location': loc,
          'recommendation': scalpIssueRecommendationText(cleanedRecs, i, conditions.length),
          'confidencePct': conf,
        },
    ];
  }

  final parsed = <Map<String, dynamic>>[];
  final raw = d['issues'];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        parsed.add({
          'issue': e['issue']?.toString() ?? '',
          'severity': e['severity']?.toString() ?? '',
          'location': e['location']?.toString() ?? loc,
          'recommendation': e['recommendation']?.toString() ?? '',
          'confidencePct': e['confidencePct'] ?? e['confidence'] ?? conf,
        });
      }
    }
  }
  if (parsed.isEmpty) return [];

  if (cleanedRecs.isNotEmpty) {
    return [
      for (var i = 0; i < parsed.length; i++)
        {
          'issue': parsed[i]['issue'] ?? '',
          'severity': scalpSeverityWithMetricsGuard(
            parsed[i]['issue']?.toString() ?? '',
            parsed[i]['severity']?.toString() ?? '',
            damagePct,
            fallPct,
          ),
          'location': parsed[i]['location'] ?? loc,
          'recommendation': scalpIssueRecommendationText(cleanedRecs, i, parsed.length),
          'confidencePct': parsed[i]['confidencePct'] ?? conf,
        },
    ];
  }

  return [
    for (final row in parsed)
      {
        'issue': row['issue'] ?? '',
        'severity': scalpSeverityWithMetricsGuard(
          row['issue']?.toString() ?? '',
          row['severity']?.toString() ?? '',
          damagePct,
          fallPct,
        ),
        'location': row['location'] ?? loc,
        'recommendation': row['recommendation'] ?? '',
        'confidencePct': row['confidencePct'] ?? conf,
      },
  ];
}

/// Picks recommendation text for each detected issue row so the table is not
/// "the same first line" for every row. Single issue: join several tips; multiple issues: split list.
String scalpIssueRecommendationText(
  List<String> recs,
  int issueIndex,
  int issueCount,
) {
  if (recs.isEmpty) {
    return 'Consult a qualified hair specialist for advice tailored to you.';
  }
  final n = math.max(1, issueCount);
  if (n == 1) {
    final take = math.min(4, recs.length);
    return recs.take(take).join('; ');
  }
  final per = math.max(1, (recs.length / n).ceil());
  final start = issueIndex * per;
  if (start >= recs.length) return recs.last;
  final end = math.min(start + per, recs.length);
  return recs.sublist(start, end).join('; ');
}
