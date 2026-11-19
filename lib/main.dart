import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NotesApp());

// ───────────────────────── Model ─────────────────────────

const _lightColors = [
  Color(0xFFFFFFFF),
  Color(0xFFFFE0E0),
  Color(0xFFFFF1C9),
  Color(0xFFDDF5D6),
  Color(0xFFD6ECFF),
  Color(0xFFEBDDFF),
];
const _darkColors = [
  Color(0xFF2A2A2E),
  Color(0xFF4A2C2C),
  Color(0xFF4A402A),
  Color(0xFF2B4228),
  Color(0xFF263B52),
  Color(0xFF3D2F52),
];

class Note {
  String id;
  String title;
  String body;
  int color;
  bool pinned;
  DateTime updated;

  Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.color = 0,
    this.pinned = false,
    DateTime? updated,
  }) : updated = updated ?? DateTime.now();

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'color': color,
        'pinned': pinned,
        'updated': updated.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        color: j['color'] as int? ?? 0,
        pinned: j['pinned'] as bool? ?? false,
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
      );
}

// ───────────────────────── Store ─────────────────────────

class NotesStore extends ChangeNotifier {
  static const _key = 'notes_v1';
  final List<Note> _notes = [];
  String query = '';

  List<Note> get visible {
    final q = query.trim().toLowerCase();
    final list = _notes
        .where((n) =>
            q.isEmpty ||
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updated.compareTo(a.updated);
    });
    return list;
  }

  bool get hasAny => _notes.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as List;
        _notes
          ..clear()
          ..addAll(data.map((e) => Note.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_notes.map((n) => n.toJson()).toList()));
  }

  void upsert(Note n) {
    n.updated = DateTime.now();
    if (!_notes.any((x) => x.id == n.id)) _notes.add(n);
    _save();
    notifyListeners();
  }

  void remove(Note n) {
    _notes.removeWhere((x) => x.id == n.id);
    _save();
    notifyListeners();
  }

  void restore(Note n) {
    _notes.add(n);
    _save();
    notifyListeners();
  }

  void cleanupEmpty() {
    _notes.removeWhere((n) => n.isEmpty);
    _save();
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }
}

final store = NotesStore();

// ───────────────────────── App ─────────────────────────

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF6F6F9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121214),
      ),
      home: const HomePage(),
    );
  }
}

Color _noteColor(BuildContext context, int i) =>
    (Theme.of(context).brightness == Brightness.dark ? _darkColors : _lightColors)[i];

String _fmt(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day} ${m[d.month - 1]}, $h:$mm $ap';
}

Route<void> _smoothRoute(Widget page) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );

// ───────────────────────── Home ─────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    store.load();
  }

  Future<void> _open(Note note) async {
    await Navigator.of(context).push(_smoothRoute(EditorPage(note: note)));
    store.cleanupEmpty();
  }

  void _newNote() => _open(Note(id: DateTime.now().microsecondsSinceEpoch.toString()));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newNote,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New note'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final notes = store.visible;
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              const SliverAppBar.large(title: Text('My Notes')),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SearchBar(
                    hintText: 'Search notes',
                    leading: const Icon(Icons.search_rounded),
                    elevation: const WidgetStatePropertyAll(0),
                    onChanged: store.setQuery,
                  ),
                ),
              ),
              if (notes.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded, size: 88, color: cs.outline),
                        const SizedBox(height: 12),
                        Text(
                          store.hasAny ? 'No matching notes' : 'No notes yet\nTap "New note" to start',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.outline, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList.separated(
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _NoteCard(
                      key: ValueKey(notes[i].id),
                      note: notes[i],
                      onTap: () => _open(notes[i]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  const _NoteCard({super.key, required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('dis_${note.id}'),
      background: Container(
        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
      ),
      onDismissed: (_) {
        store.remove(note);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: const Text('Note deleted'),
            action: SnackBarAction(label: 'UNDO', onPressed: () => store.restore(note)),
          ));
      },
      child: Material(
        color: _noteColor(context, note.color),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        note.title.trim().isEmpty ? 'Untitled' : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (note.pinned) Icon(Icons.push_pin_rounded, size: 18, color: cs.primary),
                  ],
                ),
                if (note.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    note.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface.withAlpha(180), height: 1.35),
                  ),
                ],
                const SizedBox(height: 10),
                Text(_fmt(note.updated), style: TextStyle(fontSize: 12, color: cs.outline)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Editor ─────────────────────────

class EditorPage extends StatefulWidget {
  final Note note;
  const EditorPage({super.key, required this.note});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late Note n;

  @override
  void initState() {
    super.initState();
    n = widget.note;
    _title = TextEditingController(text: n.title);
    _body = TextEditingController(text: n.body);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed() {
    n.title = _title.text;
    n.body = _body.text;
    if (!n.isEmpty) store.upsert(n);
    setState(() {});
  }

  void _pickColor() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_lightColors.length, (i) {
            final selected = n.color == i;
            return GestureDetector(
              onTap: () {
                setState(() => n.color = i);
                if (!n.isEmpty) store.upsert(n);
                Navigator.pop(ctx);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: selected ? 48 : 42,
                height: selected ? 48 : 42,
                decoration: BoxDecoration(
                  color: _noteColor(context, i),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: selected ? 3 : 1.5,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _noteColor(context, n.color)),
      duration: const Duration(milliseconds: 300),
      builder: (context, bg, _) => Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              tooltip: 'Pin',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  key: ValueKey(n.pinned),
                  color: n.pinned ? cs.primary : null,
                ),
              ),
              onPressed: () {
                setState(() => n.pinned = !n.pinned);
                if (!n.isEmpty) store.upsert(n);
              },
            ),
            IconButton(
              tooltip: 'Color',
              icon: const Icon(Icons.palette_outlined),
              onPressed: _pickColor,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                store.remove(n);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                onChanged: (_) => _changed(),
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                ),
              ),
              Text(_fmt(n.updated), style: TextStyle(fontSize: 12, color: cs.outline)),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _body,
                  onChanged: (_) => _changed(),
                  autofocus: n.isEmpty,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 17, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Start typing...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
