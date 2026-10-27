import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/at_colors.dart';
import '../../core/theme/at_tokens.dart';
import 'learn_quest_api.dart';

// Learn Quest (Abdulelah): books from Open Library under the title of a new habit or goal,
// shown only when the title is about reading (the same backend search as «رحلة التعلّم»)
final _reading = RegExp(r'قراء|أقرأ|اقرأ|اقرا|كتاب|كتب|رواي|read|book', caseSensitive: false);
// words that say how much, not what to read: dropped from the search
final _noise = RegExp(r'[0-9٠-٩]+|صفحات|صفحة|صفحه|دقائق|دقيقة|دقيقه|ساعات|ساعة|ساعه|يوميًا|يوميا|كل يوم|بالأسبوع|بالاسبوع');

bool isReadingTitle(String title) => _reading.hasMatch(title);

class BookSuggestions extends StatefulWidget {
  final TextEditingController title;

  const BookSuggestions({super.key, required this.title});

  @override
  State<BookSuggestions> createState() => _BookSuggestionsState();
}

class _BookSuggestionsState extends State<BookSuggestions> {
  late final _api = LearnQuestApi(context.read<ApiClient>());
  Timer? _wait;
  String _query = '';
  List<LearnResource> _books = [];
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.title.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    _wait?.cancel();
    _request++;
    widget.title.removeListener(_changed);
    super.dispose();
  }

  // waits until the member stops typing, then searches once
  void _changed() {
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 700), _search);
  }

  Future<void> _search() async {
    final title = widget.title.text.trim();
    if (!isReadingTitle(title)) {
      if (mounted && (_books.isNotEmpty || _query.isNotEmpty)) {
        setState(() {
          _books = [];
          _query = '';
        });
      }
      return;
    }
    final cleaned = title.replaceAll(_noise, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    var query = cleaned.isEmpty ? title : cleaned;
    if (query.length > 100) query = query.substring(0, 100).trim(); // the backend takes 100 characters max
    if (query == _query) return;
    final id = ++_request;
    setState(() {
      _query = query;
      _loading = true;
    });
    try {
      final books = await _api.search(query, type: 'books');
      if (!mounted || id != _request) return;
      setState(() => _books = books.take(8).toList());
    } catch (_) {
      if (mounted && id == _request) setState(() => _books = []); // no books is fine, the form still works
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(LearnResource book) async {
    final uri = Uri.tryParse(book.url ?? '');
    if (uri == null || !uri.hasScheme) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_query.isEmpty || (!_loading && _books.isEmpty)) return const SizedBox.shrink();
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.menu_book_rounded, size: 18, color: c.primary),
            const SizedBox(width: 6),
            Expanded(child: Text('كتب تساعدك', style: text.labelLarge!.copyWith(fontWeight: FontWeight.w700))),
            Text('من Open Library', style: text.labelSmall!.copyWith(color: c.inkSubtle)),
          ]),
          const SizedBox(height: Space.s2),
          SizedBox(
            height: 190,
            child: _loading && _books.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _books.length,
                    separatorBuilder: (_, __) => const SizedBox(width: Space.s2),
                    itemBuilder: (context, i) => _BookCard(book: _books[i], onTap: () => _open(_books[i])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final LearnResource book;
  final VoidCallback onTap;

  const _BookCard({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final cover = Container(
      color: c.surfaceSunken,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book_rounded, color: c.inkSubtle),
    );
    return SizedBox(
      width: 104,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: SizedBox(
                width: 104,
                height: 132,
                child: book.imageUrl == null
                    ? cover
                    : Image.network(book.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => cover),
              ),
            ),
            const SizedBox(height: 6),
            Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.labelMedium!.copyWith(fontWeight: FontWeight.w700)),
            if (book.creator.trim().isNotEmpty)
              Text(book.creator, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelSmall!.copyWith(color: c.inkSubtle)),
          ],
        ),
      ),
    );
  }
}
