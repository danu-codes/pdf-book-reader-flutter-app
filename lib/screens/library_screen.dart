import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book_model.dart';
import '../services/pdf_scanner_service.dart';
import '../services/storage_service.dart';
import '../widgets/book_card.dart';
import 'reader_screen.dart';

enum _ShelfFilter { all, reading, unread, finished, bookmarked }

enum _SortOption { recent, added, title, progress }

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
  _SortOption _sortOption = _SortOption.recent;

  // Global reader preferences
  int _defaultThemeIndex = 0; // 0: Day, 1: Sepia, 2: Night
  bool _defaultHorizontal = false;
  bool _keepScreenAwake = true;
  int _coverStorageBytes = 0;

  @override
  void initState() {
    super.initState();
    _initFast();
  }

  Future<void> _initFast() async {
    await Future.wait([
      _reloadBooks(),
      _loadReaderPreferences(),
    ]);
    // Defer legacy cleanup so first frame & splash finish immediately
    Future.delayed(const Duration(seconds: 2), () {
      _storage.cleanupLegacyDuplicates();
    });
  }

  Future<void> _loadReaderPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final coverBytes = await _storage.getCoverStorageBytes();
    if (!mounted) return;
    setState(() {
      _defaultThemeIndex = prefs.getInt('reader_theme_mode') ?? 0;
      _defaultHorizontal = prefs.getBool('reader_horizontal') ?? false;
      _keepScreenAwake = prefs.getBool('reader_wakelock') ?? true;
      _coverStorageBytes = coverBytes;
    });
  }

  Future<void> _reloadBooks() async {
    final books = await _storage.getLibraryBooks();
    final coverBytes = await _storage.getCoverStorageBytes();
    if (!mounted) return;
    setState(() {
      _books = books;
      _coverStorageBytes = coverBytes;
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

  List<BookModel> get _filteredAndSortedBooks {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _books.where((book) {
      if (q.isNotEmpty && !book.title.toLowerCase().contains(q)) {
        return false;
      }
      return switch (_activeFilter) {
        _ShelfFilter.all => true,
        _ShelfFilter.reading => book.shelf == ReadingShelf.reading,
        _ShelfFilter.unread => book.shelf == ReadingShelf.wantToRead,
        _ShelfFilter.finished => book.shelf == ReadingShelf.finished,
        _ShelfFilter.bookmarked => book.bookmarks.isNotEmpty,
      };
    }).toList();

    switch (_sortOption) {
      case _SortOption.recent:
        break; // Already sorted by lastOpened in StorageService
      case _SortOption.added:
        filtered.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case _SortOption.title:
        filtered.sort(
                (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _SortOption.progress:
        filtered.sort((a, b) => b.progress.compareTo(a.progress));
    }
    return filtered;
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

  Future<void> _exportBackup() async {
    final jsonStr = await _storage.exportLibraryBackupJson();
    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final filePath = p.join(dir.path, 'lumina_library_backup.json');
    await File(filePath).writeAsString(jsonStr);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backup saved to: $filePath')),
    );
  }

  Future<void> _importBackup() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked.isEmpty || picked.first.path == null) return;
    final jsonStr = await File(picked.first.path!).readAsString();
    final count = await _storage.importLibraryBackupJson(jsonStr);
    await _reloadBooks();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored progress for $count books')),
    );
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

  Widget _buildSidebarDrawer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final finishedCount =
        _books.where((b) => b.shelf == ReadingShelf.finished).length;
    final totalPagesRead =
    _books.fold<int>(0, (sum, b) => sum + (b.lastPage > 1 ? b.lastPage : 0));
    final totalBookmarks =
    _books.fold<int>(0, (sum, b) => sum + b.bookmarks.length);
    final coverKb = (_coverStorageBytes / 1024).toStringAsFixed(0);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_stories_rounded,
                          size: 30, color: cs.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Lumina Reader',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statColumn('${_books.length}', 'Books'),
                      _statColumn('$finishedCount', 'Finished'),
                      _statColumn('$totalPagesRead', 'Pages Read'),
                      _statColumn('$totalBookmarks', 'Bookmarks'),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'SHELVES',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.library_books_rounded),
              title: const Text('All Books'),
              selected: _activeFilter == _ShelfFilter.all,
              onTap: () {
                setState(() => _activeFilter = _ShelfFilter.all);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('Currently Reading'),
              selected: _activeFilter == _ShelfFilter.reading,
              onTap: () {
                setState(() => _activeFilter = _ShelfFilter.reading);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: const Text('Finished Books'),
              selected: _activeFilter == _ShelfFilter.finished,
              onTap: () {
                setState(() => _activeFilter = _ShelfFilter.finished);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmarks_outlined),
              title: const Text('Bookmarked Books'),
              selected: _activeFilter == _ShelfFilter.bookmarked,
              onTap: () {
                setState(() => _activeFilter = _ShelfFilter.bookmarked);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'READER SETTINGS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Default Paper Theme'),
              subtitle: Text(switch (_defaultThemeIndex) {
                1 => 'Warm Sepia',
                2 => 'Dim Night Mode',
                _ => 'Day Light',
              }),
              onTap: () async {
                final next = (_defaultThemeIndex + 1) % 3;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('reader_theme_mode', next);
                setState(() => _defaultThemeIndex = next);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Horizontal Page Flip'),
              subtitle: const Text('Swipe left/right instead of vertical scroll'),
              value: _defaultHorizontal,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('reader_horizontal', val);
                setState(() => _defaultHorizontal = val);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.screen_lock_portrait_rounded),
              title: const Text('Keep Screen Awake'),
              subtitle: const Text('Prevent screen sleep while reading'),
              value: _keepScreenAwake,
              onChanged: (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('reader_wakelock', val);
                setState(() => _keepScreenAwake = val);
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'DATA & BACKUP',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_rounded),
              title: const Text('Export Reading Progress'),
              subtitle: const Text('Save bookmarks & pages to JSON'),
              onTap: _exportBackup,
            ),
            ListTile(
              leading: const Icon(Icons.restore_page_rounded),
              title: const Text('Restore Progress Backup'),
              subtitle: const Text('Import from JSON backup file'),
              onTap: _importBackup,
            ),
            ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('Database & Cover Storage'),
              subtitle: Text('SQLite DB active • Covers: $coverKb KB'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeBook = _activeBook;
    final showHero = activeBook != null &&
        _searchQuery.isEmpty &&
        _activeFilter == _ShelfFilter.all &&
        _sortOption == _SortOption.recent;
    final filtered = _filteredAndSortedBooks;

    return Scaffold(
      drawer: _buildSidebarDrawer(context),
      appBar: AppBar(
        title: const Text(
          'Lumina Library',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          PopupMenuButton<_SortOption>(
            tooltip: 'Sort Bookshelf',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sortOption,
            onSelected: (opt) => setState(() => _sortOption = opt),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _SortOption.recent,
                child: Text('Sort: All'),
              ),
              PopupMenuItem(
                value: _SortOption.added,
                child: Text('Sort: Recently Added'),
              ),
              PopupMenuItem(
                value: _SortOption.title,
                child: Text('Sort: Title (A–Z)'),
              ),
              PopupMenuItem(
                value: _SortOption.progress,
                child: Text('Sort: Reading Progress'),
              ),
            ],
          ),
        ],
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
                const SizedBox(width: 8),
                _filterChip('Bookmarked', _ShelfFilter.bookmarked),
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
              'Add PDF books from Downloads, Documents, or any folder on your phone. Your progress and bookmarks are saved in SQLite.',
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