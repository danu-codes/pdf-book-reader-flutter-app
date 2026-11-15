import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book_model.dart';

typedef BookLibraryMap = Map<String, BookModel>;

class StorageService {
  static const String _storageKey = 'lumina_library_books_v2';
  static BookLibraryMap? _cache;
  static Timer? _debounce;

  Future<BookLibraryMap> getLibraryMap() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _cache = (raw == null || raw.isEmpty)
        ? <String, BookModel>{}
        : {for (final b in BookModel.decodeList(raw)) b.filePath: b};
    return _cache!;
  }

  /// Loads only books explicitly added to the user's curated library (instant < 30ms).
  Future<List<BookModel>> getLibraryBooks() async {
    final map = await getLibraryMap();
    final validBooks = <BookModel>[];
    bool removedMissing = false;

    for (final entry in map.entries.toList()) {
      if (await File(entry.key).exists()) {
        validBooks.add(entry.value);
      } else {
        map.remove(entry.key);
        removedMissing = true;
      }
    }

    if (removedMissing) {
      await _flush();
    }

    validBooks.sort((a, b) {
      if (a.lastOpened != null && b.lastOpened != null) {
        return b.lastOpened!.compareTo(a.lastOpened!);
      }
      if (a.lastOpened != null) return -1;
      if (b.lastOpened != null) return 1;
      return b.dateAdded.compareTo(a.dateAdded);
    });

    return validBooks;
  }

  Future<void> addBooksToLibrary(List<BookModel> books) async {
    final map = await getLibraryMap();
    for (final book in books) {
      map.putIfAbsent(book.filePath, () => book);
    }
    await _flush();
  }

  Future<void> removeBookFromLibrary(String filePath) async {
    final map = await getLibraryMap();
    final removed = map.remove(filePath);
    if (removed?.thumbnailPath != null) {
      final thumbFile = File(removed!.thumbnailPath!);
      if (await thumbFile.exists()) {
        await thumbFile.delete();
      }
    }
    await _flush();
  }

  Future<void> resetBookProgress(BookModel book) async {
    book.lastPage = 1;
    book.lastOpened = null;
    book.isManuallyFinished = false;
    await saveBookProgress(book, immediate: true);
  }

  /// Updates in-memory cache immediately; disk write is debounced for smooth scrolling.
  Future<void> saveBookProgress(BookModel book, {bool immediate = false}) async {
    final map = await getLibraryMap();
    map[book.filePath] = book;
    _debounce?.cancel();
    if (immediate) {
      await _flush();
    } else {
      _debounce = Timer(const Duration(milliseconds: 800), _flush);
    }
  }

  Future<void> _flush() async {
    if (_cache == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      BookModel.encodeList(_cache!.values.toList()),
    );
  }

  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  /// Removes old duplicated PDFs from imported_books/ to reclaim internal storage.
  Future<void> cleanupLegacyDuplicates() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final legacyDir = Directory(p.join(docs.path, 'imported_books'));
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
      }
    } catch (_) {
      // Ignore if already deleted
    }
  }
}