class File {
  final String path;

  File(this.path);

  Future<bool> exists() async => false;
  Future<void> writeAsBytes(List<int> bytes) async {}
  Future<List<int>> readAsBytes() async => const [];
  Future<void> create({bool recursive = false}) async {}
  Future<void> delete({bool recursive = false}) async {}
}

class FileSystemFile extends File {
  FileSystemFile(String path) : super(path);
}
