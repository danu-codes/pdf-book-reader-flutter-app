import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book_model.dart';

class StorageService {
  static const String _storageKey = 'saved_books_progress_v1';
  static Map<String, BookModel>? _cache;
  static Timer? _debounce;

  Future<Map<String, BookModel>> getSavedBooksMap() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    _cache = (raw == null || raw.isEmpty)
        ? <String, BookModel>{}
        : {for (final b in BookModel.decodeList(raw)) b.filePath: b};
    return _cache!;
  }

  /// Updates the in-memory cache immediately; disk write is debounced.
  Future<void> saveBookProgress(BookModel book, {bool immediate = false}) async {
    final map = await getSavedBooksMap();
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
        _storageKey, BookModel.encodeList(_cache!.values.toList()));
  }

  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }
}