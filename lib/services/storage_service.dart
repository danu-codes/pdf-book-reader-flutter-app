import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/book_model.dart';

typedef BookLibraryMap = Map<String, BookModel>;

class StorageService {
  static const String _dbName = 'lumina_reader.db';
  static const String _tableBooks = 'books';
  static const String _legacyPrefsKey = 'lumina_library_books_v2';

  static Database? _db;
  static Timer? _debounce;
  static BookModel? _pendingBook;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, _dbName);

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableBooks (
            filePath TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            fileSizeBytes INTEGER NOT NULL,
            lastPage INTEGER NOT NULL,
            totalPages INTEGER NOT NULL,
            lastOpened TEXT,
            dateAdded TEXT NOT NULL,
            bookmarks TEXT NOT NULL,
            thumbnailPath TEXT,
            isManuallyFinished INTEGER NOT NULL
          )
        ''');
      },
    );

    await _migrateFromLegacyPrefs(_db!);
    return _db!;
  }

  Future<void> _migrateFromLegacyPrefs(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyPrefsKey);
    if (raw == null || raw.isEmpty) return;

    final legacyBooks = BookModel.decodeList(raw);
    final batch = db.batch();
    for (final book in legacyBooks) {
      batch.insert(
        _tableBooks,
        _toRow(book),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    await prefs.remove(_legacyPrefsKey);
  }

  Map<String, Object?> _toRow(BookModel b) => {
    'filePath': b.filePath,
    'title': b.title,
    'fileSizeBytes': b.fileSizeBytes,
    'lastPage': b.lastPage,
    'totalPages': b.totalPages,
    'lastOpened': b.lastOpened?.toIso8601String(),
    'dateAdded': b.dateAdded.toIso8601String(),
    'bookmarks': jsonEncode(b.bookmarks),
    'thumbnailPath': b.thumbnailPath,
    'isManuallyFinished': b.isManuallyFinished ? 1 : 0,
  };

  BookModel _fromRow(Map<String, Object?> row) => BookModel(
    filePath: row['filePath'] as String,
    title: row['title'] as String,
    fileSizeBytes: row['fileSizeBytes'] as int? ?? 0,
    lastPage: row['lastPage'] as int? ?? 1,
    totalPages: row['totalPages'] as int? ?? 0,
    lastOpened: row['lastOpened'] != null
        ? DateTime.tryParse(row['lastOpened'] as String)
        : null,
    dateAdded: row['dateAdded'] != null
        ? DateTime.tryParse(row['dateAdded'] as String)
        : DateTime.now(),
    bookmarks: (jsonDecode(row['bookmarks'] as String? ?? '[]') as List)
        .map((e) => e as int)
        .toList(),
    thumbnailPath: row['thumbnailPath'] as String?,
    isManuallyFinished: (row['isManuallyFinished'] as int? ?? 0) == 1,
  );

  Future<BookLibraryMap> getLibraryMap() async {
    final db = await database;
    final rows = await db.query(_tableBooks);
    return {
      for (final r in rows) r['filePath'] as String: _fromRow(r),
    };
  }

  Future<List<BookModel>> getLibraryBooks() async {
    final db = await database;
    final rows = await db.query(_tableBooks);
    final validBooks = <BookModel>[];
    final missingPaths = <String>[];

    for (final row in rows) {
      final book = _fromRow(row);
      if (await File(book.filePath).exists()) {
        validBooks.add(book);
      } else {
        missingPaths.add(book.filePath);
      }
    }

    if (missingPaths.isNotEmpty) {
      final batch = db.batch();
      for (final path in missingPaths) {
        batch.delete(_tableBooks, where: 'filePath = ?', whereArgs: [path]);
      }
      await batch.commit(noResult: true);
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
    final db = await database;
    final batch = db.batch();
    for (final book in books) {
      batch.insert(
        _tableBooks,
        _toRow(book),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeBookFromLibrary(String filePath) async {
    final db = await database;
    final rows = await db.query(
      _tableBooks,
      columns: ['thumbnailPath'],
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
    if (rows.isNotEmpty) {
      final thumbPath = rows.first['thumbnailPath'] as String?;
      if (thumbPath != null && await File(thumbPath).exists()) {
        await File(thumbPath).delete();
      }
    }
    await db.delete(_tableBooks, where: 'filePath = ?', whereArgs: [filePath]);
  }

  Future<void> resetBookProgress(BookModel book) async {
    book.lastPage = 1;
    book.lastOpened = null;
    book.isManuallyFinished = false;
    await saveBookProgress(book, immediate: true);
  }

  Future<void> saveBookProgress(BookModel book, {bool immediate = false}) async {
    _pendingBook = book;
    _debounce?.cancel();
    if (immediate) {
      await _writeBook(book);
      _pendingBook = null;
    } else {
      _debounce = Timer(const Duration(milliseconds: 600), () async {
        if (_pendingBook != null) {
          await _writeBook(_pendingBook!);
          _pendingBook = null;
        }
      });
    }
  }

  Future<void> _writeBook(BookModel book) async {
    final db = await database;
    await db.insert(
      _tableBooks,
      _toRow(book),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> flushNow() async {
    _debounce?.cancel();
    if (_pendingBook != null) {
      await _writeBook(_pendingBook!);
      _pendingBook = null;
    }
  }

  /// Exports all library metadata, reading pages, and bookmarks as JSON.
  Future<String> exportLibraryBackupJson() async {
    final books = await getLibraryBooks();
    return BookModel.encodeList(books);
  }

  /// Restores reading progress & bookmarks from a JSON backup for matching files.
  Future<int> importLibraryBackupJson(String jsonStr) async {
    final imported = BookModel.decodeList(jsonStr);
    final db = await database;
    final batch = db.batch();
    int restored = 0;

    for (final book in imported) {
      if (await File(book.filePath).exists()) {
        batch.insert(
          _tableBooks,
          _toRow(book),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        restored++;
      }
    }
    await batch.commit(noResult: true);
    return restored;
  }

  Future<int> getCoverStorageBytes() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'book_covers'));
      if (!await coversDir.exists()) return 0;
      int total = 0;
      await for (final entity in coversDir.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> cleanupLegacyDuplicates() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final legacyDir = Directory(p.join(docs.path, 'imported_books'));
      if (await legacyDir.exists()) {
        await legacyDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}