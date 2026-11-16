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
  static const String _tableArchivedBooks = 'archived_books';
  static const String _legacyPrefsKey = 'lumina_library_books_v2';

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
      version: 3,
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
            visitedPages TEXT NOT NULL DEFAULT '[]',
            thumbnailPath TEXT,
            isManuallyFinished INTEGER NOT NULL
          )
        ''');
        await _createStatsTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createStatsTables(db);
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE $_tableBooks ADD COLUMN visitedPages TEXT NOT NULL DEFAULT '[]'",
          );
          await _createArchivedBooksTable(db);
        }
      },
    );

    await _migrateFromLegacyPrefs(_db!);
    return _db!;
  }

  Future<void> _createStatsTables(Database db) async {
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
    await _createArchivedBooksTable(db);
  }

  Future<void> _createArchivedBooksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableArchivedBooks (
        fingerprint TEXT PRIMARY KEY,
        creditedFinished INTEGER NOT NULL DEFAULT 0,
        creditedPages INTEGER NOT NULL DEFAULT 0
      )
    ''');
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
    'visitedPages': jsonEncode(b.visitedPages),
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
    visitedPages:
    (jsonDecode(row['visitedPages'] as String? ?? '[]') as List)
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
        await _archiveBookStatsDeduped(db, book);
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

  /// Banks a book's stats without double-counting if the same book was
  /// previously archived, removed, and re-added.
  Future<void> _archiveBookStatsDeduped(
      Database db,
      BookModel book, {
        bool? userConfirmedFinished,
      }) async {
    final isFinished = userConfirmedFinished ??
        (book.isManuallyFinished ||
            (book.totalPages > 0 &&
                book.visitedPages.length >= book.totalPages));

    final int newCreditedFinished = isFinished ? 1 : 0;
    final int newCreditedPages = (isFinished && book.totalPages > 0)
        ? book.totalPages
        : book.visitedPages.length;

    final existing = await db.query(
      _tableArchivedBooks,
      where: 'fingerprint = ?',
      whereArgs: [book.uniqueFingerprint],
    );

    final prevFinished = existing.isNotEmpty
        ? (existing.first['creditedFinished'] as int? ?? 0)
        : 0;
    final prevPages = existing.isNotEmpty
        ? (existing.first['creditedPages'] as int? ?? 0)
        : 0;

    final deltaFinished =
    newCreditedFinished > prevFinished ? newCreditedFinished - prevFinished : 0;
    final deltaPages =
    newCreditedPages > prevPages ? newCreditedPages - prevPages : 0;

    if (deltaFinished > 0 || deltaPages > 0) {
      await db.rawUpdate('''
        UPDATE $_tableStats
        SET archivedFinishedCount = archivedFinishedCount + ?,
            archivedPagesRead = archivedPagesRead + ?
        WHERE id = 1
      ''', [deltaFinished, deltaPages]);

      await db.insert(
        _tableArchivedBooks,
        {
          'fingerprint': book.uniqueFingerprint,
          'creditedFinished':
          newCreditedFinished > prevFinished ? newCreditedFinished : prevFinished,
          'creditedPages':
          newCreditedPages > prevPages ? newCreditedPages : prevPages,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
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

  /// Computes live totals (archived + active shelf) while subtracting any
  /// already-archived credit for books that were re-added so stats never double-count.
  Future<({int totalFinished, int totalPagesRead})> getCombinedStats(
      List<BookModel> activeBooks,
      ) async {
    final db = await database;
    final archived = await getArchivedStats();
    final archivedRows = await db.query(_tableArchivedBooks);
    final archivedMap = {
      for (final r in archivedRows)
        r['fingerprint'] as String: (
        finished: r['creditedFinished'] as int? ?? 0,
        pages: r['creditedPages'] as int? ?? 0,
        ),
    };

    int extraActiveFinished = 0;
    int extraActivePages = 0;

    for (final book in activeBooks) {
      final prev = archivedMap[book.uniqueFingerprint];
      final activeFinished = book.shelf == ReadingShelf.finished ? 1 : 0;
      final activePages = book.effectivePagesRead;

      final prevFin = prev?.finished ?? 0;
      final prevPag = prev?.pages ?? 0;

      if (activeFinished > prevFin) {
        extraActiveFinished += activeFinished - prevFin;
      }
      if (activePages > prevPag) {
        extraActivePages += activePages - prevPag;
      }
    }

    return (
    totalFinished: archived.archivedFinished + extraActiveFinished,
    totalPagesRead: archived.archivedPages + extraActivePages,
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

  /// Removes a book from the shelf and records its stats based on whether
  /// the user confirmed finishing it, preventing double-counting on re-add.
  Future<void> removeBookFromLibrary(
      String filePath, {
        bool? userConfirmedFinished,
      }) async {
    final db = await database;
    final rows = await db.query(
      _tableBooks,
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
    if (rows.isNotEmpty) {
      final book = _fromRow(rows.first);
      await _archiveBookStatsDeduped(
        db,
        book,
        userConfirmedFinished: userConfirmedFinished,
      );

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
    book.visitedPages.clear();
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
    final archivedLedger = await db.query(_tableArchivedBooks);

    final payload = {
      'version': 3,
      'updatedAt': DateTime.now().toIso8601String(),
      'archivedFinishedCount': stats.archivedFinished,
      'archivedPagesRead': stats.archivedPages,
      'archivedBooksLedger': archivedLedger,
      'books': books.map((b) => b.toJson()).toList(),
    };
    return jsonEncode(payload);
  }

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
    List<dynamic> ledgerRows = [];

    if (decoded is Map<String, dynamic>) {
      archivedFinished = decoded['archivedFinishedCount'] as int? ?? 0;
      archivedPages = decoded['archivedPagesRead'] as int? ?? 0;
      ledgerRows = decoded['archivedBooksLedger'] as List<dynamic>? ?? [];
      final rawBooks = decoded['books'] as List<dynamic>? ?? [];
      books = rawBooks
          .map((e) => BookModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (decoded is List) {
      books = BookModel.decodeList(jsonStr);
    }

    final batch = db.batch();

    for (final entry in ledgerRows) {
      if (entry is Map<String, dynamic>) {
        batch.insert(
          _tableArchivedBooks,
          {
            'fingerprint': entry['fingerprint'] as String,
            'creditedFinished': entry['creditedFinished'] as int? ?? 0,
            'creditedPages': entry['creditedPages'] as int? ?? 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    int restoredCount = 0;
    final restoredBooksList = <BookModel>[];

    for (final book in books) {
      String? resolvedPath;
      if (await File(book.filePath).exists()) {
        resolvedPath = book.filePath;
      } else {
        final fallbackPath = p.join(
          fixedBackupDirPath,
          'books',
          p.basename(book.filePath),
        );
        if (await File(fallbackPath).exists()) {
          resolvedPath = fallbackPath;
        }
      }

      if (resolvedPath != null) {
        final validThumb = (book.thumbnailPath != null &&
            await File(book.thumbnailPath!).exists())
            ? book.thumbnailPath
            : null;

        final restoredBook = BookModel(
          filePath: resolvedPath,
          title: book.title,
          fileSizeBytes: book.fileSizeBytes,
          lastPage: book.lastPage,
          totalPages: book.totalPages,
          lastOpened: book.lastOpened,
          dateAdded: book.dateAdded,
          bookmarks: book.bookmarks,
          visitedPages: book.visitedPages,
          thumbnailPath: validThumb,
          isManuallyFinished: book.isManuallyFinished,
        );

        batch.insert(
          _tableBooks,
          _toRow(restoredBook),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        restoredCount++;
        restoredBooksList.add(restoredBook);
      } else {
        final fin = book.shelf == ReadingShelf.finished ? 1 : 0;
        final pag = book.effectivePagesRead;
        archivedFinished += fin;
        archivedPages += pag;
        batch.insert(
          _tableArchivedBooks,
          {
            'fingerprint': book.uniqueFingerprint,
            'creditedFinished': fin,
            'creditedPages': pag,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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

    final combined = await getCombinedStats(restoredBooksList);
    return (
    restoredBooks: restoredCount,
    finishedCount: combined.totalFinished,
    pagesRead: combined.totalPagesRead,
    );
  }

  Future<void> resetAllDataAndStats({bool deleteBackupFiles = false}) async {
    final db = await database;
    await db.delete(_tableBooks);
    await db.delete(_tableArchivedBooks);
    await db.rawUpdate('''
      UPDATE $_tableStats
      SET archivedFinishedCount = 0,
          archivedPagesRead = 0
      WHERE id = 1
    ''');

    try {
      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory(p.join(supportDir.path, 'book_covers'));
      if (await coversDir.exists()) {
        await coversDir.delete(recursive: true);
      }
    } catch (_) {}

    if (deleteBackupFiles) {
      try {
        final backupDir = Directory(fixedBackupDirPath);
        if (await backupDir.exists()) {
          await backupDir.delete(recursive: true);
        }
      } catch (_) {}
    } else {
      await syncAutoBackupNow();
    }
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