import 'package:flutter/material.dart';
import '../services/sticker_service.dart';
import '../models/sticker_pack.dart';
import '../models/sticker.dart';

class StickerPicker extends StatefulWidget {
  final Function(String url) onStickerSelected;
  const StickerPicker({Key? key, required this.onStickerSelected}) : super(key: key);

  @override
  _StickerPickerState createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  final StickerService _service = StickerService();
  List<StickerPack> _packs = [];
  List<Sticker> _stickers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    _packs = await _service.getStickerPacks();
    if (_packs.isNotEmpty) {
      await _loadStickers(_packs.first.id);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStickers(String packId) async {
    setState(() => _isLoading = true);
    _stickers = await _service.getStickersByPack(packId);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _packs.isEmpty) return const Center(child: CircularProgressIndicator());
    
    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _packs.length,
            itemBuilder: (context, index) {
              return InkWell(
                onTap: () => _loadStickers(_packs[index].id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Text(
                    _packs[index].name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
                itemCount: _stickers.length,
                itemBuilder: (context, index) {
                  return InkWell(
                    onTap: () => widget.onStickerSelected(_stickers[index].fileUrl),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.network(_stickers[index].fileUrl),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }
}
