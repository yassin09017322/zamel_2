import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';

class StickerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // جلب حزم الملصقات المفعلة فقط
  Future<List<StickerPack>> getStickerPacks() async {
    var snapshot = await _db
        .collection('sticker_packs')
        .where('enabled', isEqualTo: true)
        .get();
    
    return snapshot.docs
        .map((doc) => StickerPack.fromJson(doc.data(), doc.id))
        .toList();
  }

  // جلب الملصقات التابعة لحزمة محددة
  Future<List<Sticker>> getStickersByPack(String packId) async {
    var snapshot = await _db
        .collection('stickers')
        .where('packId', isEqualTo: packId)
        .where('enabled', isEqualTo: true)
        .get();
        
    return snapshot.docs
        .map((doc) => Sticker.fromJson(doc.data(), doc.id))
        .toList();
  }
}
