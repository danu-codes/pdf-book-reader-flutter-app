import 'package:flutter/material.dart';
import '../models/book_model.dart';

/// Full-width list card (All PDFs).
class BookCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback onTap;

  const BookCard({super.key, required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasProgress = book.totalPages > 0 && book.lastPage > 1;
    final percent = (book.progress * 100).toStringAsFixed(0);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 62,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.menu_book_rounded,
                    color: cs.onPrimaryContainer, size: 26),
              ),
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
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.totalPages > 0
                          ? '${book.formattedSize} • Page ${book.lastPage} of ${book.totalPages} ($percent%)'
                          : book.formattedSize,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                        hasProgress ? FontWeight.w600 : FontWeight.normal,
                        color: hasProgress ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    if (book.totalPages > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: book.progress,
                          minHeight: 5,
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact card for the horizontal "Continue Reading" shelf.
class ShelfCard extends StatelessWidget {
  final BookModel book;
  final VoidCallback onTap;

  const ShelfCard({super.key, required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final percent = (book.progress * 100).toStringAsFixed(0);

    return SizedBox(
      width: 150,
      child: Card(
        margin: const EdgeInsets.only(right: 12),
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 64,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.menu_book_rounded,
                      color: cs.onPrimaryContainer, size: 28),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                if (book.totalPages > 0) ...[
                  Text('$percent% • p.${book.lastPage}',
                      style: TextStyle(fontSize: 11, color: cs.primary)),
                  const SizedBox(height: 4),
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
        ),
      ),
    );
  }
}