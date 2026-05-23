/// Merges nested API shapes (`analysis`, `metrics`, report `summary`) into one map.
Map<String, dynamic> normalizeScalpApiResponse(Map<String, dynamic> raw) {
  final out = Map<String, dynamic>.from(raw);
  void merge(Map<String, dynamic>? m) {
    if (m == null) return;
    for (final e in m.entries) {
      if (e.value != null) out[e.key] = e.value;
    }
  }

  if (raw['analysis'] is Map) {
    merge(Map<String, dynamic>.from(raw['analysis'] as Map));
  }
  if (raw['metrics'] is Map) {
    merge(Map<String, dynamic>.from(raw['metrics'] as Map));
  }
  final report = raw['report'];
  if (report is Map) {
    if (report['summary'] is Map) {
      merge(Map<String, dynamic>.from(report['summary'] as Map));
    }
    merge(Map<String, dynamic>.from(report));
  }
  return out;
}

num? scalpApiNum(Map<String, dynamic> api, List<String> keys) {
  for (final k in keys) {
    final v = api[k];
    if (v is num) return v;
  }
  return null;
}
