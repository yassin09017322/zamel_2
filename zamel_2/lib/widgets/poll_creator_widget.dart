import 'package:flutter/material.dart';

class PollCreatorWidget extends StatefulWidget {
  final Future<void> Function(String question, List<String> options) onCreate;

  const PollCreatorWidget({super.key, required this.onCreate});

  @override
  State<PollCreatorWidget> createState() => _PollCreatorWidgetState();
}

class _PollCreatorWidgetState extends State<PollCreatorWidget> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [TextEditingController(), TextEditingController()];
  bool _isCreating = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إضافة استطلاع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(labelText: 'ما السؤال؟'),
            ),
            const SizedBox(height: 8),
            ..._optionControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: 'الخيار ${index + 1}'),
                ),
              );
            }),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _optionControllers.add(TextEditingController());
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('إضافة خيار'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isCreating ? null : _submit,
              child: _isCreating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('نشر الاستطلاع'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final question = _questionController.text.trim();
    final options = _optionControllers.map((c) => c.text.trim()).where((v) => v.isNotEmpty).toList();
    if (question.isEmpty || options.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب سؤالاً وأدخل خيارين على الأقل')));
      return;
    }

    setState(() => _isCreating = true);
    try {
      await widget.onCreate(question, options);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر الاستطلاع')));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل نشر الاستطلاع')));
    } finally {
      setState(() => _isCreating = false);
    }
  }
}
