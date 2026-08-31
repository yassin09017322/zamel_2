import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/category_model.dart';

class CategoryService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<List<CategoryModel>> fetchCategories() async {
    final snapshot = await _firestore.collection('content_categories').get();
    return snapshot.docs
        .map((doc) => CategoryModel.fromFirestore(doc.data(), documentId: doc.id))
        .where((item) => item.id.isNotEmpty)
        .toList();
  }
}
