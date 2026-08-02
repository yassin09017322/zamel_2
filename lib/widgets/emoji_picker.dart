import 'dart:async';
import 'package:flutter/material.dart';
import '../services/local_storage_service.dart';

typedef EmojiSelected = void Function(String emoji);

class EmojiPicker extends StatefulWidget {
  final EmojiSelected onEmojiSelected;
  final int recentLimit;

  const EmojiPicker({super.key, required this.onEmojiSelected, this.recentLimit = 40});

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> with SingleTickerProviderStateMixin {
  static const _storageKey = 'emoji_picker_recent';

  late final AnimationController _anim;
  late final Animation<Offset> _offsetAnim;
  late final Animation<double> _fadeAnim;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _selectedCategory = 0; // 0 = Recent

  List<String> _recent = [];

  static const Map<String, List<String>> _categories = {
    'Smileys': [
      '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😙','😚','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤮','🤧','🥵','🥶','🥴','😵','🤯','😎','🥳','🤓','🧐','😕','😟','🙁','☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞','😓','😩','😫','🥱','😤','😡','😠','🤬','😈','👿','💀','☠️','👻','👽','👾','🤖',
      '👋','🤚','🖐️','✋','🖖','👌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','✋','👏','🙌','👐','🤲','🤝','🙏','👍','👎','✊','👊','🤛','🤜',
      '👶','🧒','👦','👧','🧑','👱‍♀️','👱‍♂️','👨','👩','🧓','👴','👵','👨‍👩‍👦','👨‍👩‍👧','👨‍👩‍👧‍👦','👩‍👩‍👦','👨‍👨‍👦','👩‍👦','👨‍👦','👩‍👧','👨‍👧','👨‍👩‍👦‍👦','👨‍👩‍👧‍👧','👩‍👩‍👧‍👦','👨‍👨‍👧‍👧','👩‍🦱','👨‍🦱','👩‍🦰','👨‍🦰','👩‍🦳','👨‍🦳','👩‍🦲','👨‍🦲','👮‍♀️','👮‍♂️','👷‍♀️','👷‍♂️','💂‍♀️','💂‍♂️','🕵️‍♀️','🕵️‍♂️','👩‍⚕️','👨‍⚕️','👩‍🎓','👨‍🎓','👩‍🏫','👨‍🏫','👩‍⚖️','👨‍⚖️','👩‍🌾','👨‍🌾','👩‍🍳','👨‍🍳','👩‍🎤','👨‍🎤','👩‍🎨','👨‍🎨','👩‍✈️','👨‍✈️','👩‍🚀','👨‍🚀','👩‍🚒','👨‍🚒','👩‍🔧','👨‍🔧','👩‍🏭','👨‍🏭','👩‍💼','👨‍💼','👩‍🔬','👨‍🔬','👩‍💻','👨‍💻','👩‍🎓','👨‍🎓','👩‍⚕️','👨‍⚕️','🧑‍⚕️','🧑‍🎓','🧑‍🏫','🧑‍⚖️','🧑‍🍳','🧑‍🎤','🧑‍🎨','🧑‍✈️','🧑‍🚀','🧑‍🚒','🧑‍🔧','🧑‍🏭','🧑‍💼','🧑‍🔬','🧑‍💻',
      '👍🏻','👍🏼','👍🏽','👍🏾','👍🏿','👎🏻','👎🏼','👎🏽','👎🏾','👎🏿','👋🏻','👋🏼','👋🏽','👋🏾','👋🏿','👏🏻','👏🏼','👏🏽','👏🏾','👏🏿','🙌🏻','🙌🏼','🙌🏽','🙌🏾','🙌🏿','🙏🏻','🙏🏼','🙏🏽','🙏🏾','🙏🏿','🤝🏻','🤝🏼','🤝🏽','🤝🏾','🤝🏿',
      '🧑🏻‍⚕️','🧑🏼‍⚕️','🧑🏽‍⚕️','🧑🏾‍⚕️','🧑🏿‍⚕️','👩🏻‍⚕️','👩🏼‍⚕️','👩🏽‍⚕️','👩🏾‍⚕️','👩🏿‍⚕️','👨🏻‍⚕️','👨🏼‍⚕️','👨🏽‍⚕️','👨🏾‍⚕️','👨🏿‍⚕️','👩🏻‍🔧','👩🏼‍🔧','👩🏽‍🔧','👩🏾‍🔧','👩🏿‍🔧','👨🏻‍🔧','👨🏼‍🔧','👨🏽‍🔧','👨🏾‍🔧','👨🏿‍🔧','🧑🏻‍🔧','🧑🏼‍🔧','🧑🏽‍🔧','🧑🏾‍🔧','🧑🏿‍🔧',
    ],
    'Animals': ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵'],
    'Food': ['🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🍒','🍑','🍍','🥭','🍔','🍟','🍕'],
    'Activities': ['⚽','🏀','🏈','🎾','🎲','🏓','🎳','🎯','🏆','🎮','🕹️'],
    'Travel': ['🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','✈️','🚀','⛵','🚢'],
    'Objects': ['⌚','📱','💻','🖥️','🖨️','📷','🎥','🔦','💡','🔑','📌','📎'],
    'Symbols': ['❤️','💔','💕','✨','🔥','⭐','✅','❌','➕','➖','⚠️','🔔'],
    'Flags': ['🏳️','🏴','🏁','🇺🇸','🇬🇧','🇪🇸','🇫🇷','🇩🇪','🇮🇳','🇸🇦','🇦🇪']
  };

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _offsetAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _loadRecent();
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final svc = LocalStorageService();
    final data = await svc.getValue<List<dynamic>>(_storageKey);
    if (data != null) {
      setState(() => _recent = data.cast<String>().toList());
    }
  }

  Future<void> _saveRecent(String emoji) async {
    _recent.removeWhere((e) => e == emoji);
    _recent.insert(0, emoji);
    if (_recent.length > widget.recentLimit) _recent = _recent.sublist(0, widget.recentLimit);
    final svc = LocalStorageService();
    await svc.setValue(_storageKey, _recent);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      setState(() => _query = v.trim());
    });
  }

  List<String> _filteredForCategory(int idx) {
    if (idx == 0) return _recent;
    final key = _categories.keys.elementAt(idx - 1);
    final list = _categories[key] ?? <String>[];
    if (_query.isEmpty) return list;
    return list.where((e) => e.contains(_query) || _emojiNameMatches(e, _query)).toList();
  }

  bool _emojiNameMatches(String emoji, String q) {
    // lightweight fallback: match by codepoint substring
    return emoji.runes.map((r) => r.toString()).join().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surface;

    final tabs = ['Recent', ..._categories.keys];

    final currentList = _filteredForCategory(_selectedCategory);

    return SlideTransition(
      position: _offsetAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          height: 320,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -6))],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'بحث عن إيموجي',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.backspace_outlined),
                      onPressed: () {
                        widget.onEmojiSelected('\u{0008}'); // signal to delete
                      },
                    ),
                  ],
                ),
              ),
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabs.length,
                  itemBuilder: (ctx, i) {
                    final selected = i == _selectedCategory;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedCategory = i;
                        _query = '';
                        _searchController.clear();
                      }),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? theme.colorScheme.primary : theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? theme.colorScheme.primary : Colors.transparent),
                        ),
                        child: Center(
                          child: Text(
                            tabs[i],
                            style: TextStyle(
                              color: selected
                                  ? theme.colorScheme.onPrimary
                                  : theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, childAspectRatio: 1, mainAxisSpacing: 6, crossAxisSpacing: 6),
                    itemCount: currentList.length,
                    itemBuilder: (ctx, idx) {
                      final e = currentList[idx];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            await _saveRecent(e);
                            widget.onEmojiSelected(e);
                          },
                          child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
