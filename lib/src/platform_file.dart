// Exports a platform-appropriate `File` type.
// On native platforms this re-exports `dart:io`'s File.
// On web it falls back to the minimal stub in this folder.
export 'file_io_stub.dart' if (dart.library.io) 'dart:io';
