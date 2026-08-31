import 'package:firebase_storage/firebase_storage.dart';


class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static Future<String> uploadMedia({
    required dynamic file,
    required String destinationPath,
  }) async {
    final ref = _storage.ref(destinationPath);
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }

  static String getFileExtension(String path) {
    final index = path.lastIndexOf('.');
    if (index == -1) return 'dat';
    return path.substring(index + 1);
  }
}
