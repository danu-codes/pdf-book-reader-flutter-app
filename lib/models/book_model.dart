import 'dart:convert';

enum ReadingShelf {
  wantToRead,
  reading,
  finished,
}

class BookModel {
  final String filePath;
  String title;
  final int fileSizeBytes;
  int lastPage;
  int totalPages;
  DateTime? lastOpened;
  DateTime dateAdded;
  List<int> bookmarks;
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
    this.thumbnailPath,
    this.isManuallyFinished = false,
  })  : dateAdded = dateAdded ?? DateTime.now(),
        bookmarks = bookmarks ?? [];

  ReadingShelf get shelf {
    if (isManuallyFinished || (totalPages > 0 && lastPage >= totalPages)) {
      return ReadingShelf.finished;
    }
    if (lastPage > 1 || lastOpened != null) {
      return ReadingShelf.reading;
    }
    return ReadingShelf.wantToRead;
  }

  double get progress {
    if (totalPages <= 0) return 0.0;
    if (isManuallyFinished) return 1.0;
    return (lastPage / totalPages).clamp(0.0, 1.0);
  }

  int get pagesLeft {
    if (totalPages <= 0) return 0;
    return (totalPages - lastPage).clamp(0, totalPages);
  }

  String get formattedSize {
    final kb = fileSizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
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
    'thumbnailPath': thumbnailPath,
    'isManuallyFinished': isManuallyFinished,
  };

  factory BookModel.fromJson(Map<String, dynamic> json) => BookModel(
    filePath: json['filePath'] as String,
    title: json['title'] as String,
    fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
    lastPage: json['lastPage'] as int? ?? 1,
    totalPages: json['totalPages'] as int? ?? 0,
    lastOpened: json['lastOpened'] != null
        ? DateTime.tryParse(json['lastOpened'] as String)
        : null,
    dateAdded: json['dateAdded'] != null
        ? DateTime.tryParse(json['dateAdded'] as String)
        : DateTime.now(),
    bookmarks: (json['bookmarks'] as List<dynamic>?)
        ?.map((e) => e as int)
        .toList() ??
        [],
    thumbnailPath: json['thumbnailPath'] as String?,
    isManuallyFinished: json['isManuallyFinished'] as bool? ?? false,
  );

  static String encodeList(List<BookModel> books) =>
      jsonEncode(books.map((b) => b.toJson()).toList());

  static List<BookModel> decodeList(String jsonStr) {
    final List<dynamic> list = jsonDecode(jsonStr);
    return list
        .map((e) => BookModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}