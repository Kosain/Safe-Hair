int? _nullableInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse(v.toString());
}

String? _nullableString(dynamic v) {
  if (v == null) return null;
  return v.toString();
}

class ScalpAnalysisModel {
  final String id;
  final String userId;
  final String? imageUrl;
  final double hairStrength;
  final double scalpHealth;
  final double hairDensity;
  final double moistureLevel;
  final List<String> conditions;
  final List<String> recommendations;
  final DateTime createdAt;
  /// Bald area in cm² (from OpenCV/CNN).
  final double? baldAreaCm2;
  /// Vertex view: slick bald skin only (cm²).
  final double? baldOnlyCm2;
  /// Vertex view: thinning band (cm²).
  final double? thinAreaCm2;
  /// Estimated graft count range (min).
  final int? graftMin;
  /// Estimated graft count range (max).
  final int? graftMax;
  /// Bald region ratio 0–1 (from detection).
  final double? baldRatio;
  /// Processed image with bald area overlay (base64).
  final String? overlayImageBase64;
  /// Hair-bearing area in cm² (visible crop).
  final double? hairAreaCm2;
  /// Estimated hairs on visible hair region (min / max range).
  final int? estimatedHairCountMin;
  final int? estimatedHairCountMax;
  final int? estimatedHairCount;
  /// How bald vs hair was segmented: `opencv`, `opencv_frontal`, or `cnn`.
  final String? segmentationMethod;
  final String? hairCountNote;
  /// `front` (hairline / selfie) vs `top` (vertex) — from backend heuristic.
  final String? viewOrientation;
  /// One-line consolidated report from the API (view, area, grafts, scores).
  final String? analysisSummary;
  /// Backend heuristic 18–92; not a formal confidence interval.
  final int? estimateReliabilityPercent;
  /// Short legal/clinical disclaimer for graft and area estimates.
  final String? estimateDisclaimer;

  ScalpAnalysisModel({
    required this.id,
    required this.userId,
    this.imageUrl,
    required this.hairStrength,
    required this.scalpHealth,
    this.hairDensity = 0,
    this.moistureLevel = 0,
    this.conditions = const [],
    this.recommendations = const [],
    required this.createdAt,
    this.baldAreaCm2,
    this.baldOnlyCm2,
    this.thinAreaCm2,
    this.graftMin,
    this.graftMax,
    this.baldRatio,
    this.overlayImageBase64,
    this.hairAreaCm2,
    this.estimatedHairCountMin,
    this.estimatedHairCountMax,
    this.estimatedHairCount,
    this.segmentationMethod,
    this.hairCountNote,
    this.viewOrientation,
    this.analysisSummary,
    this.estimateReliabilityPercent,
    this.estimateDisclaimer,
  });

  factory ScalpAnalysisModel.fromMap(Map<String, dynamic> map) {
    return ScalpAnalysisModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? map['user_id'] ?? '',
      imageUrl: map['imageUrl'] ?? map['image_url'],
      hairStrength: (map['hairStrength'] ?? map['hair_strength'] ?? 0).toDouble(),
      scalpHealth: (map['scalpHealth'] ?? map['scalp_health'] ?? 0).toDouble(),
      hairDensity: (map['hairDensity'] ?? map['hair_density'] ?? 0).toDouble(),
      moistureLevel: (map['moistureLevel'] ?? map['moisture_level'] ?? 0).toDouble(),
      conditions: List<String>.from(map['conditions'] ?? []),
      recommendations: List<String>.from(map['recommendations'] ?? []),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      baldAreaCm2: (map['bald_area_cm2'] ?? map['baldAreaCm2']) != null
          ? (map['bald_area_cm2'] ?? map['baldAreaCm2']).toDouble()
          : null,
      baldOnlyCm2: (map['bald_only_cm2'] ?? map['baldOnlyCm2']) != null
          ? (map['bald_only_cm2'] ?? map['baldOnlyCm2']).toDouble()
          : null,
      thinAreaCm2: (map['thin_area_cm2'] ?? map['thinAreaCm2']) != null
          ? (map['thin_area_cm2'] ?? map['thinAreaCm2']).toDouble()
          : null,
      graftMin: _nullableInt(map['graft_min'] ?? map['graftMin']),
      graftMax: _nullableInt(map['graft_max'] ?? map['graftMax']),
      baldRatio: (map['bald_ratio'] ?? map['baldRatio']) != null
          ? (map['bald_ratio'] ?? map['baldRatio']).toDouble()
          : null,
      overlayImageBase64: map['overlay_image_base64'] ?? map['overlayImageBase64'],
      hairAreaCm2: (map['hair_area_cm2'] ?? map['hairAreaCm2']) != null
          ? (map['hair_area_cm2'] ?? map['hairAreaCm2']).toDouble()
          : null,
      estimatedHairCountMin: _nullableInt(map['estimated_hair_count_min'] ?? map['estimatedHairCountMin']),
      estimatedHairCountMax: _nullableInt(map['estimated_hair_count_max'] ?? map['estimatedHairCountMax']),
      estimatedHairCount: _nullableInt(map['estimated_hair_count'] ?? map['estimatedHairCount']),
      segmentationMethod: _nullableString(map['segmentation_method'] ?? map['segmentationMethod']),
      hairCountNote: _nullableString(map['hair_count_note'] ?? map['hairCountNote']),
      viewOrientation: _nullableString(map['view_orientation'] ?? map['viewOrientation']),
      analysisSummary: _nullableString(map['analysis_summary'] ?? map['analysisSummary']),
      estimateReliabilityPercent: _nullableInt(map['estimate_reliability_percent'] ?? map['estimateReliabilityPercent']),
      estimateDisclaimer: _nullableString(map['estimate_disclaimer'] ?? map['estimateDisclaimer']),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'imageUrl': imageUrl,
        'hairStrength': hairStrength,
        'scalpHealth': scalpHealth,
        'hairDensity': hairDensity,
        'moistureLevel': moistureLevel,
        'conditions': conditions,
        'recommendations': recommendations,
        'createdAt': createdAt.toIso8601String(),
        if (baldAreaCm2 != null) 'baldAreaCm2': baldAreaCm2,
        if (baldOnlyCm2 != null) 'baldOnlyCm2': baldOnlyCm2,
        if (thinAreaCm2 != null) 'thinAreaCm2': thinAreaCm2,
        if (graftMin != null) 'graftMin': graftMin,
        if (graftMax != null) 'graftMax': graftMax,
        if (baldRatio != null) 'baldRatio': baldRatio,
        if (overlayImageBase64 != null) 'overlay_image_base64': overlayImageBase64,
        if (hairAreaCm2 != null) 'hairAreaCm2': hairAreaCm2,
        if (estimatedHairCountMin != null) 'estimatedHairCountMin': estimatedHairCountMin,
        if (estimatedHairCountMax != null) 'estimatedHairCountMax': estimatedHairCountMax,
        if (estimatedHairCount != null) 'estimatedHairCount': estimatedHairCount,
        if (segmentationMethod != null) 'segmentationMethod': segmentationMethod,
        if (hairCountNote != null) 'hairCountNote': hairCountNote,
        if (viewOrientation != null) 'viewOrientation': viewOrientation,
        if (analysisSummary != null) 'analysisSummary': analysisSummary,
        if (estimateReliabilityPercent != null) 'estimateReliabilityPercent': estimateReliabilityPercent,
        if (estimateDisclaimer != null) 'estimateDisclaimer': estimateDisclaimer,
      };
}
