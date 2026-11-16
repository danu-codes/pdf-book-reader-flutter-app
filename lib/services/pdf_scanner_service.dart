import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import '../models/book_model.dart';
import 'storage_service.dart';

class PdfScannerService {
  final StorageService _storageService = StorageService();

  /// Opens Android's native file manager directly.
  /// Moves temporary /cache/file_picker/ copies into persistent shared storage
  /// (/Download/LuminaReaderBackup/books) so Clear Cache, Clear Data, and
  /// Reinstall never lose the PDF file.
  Future<List<BookModel>> pickPdfsFromFileManager() async {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (pickedFiles.isEmpty) return [];

    final savedMap = await _storageService.getLibraryMap();
    final newlyAdded = <BookModel>[];
    final returnedBooks = <BookModel>[];
    final supportDir = await getApplicationSupportDirectory();

    for (final picked in pickedFiles) {
      final rawPath = picked.path;
      if (rawPath == null) continue;

      final sourceFile = File(rawPath);
      if (!await sourceFile.exists()) continue;

      String finalPath = rawPath;

      if (rawPath.contains('/cache/')) {
        Directory persistentDir;
        try {
          persistentDir = Directory(
            p.join(StorageService.fixedBackupDirPath, 'books'),
          );
          if (!await persistentDir.exists()) {
            await persistentDir.create(recursive: true);
          }
        } catch (_) {
          persistentDir = Directory(p.join(supportDir.path, 'library_pdfs'));
          if (!await persistentDir.exists()) {
            await persistentDir.create(recursive: true);
          }
        }

        final destPath = p.join(persistentDir.path, p.basename(rawPath));
        final destFile = File(destPath);
        if (!await destFile.exists()) {
          await sourceFile.copy(destPath);
        }
        await sourceFile.delete();
        finalPath = destPath;
      }

      if (savedMap.containsKey(finalPath)) {
        returnedBooks.add(savedMap[finalPath]!);
        continue;
      }

      final stat = await File(finalPath).stat();
      final book = BookModel(
        filePath: finalPath,
        title: p.basenameWithoutExtension(finalPath),
        fileSizeBytes: stat.size,
      );
      newlyAdded.add(book);
      returnedBooks.add(book);
    }

    if (newlyAdded.isNotEmpty) {
      await _storageService.addBooksToLibrary(newlyAdded);
    }

    return returnedBooks;
  }

  /// Deterministic 64-bit FNV-1a hash so cover filenames never collide or
  /// change across app restarts.
  String _stablePathHash(String input) {
    var hash = 0xcbf29ce484222325;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Renders Page 1 into persistent App Support storage with a solid white paper
  /// background so Clear Cache keeps covers intact and text is always crisp.
  Future<String?> generateCoverThumbnail(BookModel book) async {
    if (book.thumbnailPath != null && await File(book.thumbnailPath!).exists()) {
      return book.thumbnailPath;
    }

    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'book_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final safeName = '${_stablePathHash(book.filePath)}.png';
      final outPath = p.join(coversDir.path, safeName);
      final outFile = File(outPath);

      if (await outFile.exists() && await outFile.length() > 0) {
        book.thumbnailPath = outPath;
        await _storageService.saveBookProgress(book, immediate: true);
        return outPath;
      }

      final doc = await PdfDocument.openFile(book.filePath);
      try {
        if (doc.pages.isEmpty) return null;
        final page = doc.pages.first;
        const targetWidth = 220.0;
        final scale = targetWidth / page.width;
        final targetHeight = (page.height * scale).round();

        final pdfImage = await page.render(
          width: targetWidth.round(),
          height: targetHeight,
          backgroundColor: 0xFFFFFFFF,
        );
        if (pdfImage == null) return null;

        final uiImage = await pdfImage.createImage();
        pdfImage.dispose();

        final byteData =
        await uiImage.toByteData(format: ui.ImageByteFormat.png);
        uiImage.dispose();

        if (byteData != null) {
          await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
          book.thumbnailPath = outPath;
          if (book.totalPages == 0) {
            book.totalPages = doc.pages.length;
          }
          await _storageService.saveBookProgress(book, immediate: true);
          return outPath;
        }
      } finally {
        await doc.dispose();
      }
    } catch (_) {}
    return null;
  }
}