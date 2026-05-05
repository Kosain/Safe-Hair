class GuidelineModel {
  final String id;
  final String title;
  final String category;
  final String content;
  final String? imageUrl;
  final List<String> tips;

  GuidelineModel({
    required this.id,
    required this.title,
    required this.category,
    required this.content,
    this.imageUrl,
    this.tips = const [],
  });

  factory GuidelineModel.fromMap(Map<String, dynamic> map) {
    return GuidelineModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      category: map['category'] ?? 'General',
      content: map['content'] ?? '',
      imageUrl: map['imageUrl'] ?? map['image_url'],
      tips: List<String>.from(map['tips'] ?? []),
    );
  }
}
