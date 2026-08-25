// Minimal File stub used for platforms without dart:io (web)
// This provides only the `path` property used by the app and keeps
// types consistent during cross-platform builds.
class File {
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  Future<int> length() async => 0;
  Future<void> writeAsBytes(List<int> bytes) async {}
}
