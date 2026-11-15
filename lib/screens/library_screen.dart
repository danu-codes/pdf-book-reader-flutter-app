import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/pdf_scanner_service.dart';
import '../services/storage_service.dart';
import '../widgets/book_card.dart';
import 'reader_screen.dart';

enum _ShelfFilter { all, reading, unread, finished }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final StorageService _storage = StorageService();
  final PdfScannerService _scanner = PdfScannerService();

  List<BookModel> _books = [];
  bool _isLoading = true;
  String _searchQuery = '';
  _ShelfFilter _activeFilter = _ShelfFilter.all;

  @override
  void initState() {
    super.initState();
    _initLibrary();
  }

  Future<void> _initLibrary() async {
    await _storage.cleanupLegacyDuplicates();
    await _reloadBooks();
  }

  Future<void> _reloadBooks() async {
    final books = await _storage.getLibraryBooks();
    if (!mounted) return;
    setState(() {
      _books = books;
      _isLoading = false;
    });
  }

  BookModel? get _activeBook {
    for (final b in _books) {
      if (b.lastOpened != null && b.shelf != ReadingShelf.finished) {
        return b;
      }
    }
    return null;
  }

  List<BookModel> get _filteredBooks {
    final q = _searchQuery.trim().toLowerCase();
    return _books.where((book) {
      if (q.isNotEmpty && !book.title.toLowerCase().contains(q)) {
        return false;
      }
      return switch (_activeFilter) {
        _ShelfFilter.all => true,
        _ShelfFilter.reading => book.shelf == ReadingShelf.reading,
        _ShelfFilter.unread => book.shelf == ReadingShelf.wantToRead,
        _ShelfFilter.finished => book.shelf == ReadingShelf.finished,
      };
    }).toList();
  }

  Future<void> _openBook(BookModel book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
    await _reloadBooks();
  }

  Future<void> _pickBooksFromStorage() async {
    final pickedBooks = await _scanner.pickPdfsFromFileManager();
    if (pickedBooks.isEmpty || !mounted) return;

    await _reloadBooks();

    if (pickedBooks.length == 1) {
      await _openBook(pickedBooks.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${pickedBooks.length} books to your library'),
        ),
      );
    }
  }

  void _showBookActions(BookModel book) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Rename Title'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(book);
              },
            ),
            ListTile(
              leading: Icon(
                book.isManuallyFinished
                    ? Icons.undo_rounded
                    : Icons.check_circle_outline_rounded,
              ),
              title: Text(book.isManuallyFinished
                  ? 'Mark as Unfinished'
                  : 'Mark as Finished'),
              onTap: () async {
                Navigator.pop(ctx);
                book.isManuallyFinished = !book.isManuallyFinished;
                await _storage.saveBookProgress(book, immediate: true);
                await _reloadBooks();
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('Reset Reading Progress'),
              onTap: () async {
                Navigator.pop(ctx);
                await _storage.resetBookProgress(book);
                await _reloadBooks();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                'Remove from Library',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text('Keeps original PDF file on your phone'),
              onTap: () async {
                Navigator.pop(ctx);
                await _storage.removeBookFromLibrary(book.filePath);
                await _reloadBooks();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BookModel book) {
    final controller = TextEditingController(text: book.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Book'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter book title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                book.title = newTitle;
                await _storage.saveBookProgress(book, immediate: true);
                await _reloadBooks();
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeBook = _activeBook;
    final showHero = activeBook != null &&
        _searchQuery.isEmpty &&
        _activeFilter == _ShelfFilter.all;
    final filtered = _filteredBooks;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Lumina Library',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search your library...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _filterChip('All (${_books.length})', _ShelfFilter.all),
                const SizedBox(width: 8),
                _filterChip('Reading', _ShelfFilter.reading),
                const SizedBox(width: 8),
                _filterChip('Unread', _ShelfFilter.unread),
                const SizedBox(width: 8),
                _filterChip('Finished', _ShelfFilter.finished),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _books.isEmpty
                ? _buildEmptyLibraryState()
                : filtered.isEmpty
                ? const Center(
              child: Text('No books in this shelf yet.'),
            )
                : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                if (showHero)
                  ContinueReadingHeroCard(
                    book: activeBook,
                    onTap: () => _openBook(activeBook),
                  ),
                ...filtered.map(
                      (book) => BookCard(
                    book: book,
                    onTap: () => _openBook(book),
                    onMoreTap: () => _showBookActions(book),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickBooksFromStorage,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Books'),
      ),
    );
  }

  Widget _filterChip(String label, _ShelfFilter filter) {
    return ChoiceChip(
      label: Text(label),
      selected: _activeFilter == filter,
      onSelected: (_) => setState(() => _activeFilter = filter),
    );
  }

  Widget _buildEmptyLibraryState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Bookshelf is Empty',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add PDF books from your phone storage. Your reading page, covers, and bookmarks are saved automatically.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pickBooksFromStorage,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Books from Storage'),
            ),
          ],
        ),
      ),
    );
  }
}