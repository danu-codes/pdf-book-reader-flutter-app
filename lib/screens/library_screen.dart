import 'package:flutter/material.dart';
import '../models/book_model.dart';
import '../services/pdf_scanner_service.dart';
import '../widgets/book_card.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final PdfScannerService _scanner = PdfScannerService();
  List<BookModel> _allBooks = [];
  bool _isLoading = true;
  bool _permissionDenied = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _isLoading = true);

    final granted = await _scanner.requestStoragePermission();
    final books =
    granted ? await _scanner.scanDevicePdfs() : await _scanner.loadSavedBooks();

    if (!mounted) return;
    setState(() {
      _allBooks = books;
      _permissionDenied = !granted;
      _isLoading = false;
    });
  }

  List<BookModel> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _allBooks;
    return _allBooks.where((b) => b.title.toLowerCase().contains(q)).toList();
  }

  List<BookModel> get _recent {
    final list = _allBooks.where((b) => b.lastOpened != null).toList()
      ..sort((a, b) => b.lastOpened!.compareTo(a.lastOpened!));
    return list.take(6).toList();
  }

  Future<void> _openBook(BookModel book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
    if (!mounted) return;
    // ReaderScreen mutates the same BookModel; just re-sort and rebuild.
    setState(() {
      if (!_allBooks.any((b) => b.filePath == book.filePath)) {
        _allBooks.add(book);
      }
      _allBooks.sort((a, b) {
        final ad = a.lastOpened, bd = b.lastOpened;
        if (ad != null && bd != null) return bd.compareTo(ad);
        if (ad != null) return -1;
        if (bd != null) return 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    });
  }

  Future<void> _pickManualFile() async {
    final picked = await _scanner.pickSinglePdf();
    if (picked != null && mounted) await _openBook(picked);
  }

  @override
  Widget build(BuildContext context) {
    final showShelf = _searchQuery.isEmpty && _recent.isNotEmpty;
    final recentPaths = _recent.map((b) => b.filePath).toSet();
    final listBooks = showShelf
        ? _filtered.where((b) => !recentPaths.contains(b.filePath)).toList()
        : _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookshelf',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Rescan Storage',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _scan,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search PDFs...',
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
          if (_permissionDenied) _permissionBanner(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? const Center(child: Text('No PDF files found.'))
                : RefreshIndicator(
              onRefresh: _scan,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 84),
                children: [
                  if (showShelf) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 4, 16, 8),
                      child: Text('Continue Reading',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                    SizedBox(
                      height: 190,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _recent.length,
                        itemBuilder: (_, i) => ShelfCard(
                          book: _recent[i],
                          onTap: () => _openBook(_recent[i]),
                        ),
                      ),
                    ),
                    if (listBooks.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(18, 16, 16, 8),
                        child: Text('All Device PDFs',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                  ...listBooks.map((b) =>
                      BookCard(book: b, onTap: () => _openBook(b))),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickManualFile,
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text('Open File'),
      ),
    );
  }

  Widget _permissionBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
                'Storage access denied. Grant it to auto-find PDFs, or use "Open File".'),
          ),
          TextButton(onPressed: _scan, child: const Text('Grant')),
        ],
      ),
    );
  }
}