import 'dart:async';
import 'dart:typed_data';

import 'dart:html' as html;

class WebAudioRecorder {
  static html.MediaRecorder? _recorder;
  static final List<Uint8List> _chunks = <Uint8List>[];

  static Future<void> start() async {
    final stream = await html.window.navigator.mediaDevices!.getUserMedia({'audio': true});
    _recorder = html.MediaRecorder(stream);
    _chunks.clear();
    _recorder!.addEventListener('dataavailable', (event) {
      final blob = (event as dynamic).data as html.Blob;
      _readBlobBytes(blob).then((bytes) {
        _chunks.add(bytes);
      });
    });
    _recorder!.start();
  }

  static Future<Uint8List?> stop() async {
    if (_recorder == null) return null;
    _recorder!.stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final blob = html.Blob(_chunks.map((chunk) => chunk).toList(), 'audio/webm');
    return _readBlobBytes(blob);
  }

  static Future<Uint8List> _readBlobBytes(html.Blob blob) async {
    final reader = html.FileReader();
    reader.readAsArrayBuffer(blob);
    await reader.onLoad.first;
    final result = reader.result;
    if (result is ByteBuffer) {
      return Uint8List.view(result);
    }
    if (result is List<int>) {
      return Uint8List.fromList(result.cast<int>());
    }
    return Uint8List(0);
  }
}
