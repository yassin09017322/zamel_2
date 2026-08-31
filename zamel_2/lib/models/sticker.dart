class Sticker {
  final String id;
  final String packId;
  final String fileUrl;
  final String type;
  final bool enabled;

  Sticker({
    required this.id,
    required this.packId,
    required this.fileUrl,
    required this.type,
    required this.enabled,
  });

  factory Sticker.fromJson(Map<String, dynamic> json, String documentId) {
    return Sticker(
      id: documentId,
      packId: json['packId'] as String? ?? '',
      fileUrl: json['fileUrl'] as String? ?? '',
      type: json['type'] as String? ?? 'animated',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packId': packId,
      'fileUrl': fileUrl,
      'type': type,
      'enabled': enabled,
    };
  }
}
