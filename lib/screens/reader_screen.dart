import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/book_model.dart';
import '../services/storage_service.dart';

class ReaderScreen extends StatefulWidget {
  final BookModel book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _kNight = 'reader_night_mode';
  static const _kHorizontal = 'reader_horizontal';

  final PdfViewerController _pdfController = PdfViewerController();
  final StorageService _storage = StorageService();

  late int _currentPage;
  int _totalPages = 0;
  bool _settingsLoaded = false;
  bool _isNightMode = false;
  bool _horizontal = false;
  bool _showControls = true;
  double? _dragValue;

  Offset? _downPos;
  int _downTime = 0;

  static const ColorFilter _invertFilter = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  @override
  void initState() {
    super.initState();
    _currentPage = widget.book.lastPage > 0 ? widget.book.lastPage : 1;
    _totalPages = widget.book.totalPages;
    WakelockPlus.enable();
    widget.book.lastOpened = DateTime.now();
    _storage.saveBookProgress(widget.book);
    _loadSettings();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _storage.flushNow();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isNightMode = prefs.getBool(_kNight) ?? false;
      _horizontal = prefs.getBool(_kHorizontal) ?? false;
      _settingsLoaded = true;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  void _onPageChanged(int? page) {
    if (page == null || page <= 0) return;
    setState(() => _currentPage = page);
    widget.book.lastPage = page;
    widget.book.lastOpened = DateTime.now();
    _storage.saveBookProgress(widget.book);
  }

  void _toggleBookmark() {
    setState(() {
      final bm = widget.book.bookmarks;
      if (bm.contains(_currentPage)) {
        bm.remove(_currentPage);
      } else {
        bm.add(_currentPage);
        bm.sort();
      }
    });
    _storage.saveBookProgress(widget.book);
  }

  void _goTo(int page) {
    if (!_pdfController.isReady) return;
    _pdfController.goToPage(pageNumber: page);
  }

  // Horizontal page layout (pages side by side)
  PdfPageLayout _horizontalLayout(
      List<PdfPage> pages, PdfViewerParams params) {
    final height =
        pages.fold<double>(0.0, (m, p) => max(m, p.height)) + params.margin * 2;
    final rects = <Rect>[];
    double x = params.margin;
    for (final p in pages) {
      rects.add(Rect.fromLTWH(x, (height - p.height) / 2, p.width, p.height));
      x += p.width + params.margin;
    }
    return PdfPageLayout(pageLayouts: rects, documentSize: Size(x, height));
  }

  void _showJumpToPageDialog() {
    final controller = TextEditingController(text: _currentPage.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jump to Page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Enter page (1 - $_totalPages)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final target = int.tryParse(controller.text);
              if (target != null && target >= 1 && target <= _totalPages) {
                _goTo(target);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  void _showBookmarksSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Saved Bookmarks',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            if (widget.book.bookmarks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No bookmarks added yet.'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.book.bookmarks.length,
                  itemBuilder: (_, i) {
                    final page = widget.book.bookmarks[i];
                    return ListTile(
                      leading: const Icon(Icons.bookmark_rounded),
                      title: Text('Page $page'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          setState(() => widget.book.bookmarks.remove(page));
                          _storage.saveBookProgress(widget.book);
                          Navigator.pop(ctx);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _goTo(page);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewer() {
    Widget viewer = PdfViewer.file(
      widget.book.filePath,
      key: ValueKey(_horizontal), // rebuild on direction change, resumes at _currentPage
      controller: _pdfController,
      params: PdfViewerParams(
        layoutPages: _horizontal ? _horizontalLayout : null,
        calculateInitialPageNumber: (document, controller) =>
            _currentPage.clamp(1, document.pages.length),
        onViewerReady: (document, controller) {
          final total = document.pages.length;
          widget.book.totalPages = total;
          _storage.saveBookProgress(widget.book);
          if (mounted) setState(() => _totalPages = total);
        },
        onPageChanged: _onPageChanged,
      ),
    );

    if (_isNightMode) {
      viewer = ColorFiltered(colorFilter: _invertFilter, child: viewer);
    }

    // Listener does not enter the gesture arena, so PDF links/zoom/scroll still work.
    return Listener(
      onPointerDown: (e) {
        _downPos = e.position;
        _downTime = DateTime.now().millisecondsSinceEpoch;
      },
      onPointerUp: (e) {
        final start = _downPos;
        if (start == null) return;
        final quick = DateTime.now().millisecondsSinceEpoch - _downTime < 250;
        if (quick && (e.position - start).distance < 10) {
          setState(() => _showControls = !_showControls);
        }
        _downPos = null;
      },
      child: viewer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBookmarked = widget.book.bookmarks.contains(_currentPage);

    return Scaffold(
      body: !_settingsLoaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          Positioned.fill(child: _buildViewer()),

          // Top bar (overlay, does not resize the viewer)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              offset: _showControls ? Offset.zero : const Offset(0, -1),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Material(
                  color: cs.surface.withValues(alpha: 0.96),
                  elevation: 2,
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: kToolbarHeight,
                      child: Row(
                        children: [
                          const BackButton(),
                          Expanded(
                            child: Text(
                              widget.book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Scroll direction',
                            icon: Icon(_horizontal
                                ? Icons.swap_vert_rounded
                                : Icons.swap_horiz_rounded),
                            onPressed: () {
                              setState(() => _horizontal = !_horizontal);
                              _saveSetting(_kHorizontal, _horizontal);
                            },
                          ),
                          IconButton(
                            tooltip: 'Night Reading Mode',
                            icon: Icon(_isNightMode
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded),
                            onPressed: () {
                              setState(
                                      () => _isNightMode = !_isNightMode);
                              _saveSetting(_kNight, _isNightMode);
                            },
                          ),
                          IconButton(
                            tooltip: 'Bookmark Page',
                            icon: Icon(isBookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded),
                            onPressed: _toggleBookmark,
                          ),
                          IconButton(
                            tooltip: 'View Bookmarks',
                            icon: const Icon(Icons.bookmarks_outlined),
                            onPressed: _showBookmarksSheet,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom bar
          if (_totalPages > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                offset: _showControls ? Offset.zero : const Offset(0, 1),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Material(
                    color: cs.surface.withValues(alpha: 0.96),
                    elevation: 2,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _showJumpToPageDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Page $_currentPage / $_totalPages',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                value: (_dragValue ??
                                    _currentPage.toDouble())
                                    .clamp(1.0, _totalPages.toDouble()),
                                min: 1,
                                max: max(2.0, _totalPages.toDouble()),
                                onChanged: (v) =>
                                    setState(() => _dragValue = v),
                                onChangeEnd: (v) {
                                  setState(() => _dragValue = null);
                                  _goTo(v.round());
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}