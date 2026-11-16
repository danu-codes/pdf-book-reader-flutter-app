import 'dart:convert';

enum ReadingShelf { wantToRead, reading, finished }

class BookModel {
  final String filePath;
  String title;
  final int fileSizeBytes;
  int lastPage;
  int totalPages;
  DateTime? lastOpened;
  final DateTime dateAdded;
  List<int> bookmarks;
  List<int> visitedPages;
  String? thumbnailPath;
  bool isManuallyFinished;

  BookModel({
    required this.filePath,
    required this.title,
    required this.fileSizeBytes,
    this.lastPage = 1,
    this.totalPages = 0,
    this.lastOpened,
    DateTime? dateAdded,
    List<int>? bookmarks,
    List<int>? visitedPages,
    this.thumbnailPath,
    this.isManuallyFinished = false,
  })  : dateAdded = dateAdded ?? DateTime.now(),
        bookmarks = bookmarks ?? [],
        visitedPages = visitedPages ?? [];

  /// Unique fingerprint that stays identical even if the file is moved or re-added
  String get uniqueFingerprint =>
      '${filePath.split('/').last.split('\\').last}|$fileSizeBytes';

  /// Actual number of pages read (full totalPages if finished, otherwise distinct visited pages)
  int get effectivePagesRead {
    if (shelf == ReadingShelf.finished && totalPages > 0) {
      return totalPages;
    }
    return visitedPages.length;
  }

  int get pagesLeft =>
      totalPages > 0 ? (totalPages - lastPage).clamp(0, totalPages) : 0;

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  double get progress {
    if (isManuallyFinished) return 1.0;
    if (totalPages <= 0) return 0.0;
    return (lastPage / totalPages).clamp(0.0, 1.0);
  }

  ReadingShelf get shelf {
    if (isManuallyFinished ||
        (totalPages > 0 && visitedPages.length >= totalPages)) {
      return ReadingShelf.finished;
    }
    if (lastOpened != null && (lastPage > 1 || visitedPages.length > 1)) {
      return ReadingShelf.reading;
    }
    return ReadingShelf.wantToRead;
  }

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'title': title,
    'fileSizeBytes': fileSizeBytes,
    'lastPage': lastPage,
    'totalPages': totalPages,
    'lastOpened': lastOpened?.toIso8601String(),
    'dateAdded': dateAdded.toIso8601String(),
    'bookmarks': bookmarks,
    'visitedPages': visitedPages,
    'thumbnailPath': thumbnailPath,
    'isManuallyFinished': isManuallyFinished,
  };

  factory BookModel.fromJson(Map<String, dynamic> json) {
    final lastPage = json['lastPage'] as int? ?? 1;
    final rawVisited = json['visitedPages'] as List<dynamic>?;
    return BookModel(
      filePath: json['filePath'] as String,
      title: json['title'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      lastPage: lastPage,
      totalPages: json['totalPages'] as int? ?? 0,
      lastOpened: json['lastOpened'] != null
          ? DateTime.tryParse(json['lastOpened'] as String)
          : null,
      dateAdded: json['dateAdded'] != null
          ? DateTime.tryParse(json['dateAdded'] as String)
          : DateTime.now(),
      bookmarks: (json['bookmarks'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      visitedPages: rawVisited != null
          ? rawVisited.map((e) => e as int).toList()
          : (lastPage > 1 ? [lastPage] : []),
      thumbnailPath: json['thumbnailPath'] as String?,
      isManuallyFinished: json['isManuallyFinished'] as bool? ?? false,
    );
  }

  static String encodeList(List<BookModel> books) =>
      jsonEncode(books.map((b) => b.toJson()).toList());

  static List<BookModel> decodeList(String source) {
    final decoded = jsonDecode(source) as List<dynamic>;
    return decoded
        .map((e) => BookModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}