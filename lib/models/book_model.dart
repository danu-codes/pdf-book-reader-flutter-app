import 'dart:convert';

class BookModel {
  final String filePath;
  final String title;
  final int fileSizeBytes;
  int lastPage;
  int totalPages;
  DateTime? lastOpened;
  List<int> bookmarks;

  BookModel({
    required this.filePath,
    required this.title,
    required this.fileSizeBytes,
    this.lastPage = 1,
    this.totalPages = 0,
    this.lastOpened,
    List<int>? bookmarks,
  }) : bookmarks = bookmarks ?? [];

  double get progress {
    if (totalPages <= 0) return 0.0;
    return (lastPage / totalPages).clamp(0.0, 1.0);
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
    'bookmarks': bookmarks,
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
    bookmarks: (json['bookmarks'] as List<dynamic>?)
        ?.map((e) => e as int)
        .toList() ??
        [],
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