class StickerPack {
  final String id;
  final String name;
  final String coverUrl;
  final bool enabled;

  StickerPack({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.enabled,
  });

  factory StickerPack.fromJson(Map<String, dynamic> json, String documentId) {
    return StickerPack(
      id: documentId,
      name: json['name'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'coverUrl': coverUrl,
      'enabled': enabled,
    };
  }
}
