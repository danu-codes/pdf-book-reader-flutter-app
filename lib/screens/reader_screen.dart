import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/book_model.dart';
import '../services/storage_service.dart';

enum _ReaderThemeMode { day, sepia, night }

class ReaderScreen extends StatefulWidget {
  final BookModel book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _kTheme = 'reader_theme_mode';
  static const _kHorizontal = 'reader_horizontal';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final PdfViewerController _pdfController = PdfViewerController();
  late final PdfTextSearcher _textSearcher;
  final TextEditingController _searchController = TextEditingController();
  final StorageService _storage = StorageService();

  late int _currentPage;
  int _totalPages = 0;
  bool _settingsLoaded = false;
  _ReaderThemeMode _themeMode = _ReaderThemeMode.day;
  bool _horizontal = false;
  bool _showControls = true;
  bool _isSearching = false;
  double? _dragValue;

  List<PdfOutlineNode> _outline = [];
  Offset? _downPos;
  int _downTime = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.book.lastPage > 0 ? widget.book.lastPage : 1;
    _totalPages = widget.book.totalPages;
    _textSearcher = PdfTextSearcher(_pdfController)..addListener(_onSearchUpdate);

    WakelockPlus.enable();
    widget.book.lastOpened = DateTime.now();
    _storage.saveBookProgress(widget.book);
    _loadSettings();
  }

  @override
  void dispose() {
    _textSearcher.removeListener(_onSearchUpdate);
    _textSearcher.dispose();
    _searchController.dispose();
    WakelockPlus.disable();
    _storage.flushNow();
    super.dispose();
  }

  void _onSearchUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final themeIndex = prefs.getInt(_kTheme) ?? 0;
    final keepAwake = prefs.getBool('reader_wakelock') ?? true;
    if (keepAwake) {
      WakelockPlus.enable();
    }
    setState(() {
      _themeMode = _ReaderThemeMode
          .values[themeIndex.clamp(0, _ReaderThemeMode.values.length - 1)];
      _horizontal = prefs.getBool(_kHorizontal) ?? false;
      _settingsLoaded = true;
    });
  }

  Future<void> _cycleThemeMode() async {
    final nextIndex = (_themeMode.index + 1) % _ReaderThemeMode.values.length;
    final nextMode = _ReaderThemeMode.values[nextIndex];
    setState(() => _themeMode = nextMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTheme, nextMode.index);
  }

  Future<void> _toggleDirection() async {
    setState(() => _horizontal = !_horizontal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHorizontal, _horizontal);
  }

  void _onPageChanged(int? page) {
    if (page == null || page <= 0) return;
    setState(() => _currentPage = page);
    widget.book.lastPage = page;
    widget.book.lastOpened = DateTime.now();
    if (_totalPages > 0 && page >= _totalPages) {
      widget.book.isManuallyFinished = true;
    }
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
              child: Text(
                'Saved Bookmarks',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
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
    final bgColor = switch (_themeMode) {
      _ReaderThemeMode.day => const Color(0xFFF2F2F7),
      _ReaderThemeMode.sepia => const Color(0xFFE8DEC8),
      _ReaderThemeMode.night => const Color(0xFF121212),
    };

    final viewer = Container(
      color: bgColor,
      child: PdfViewer.file(
        widget.book.filePath,
        key: ValueKey(_horizontal),
        controller: _pdfController,
        params: PdfViewerParams(
          backgroundColor: bgColor,
          layoutPages: _horizontal ? _horizontalLayout : null,
          calculateInitialPageNumber: (document, controller) =>
              _currentPage.clamp(1, document.pages.length),
          onViewerReady: (document, controller) async {
            final total = document.pages.length;
            widget.book.totalPages = total;
            _storage.saveBookProgress(widget.book);
            final outline = await document.loadOutline();
            if (mounted) {
              setState(() {
                _totalPages = total;
                _outline = outline;
              });
            }
          },
          onPageChanged: _onPageChanged,
          pagePaintCallbacks: [
            _textSearcher.pageTextMatchPaintCallback,
          ],
        ),
      ),
    );

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
      child: Stack(
        children: [
          Positioned.fill(child: viewer),
          if (_themeMode != _ReaderThemeMode.day)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: _themeMode == _ReaderThemeMode.sepia
                      ? const Color(0x28D4A359)
                      : const Color(0x55000000),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOutlineDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Table of Contents',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: _outline.isEmpty
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This PDF does not include embedded chapters.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
                  : ListView(
                children: _buildOutlineTiles(_outline, 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildOutlineTiles(List<PdfOutlineNode> nodes, int depth) {
    final tiles = <Widget>[];
    for (final node in nodes) {
      final destPage = node.dest?.pageNumber;
      tiles.add(
        ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + depth * 16.0, right: 16),
          title: Text(
            node.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: depth == 0 ? 14 : 13,
              fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          trailing: destPage != null
              ? Text(
            'p.$destPage',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
            ),
          )
              : null,
          onTap: destPage != null
              ? () {
            Navigator.pop(context);
            _goTo(destPage);
          }
              : null,
        ),
      );
      if (node.children.isNotEmpty) {
        tiles.addAll(_buildOutlineTiles(node.children, depth + 1));
      }
    }
    return tiles;
  }

  Widget _buildSearchBar(ColorScheme cs) {
    final matches = _textSearcher.matches;
    final currentIdx = _textSearcher.currentIndex;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            _textSearcher.resetTextSearch();
            _searchController.clear();
            setState(() => _isSearching = false);
          },
        ),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search text in book...',
              border: InputBorder.none,
            ),
            onChanged: (query) => _textSearcher.startTextSearch(query),
          ),
        ),
        if (matches.isNotEmpty)
          Text(
            '${(currentIdx ?? 0) + 1}/${matches.length}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed:
          matches.isEmpty ? null : () => _textSearcher.goToPrevMatch(),
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed:
          matches.isEmpty ? null : () => _textSearcher.goToNextMatch(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBookmarked = widget.book.bookmarks.contains(_currentPage);

    final (themeIcon, themeLabel) = switch (_themeMode) {
      _ReaderThemeMode.day => (Icons.wb_sunny_outlined, 'Day Mode'),
      _ReaderThemeMode.sepia => (Icons.auto_awesome_outlined, 'Warm Sepia'),
      _ReaderThemeMode.night => (Icons.dark_mode_rounded, 'Dim Night Mode'),
    };

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildOutlineDrawer(),
      body: !_settingsLoaded
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          Positioned.fill(child: _buildViewer()),
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
                      child: _isSearching
                          ? _buildSearchBar(cs)
                          : Row(
                        children: [
                          const BackButton(),
                          Expanded(
                            child: Text(
                              widget.book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Search in Book',
                            icon: const Icon(Icons.search_rounded),
                            onPressed: () =>
                                setState(() => _isSearching = true),
                          ),
                          IconButton(
                            tooltip: themeLabel,
                            icon: Icon(themeIcon),
                            onPressed: _cycleThemeMode,
                          ),
                          IconButton(
                            tooltip: _horizontal
                                ? 'Switch to Vertical Scroll'
                                : 'Switch to Horizontal Pages',
                            icon: Icon(_horizontal
                                ? Icons.swap_vert_rounded
                                : Icons.swap_horiz_rounded),
                            onPressed: _toggleDirection,
                          ),
                          IconButton(
                            tooltip: 'Bookmark Page',
                            icon: Icon(isBookmarked
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded),
                            onPressed: _toggleBookmark,
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'toc') {
                                _scaffoldKey.currentState
                                    ?.openEndDrawer();
                              } else if (value == 'bookmarks') {
                                _showBookmarksSheet();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'toc',
                                child: ListTile(
                                  leading: Icon(Icons.toc_rounded),
                                  title: Text('Chapters'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'bookmarks',
                                child: ListTile(
                                  leading: Icon(
                                      Icons.bookmarks_outlined),
                                  title: Text('Saved Bookmarks'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
                                    fontSize: 13,
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
                            Text(
                              '${((_currentPage / _totalPages) * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
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