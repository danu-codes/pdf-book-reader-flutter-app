import 'package:flutter/material.dart';
import '../models/book_model.dart';
import 'book_cover_thumbnail.dart';

class ContinueReadingHeroCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback onTap;

  const ContinueReadingHeroCard({
    super.key,
    required this.book,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (book.progress * 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer,
            cs.secondaryContainer.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              BookCoverThumbnail(
                book: book,
                width: 68,
                height: 94,
                borderRadius: 10,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'CONTINUE READING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.totalPages > 0
                          ? 'Page ${book.lastPage} of ${book.totalPages} • ${book.pagesLeft} pages left ($percent%)'
                          : 'Page ${book.lastPage}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                    if (book.totalPages > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: book.progress,
                          minHeight: 6,
                          backgroundColor: cs.surface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onTap,
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: 'Resume Reading',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (book.progress * 100).toStringAsFixed(0);
    final shelf = book.shelf;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onMoreTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Row(
            children: [
              BookCoverThumbnail(book: book, width: 52, height: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _ShelfBadge(shelf: shelf),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            book.totalPages > 0
                                ? 'p.${book.lastPage}/${book.totalPages} ($percent%) • ${book.formattedSize}'
                                : book.formattedSize,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (book.totalPages > 0 &&
                        shelf != ReadingShelf.wantToRead) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: book.progress,
                          minHeight: 4,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                tooltip: 'Book Options',
                onPressed: onMoreTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfBadge extends StatelessWidget {
  final ReadingShelf shelf;
  const _ShelfBadge({required this.shelf});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (shelf) {
      ReadingShelf.finished => (
      'Finished',
      Colors.green.withValues(alpha: 0.18),
      Colors.green.shade700,
      ),
      ReadingShelf.reading => (
      'Reading',
      cs.primary.withValues(alpha: 0.15),
      cs.primary,
      ),
      ReadingShelf.wantToRead => (
      'Unread',
      cs.surfaceContainerHighest,
      cs.onSurfaceVariant,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}