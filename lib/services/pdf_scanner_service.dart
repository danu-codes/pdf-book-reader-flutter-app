import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/book_model.dart';
import 'storage_service.dart';

class PdfScannerService {
  final StorageService _storageService = StorageService();

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) return true;
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  /// Books already saved (imported / previously read) that still exist.
  Future<List<BookModel>> loadSavedBooks() async {
    final savedMap = await _storageService.getSavedBooksMap();
    final books = <BookModel>[];
    for (final entry in savedMap.entries) {
      if (await File(entry.key).exists()) books.add(entry.value);
    }
    _sort(books);
    return books;
  }

  Future<List<BookModel>> scanDevicePdfs() async {
    final savedMap = await _storageService.getSavedBooksMap();
    final results = <BookModel>[];
    final seen = <String>{};

    for (final entry in savedMap.entries) {
      if (await File(entry.key).exists()) {
        results.add(entry.value);
        seen.add(entry.key);
      }
    }

    final root = Directory('/storage/emulated/0');
    if (await root.exists()) {
      await _scanDirectory(root, savedMap, results, seen);
    }

    _sort(results);
    return results;
  }

  void _sort(List<BookModel> books) {
    books.sort((a, b) {
      if (a.lastOpened != null && b.lastOpened != null) {
        return b.lastOpened!.compareTo(a.lastOpened!);
      }
      if (a.lastOpened != null) return -1;
      if (b.lastOpened != null) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }

  Future<void> _scanDirectory(
      Directory dir,
      Map<String, BookModel> savedMap,
      List<BookModel> results,
      Set<String> seen,
      ) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final path = entity.path;
        final name = p.basename(path);
        if (name.startsWith('.') ||
            path.contains('/Android/data') ||
            path.contains('/Android/obb')) {
          continue;
        }

        if (entity is Directory) {
          await _scanDirectory(entity, savedMap, results, seen);
        } else if (entity is File && path.toLowerCase().endsWith('.pdf')) {
          if (seen.add(path)) {
            final stat = await entity.stat();
            results.add(savedMap[path] ??
                BookModel(
                  filePath: path,
                  title: p.basenameWithoutExtension(path),
                  fileSizeBytes: stat.size,
                ));
          }
        }
      }
    } catch (_) {
      // Skip folders with restricted access
    }
  }

  /// Picks a PDF and copies it into permanent app storage so that
  /// progress survives file_picker's cache being cleared.
  Future<BookModel?> pickSinglePdf() async {
    final pickedFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (pickedFile == null || pickedFile.path == null) return null;

    final src = pickedFile.path!;
    final docs = await getApplicationDocumentsDirectory();
    final booksDir = Directory(p.join(docs.path, 'imported_books'));
    if (!await booksDir.exists()) await booksDir.create(recursive: true);

    final srcFile = File(src);
    final srcLen = await srcFile.length();
    var dest = p.join(booksDir.path, p.basename(src));
    final destFile = File(dest);
    if (await destFile.exists()) {
      if (await destFile.length() != srcLen) {
        dest = p.join(booksDir.path,
            '${DateTime.now().millisecondsSinceEpoch}_${p.basename(src)}');
        await srcFile.copy(dest);
      }
    } else {
      await srcFile.copy(dest);
    }

    final savedMap = await _storageService.getSavedBooksMap();
    if (savedMap.containsKey(dest)) return savedMap[dest];

    final book = BookModel(
      filePath: dest,
      title: p.basenameWithoutExtension(src),
      fileSizeBytes: srcLen,
    );
    await _storageService.saveBookProgress(book);
    return book;
  }
}