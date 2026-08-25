class Directory {
  final String path;

  Directory(this.path);

  Future<Directory> create({bool recursive = false}) async => this;
}
