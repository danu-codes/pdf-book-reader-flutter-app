import 'dart:io';
import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/pdf_scanner_service.dart';

class BookCoverThumbnail extends StatefulWidget {
  final BookModel book;
  final double width;
  final double height;
  final double borderRadius;

  const BookCoverThumbnail({
    super.key,
    required this.book,
    this.width = 54,
    this.height = 74,
    this.borderRadius = 8,
  });

  @override
  State<BookCoverThumbnail> createState() => _BookCoverThumbnailState();
}

class _BookCoverThumbnailState extends State<BookCoverThumbnail> {
  static final PdfScannerService _scanner = PdfScannerService();
  String? _thumbPath;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant BookCoverThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.filePath != widget.book.filePath ||
        oldWidget.book.thumbnailPath != widget.book.thumbnailPath) {
      _thumbPath = null;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final generation = ++_loadGeneration;
    final targetFilePath = widget.book.filePath;

    final existing = widget.book.thumbnailPath;
    if (existing != null && await File(existing).exists()) {
      if (mounted &&
          generation == _loadGeneration &&
          widget.book.filePath == targetFilePath) {
        setState(() => _thumbPath = existing);
      }
      return;
    }

    final generated = await _scanner.generateCoverThumbnail(widget.book);
    if (mounted &&
        generated != null &&
        generation == _loadGeneration &&
        widget.book.filePath == targetFilePath) {
      setState(() => _thumbPath = generated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _thumbPath != null
          ? Image.file(
        File(_thumbPath!),
        key: ValueKey(_thumbPath),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        cacheWidth: (widget.width * 2).round(),
        errorBuilder: (_, __, ___) => _fallbackIcon(cs),
      )
          : _fallbackIcon(cs),
    );
  }

  Widget _fallbackIcon(ColorScheme cs) {
    return Center(
      child: Icon(
        Icons.menu_book_rounded,
        color: cs.onPrimaryContainer,
        size: widget.width * 0.48,
      ),
    );
  }
}