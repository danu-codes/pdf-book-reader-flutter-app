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
  static const String _tableStats = 'reading_stats';
  static const String _legacyPrefsKey = 'lumina_library_books_v2';

  /// Fixed public location that survives Clear Cache, Clear Data, and Uninstall
  static const String fixedBackupDirPath =
      '/storage/emulated/0/Download/LuminaReaderBackup';
  static const String autoBackupFileName = 'lumina_auto_backup.json';

  static String get fixedBackupFilePath =>
      p.join(fixedBackupDirPath, autoBackupFileName);

  static Database? _db;
  static Timer? _debounce;
  static BookModel? _pendingBook;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, _dbName);

    _db = await openDatabase(
      dbPath,
      version: 2,
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
        await _createStatsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createStatsTable(db);
        }
      },
    );

    await _migrateFromLegacyPrefs(_db!);
    return _db!;
  }

  Future<void> _createStatsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableStats (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        archivedFinishedCount INTEGER NOT NULL DEFAULT 0,
        archivedPagesRead INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert(
      _tableStats,
      {'id': 1, 'archivedFinishedCount': 0, 'archivedPagesRead': 0},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
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
        await _archiveBookStats(db, book);
        missingPaths.add(book.filePath);
      }
    }

    if (missingPaths.isNotEmpty) {
      final batch = db.batch();
      for (final path in missingPaths) {
        batch.delete(_tableBooks, where: 'filePath = ?', whereArgs: [path]);
      }
      await batch.commit(noResult: true);
      await syncAutoBackupNow();
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

  Future<void> _archiveBookStats(Database db, BookModel book) async {
    final isFinished = book.shelf == ReadingShelf.finished ? 1 : 0;
    final pagesRead = book.lastPage > 1 ? book.lastPage : 0;
    if (isFinished == 0 && pagesRead == 0) return;

    await db.rawUpdate('''
      UPDATE $_tableStats
      SET archivedFinishedCount = archivedFinishedCount + ?,
          archivedPagesRead = archivedPagesRead + ?
      WHERE id = 1
    ''', [isFinished, pagesRead]);
  }

  Future<({int archivedFinished, int archivedPages})> getArchivedStats() async {
    final db = await database;
    final rows = await db.query(_tableStats, where: 'id = 1');
    if (rows.isEmpty) return (archivedFinished: 0, archivedPages: 0);
    return (
    archivedFinished: rows.first['archivedFinishedCount'] as int? ?? 0,
    archivedPages: rows.first['archivedPagesRead'] as int? ?? 0,
    );
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
    await syncAutoBackupNow();
  }

  Future<void> removeBookFromLibrary(String filePath) async {
    final db = await database;
    final rows = await db.query(
      _tableBooks,
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
    if (rows.isNotEmpty) {
      final book = _fromRow(rows.first);
      await _archiveBookStats(db, book);

      if (book.thumbnailPath != null &&
          await File(book.thumbnailPath!).exists()) {
        await File(book.thumbnailPath!).delete();
      }

      if (filePath.contains('library_pdfs') && await File(filePath).exists()) {
        await File(filePath).delete();
      }
    }
    await db.delete(_tableBooks, where: 'filePath = ?', whereArgs: [filePath]);
    await syncAutoBackupNow();
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
    await syncAutoBackupNow();
  }

  Future<void> flushNow() async {
    _debounce?.cancel();
    if (_pendingBook != null) {
      await _writeBook(_pendingBook!);
      _pendingBook = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Fixed-Location Auto-Backup & Restore (/Download/LuminaReaderBackup/)
  // ---------------------------------------------------------------------------

  Future<bool> hasExistingBackupFile() async {
    try {
      return await File(fixedBackupFilePath).exists();
    } catch (_) {
      return false;
    }
  }

  /// Automatically writes the full SQLite state (books + lifetime stats)
  /// to /storage/emulated/0/Download/LuminaReaderBackup/lumina_auto_backup.json
  Future<bool> syncAutoBackupNow() async {
    try {
      final dir = Directory(fixedBackupDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final jsonStr = await exportFullStateJson();
      final backupFile = File(fixedBackupFilePath);
      await backupFile.writeAsString(jsonStr, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> exportFullStateJson() async {
    final db = await database;
    final rows = await db.query(_tableBooks);
    final books = rows.map(_fromRow).toList();
    final stats = await getArchivedStats();

    final payload = {
      'version': 2,
      'updatedAt': DateTime.now().toIso8601String(),
      'archivedFinishedCount': stats.archivedFinished,
      'archivedPagesRead': stats.archivedPages,
      'books': books.map((b) => b.toJson()).toList(),
    };
    return jsonEncode(payload);
  }

  /// Reads directly from /storage/emulated/0/Download/LuminaReaderBackup/lumina_auto_backup.json
  /// and restores all books, bookmarks, reading pages, and lifetime stats.
  Future<({int restoredBooks, int finishedCount, int pagesRead})?>
  restoreFromFixedBackupLocation() async {
    final backupFile = File(fixedBackupFilePath);
    if (!await backupFile.exists()) return null;

    final jsonStr = await backupFile.readAsString();
    final db = await database;
    final decoded = jsonDecode(jsonStr);

    int archivedFinished = 0;
    int archivedPages = 0;
    List<BookModel> books = [];

    if (decoded is Map<String, dynamic>) {
      archivedFinished = decoded['archivedFinishedCount'] as int? ?? 0;
      archivedPages = decoded['archivedPagesRead'] as int? ?? 0;
      final rawBooks = decoded['books'] as List<dynamic>? ?? [];
      books = rawBooks
          .map((e) => BookModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (decoded is List) {
      books = BookModel.decodeList(jsonStr);
    }

    int restoredCount = 0;
    final batch = db.batch();

    for (final book in books) {
      if (await File(book.filePath).exists()) {
        batch.insert(
          _tableBooks,
          _toRow(book),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        restoredCount++;
      } else {
        if (book.shelf == ReadingShelf.finished) archivedFinished++;
        if (book.lastPage > 1) archivedPages += book.lastPage;
      }
    }

    batch.rawUpdate('''
      UPDATE $_tableStats
      SET archivedFinishedCount = ?,
          archivedPagesRead = ?
      WHERE id = 1
    ''', [archivedFinished, archivedPages]);

    await batch.commit(noResult: true);
    await syncAutoBackupNow();

    return (
    restoredBooks: restoredCount,
    finishedCount: archivedFinished,
    pagesRead: archivedPages,
    );
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