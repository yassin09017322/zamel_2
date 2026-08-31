class CategoryModel {
  final String id;

  CategoryModel({
    required this.id,
  });

  factory CategoryModel.fromFirestore(Map<String, dynamic> data, {String? documentId}) {
    return CategoryModel(
      id: documentId?.isNotEmpty == true
          ? documentId!
          : data['id']?.toString() ?? '',
    );
  }
}
