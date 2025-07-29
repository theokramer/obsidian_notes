import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share/share.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:developer' as developer;
import 'package:markdown_quill/markdown_quill.dart' as mdq;
import 'package:markdown/markdown.dart' as md;

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        quill.FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('de')],
      home: const NotesHome(),
    );
  }
}

class NotesHome extends StatefulWidget {
  const NotesHome({super.key});

  @override
  State<NotesHome> createState() => _NotesHomeState();
}

class NoteSearchResult {
  final FileSystemEntity file;
  final int? matchLine;
  final String? matchText;
  final String? firstLine;

  NoteSearchResult(this.file, {this.matchLine, this.matchText, this.firstLine});
}

class _NotesHomeState extends State<NotesHome> {
  String? folderPath;
  List<FileSystemEntity> notes = [];
  List<NoteSearchResult> filteredNotes = [];
  bool loading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFolder();
  }

  List<TextSpan> _buildSubtitleSpans(
    String date,
    int? matchLine,
    String? matchText,
    String query,
    String? firstLine,
  ) {
    if (query.isEmpty) {
      // No search: show first line of file
      final text = firstLine?.trim();
      return [TextSpan(text: '$date     ${text ?? ''}')];
    }

    if (matchText == null || query.isEmpty) {
      return [TextSpan(text: '$date     ')];
    }

    final lowerMatch = matchText.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerMatch.indexOf(lowerQuery);

    if (matchIndex == -1) {
      return [TextSpan(text: '$date     $matchText')];
    }

    try {
      final before = matchText.substring(0, matchIndex);
      final match = matchText.substring(matchIndex, matchIndex + query.length);
      final after = matchText.substring(matchIndex + query.length);

      return [
        TextSpan(text: '$date     '),
        TextSpan(text: before),
        TextSpan(
          text: match,
          style: const TextStyle(
            color: CupertinoColors.activeBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
        TextSpan(text: after),
      ];
    } catch (e) {
      return [TextSpan(text: '$date     $matchText')];
    }
  }

  Future<void> _loadFolder() async {
    loading = false;
    // final prefs = await SharedPreferences.getInstance();
    // final path = prefs.getString('vault_folder');

    // developer.log('Lade vault_folder aus SharedPreferences: $path');

    // if (path != null && Directory(path).existsSync()) {
    //   setState(() {
    //     folderPath = path;
    //   });
    //   _loadNotes(path);
    // } else {
    //   developer.log('Kein gültiger Vault-Pfad gefunden oder existiert nicht.');
    //   setState(() {
    //     loading = false;
    //   });
    // }
  }

  Future<void> _pickFolder() async {
    String? selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vault_folder', selected);
      setState(() {
        folderPath = selected;
      });
      _loadNotes(selected);
    }
  }

  void _loadNotes(String path) {
    final dir = Directory(path);
    final files =
        dir.listSync().where((f) {
          final isFile = FileSystemEntity.isFileSync(f.path);
          final isMd = f.path.endsWith('.md');
          return isFile && isMd;
        }).toList()..sort(
          (a, b) => File(
            b.path,
          ).lastModifiedSync().compareTo(File(a.path).lastModifiedSync()),
        );
    setState(() {
      notes = files;
      _filterNotes();
      loading = false;
    });
  }

  void _filterNotes() {
    if (searchQuery.isEmpty) {
      filteredNotes = notes.map((note) {
        final file = File(note.path);
        final content = file.readAsStringSync();
        final lines = content
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
        final firstLine = lines.isNotEmpty ? lines.first : '';
        return NoteSearchResult(note, firstLine: firstLine);
      }).toList();
    } else {
      final query = searchQuery.toLowerCase();
      filteredNotes = notes
          .map((note) {
            final file = File(note.path);
            final content = file.readAsStringSync();
            final lines = content.split('\n');

            for (int i = 0; i < lines.length; i++) {
              if (lines[i].toLowerCase().contains(query)) {
                return NoteSearchResult(
                  note,
                  matchLine: i + 1,
                  matchText: lines[i].trim(),
                );
              }
            }

            final nameMatch = file.uri.pathSegments.last.toLowerCase().contains(
              query,
            );
            if (nameMatch) {
              return NoteSearchResult(note);
            }

            return null;
          })
          .whereType<NoteSearchResult>()
          .toList();
    }
  }

  void _createNote() async {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => NoteView(
          file: File(''), // Dummy
          initialContent: '',
          onSave: () => _loadNotes(folderPath!),
          createNew: true,
          folderPath: folderPath!,
        ),
      ),
    );
  }

  void _openNote(FileSystemEntity note) async {
    final content = await File(note.path).readAsString();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => NoteView(
          file: File(note.path),
          initialContent: content,
          onSave: () => _loadNotes(folderPath!),
          createNew: false,
        ),
      ),
    );
  }

  void _deleteNote(FileSystemEntity note) async {
    await File(note.path).delete();
    _loadNotes(folderPath!);
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: CupertinoSearchTextField(
        placeholder: 'Search',
        onChanged: (value) {
          setState(() {
            searchQuery = value;
            _filterNotes();
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text('Notizen')),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (folderPath == null) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Vault wählen'),
        ),
        child: Center(
          child: CupertinoButton.filled(
            onPressed: _pickFolder,
            child: const Text('Vault auswählen'),
          ),
        ),
      );
    }
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text(
          'Notizen',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _pickFolder,
          child: const Icon(CupertinoIcons.folder_open),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Die Liste
            Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: CupertinoSearchTextField(
                    placeholder: 'Search',
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value;
                        _filterNotes();
                      });
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: filteredNotes.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Keine Treffer gefunden.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: CupertinoColors.inactiveGray,
                                ),
                              ),
                            )
                          : CupertinoListSection.insetGrouped(
                              hasLeading: false,
                              margin: EdgeInsets.zero,
                              children: filteredNotes.map((result) {
                                final file = File(result.file.path);
                                final fileName = file.uri.pathSegments.last
                                    .replaceAll('.md', '');
                                final modified = file.lastModifiedSync();
                                final formattedDate = DateFormat(
                                  'dd.MM.yyyy',
                                ).format(modified);

                                String subtitleText = formattedDate;
                                if (result.matchText != null &&
                                    result.matchLine != null) {
                                  subtitleText +=
                                      '  (Zeile ${result.matchLine}): ${result.matchText}';
                                }

                                return CupertinoListTile.notched(
                                  title: Text(fileName),
                                  subtitle: Text.rich(
                                    TextSpan(
                                      children: _buildSubtitleSpans(
                                        formattedDate,
                                        result.matchLine,
                                        result.matchText,
                                        searchQuery,
                                        result.firstLine,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: CupertinoColors.inactiveGray,
                                      ),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  onTap: () {
                                    Navigator.of(context).push(
                                      CupertinoPageRoute(
                                        builder: (context) => NoteView(
                                          file: file,
                                          initialContent: file
                                              .readAsStringSync(),
                                          onSave: () {
                                            setState(() {});
                                          },
                                          createNew: false,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                ),
              ],
            ),

            // Floating Action Button rechts unten
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                onPressed: _createNote,
                backgroundColor: Colors.black,
                child: const Icon(CupertinoIcons.square_pencil),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoteView extends StatefulWidget {
  File file;
  final String initialContent;
  final VoidCallback onSave;
  final bool createNew;
  final String? folderPath;

  NoteView({
    required this.file,
    required this.initialContent,
    required this.onSave,
    super.key,
    required this.createNew,
    this.folderPath,
  });

  @override
  State<NoteView> createState() => _NoteViewState();
}

class _NoteViewState extends State<NoteView> {
  late quill.QuillController _controller;
  late String title;
  late FocusNode _focusNode;
  Timer? _autosaveTimer;
  bool editing = true;
  bool saving = false;
  bool _isToolbarVisible = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    if (widget.createNew) {
      title = "Neue Notiz";
    } else {
      final fileName = widget.file.uri.pathSegments.last.replaceAll('.md', '');
      title = fileName.isNotEmpty ? fileName : 'Neue Notiz';
    }

    final converter = mdq.MarkdownToDelta(markdownDocument: md.Document());
    final delta = converter.convert(widget.initialContent);
    _controller = quill.QuillController(
      document: delta.isEmpty
          ? quill.Document()
          : quill.Document.fromDelta(delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller.addListener(_onContentChanged);
  }

  void _handleFocusChange() {
    setState(() {
      _isToolbarVisible =
          _focusNode.hasFocus || !_controller.selection.isCollapsed;
      developer.log('Focus changed: _isToolbarVisible = $_isToolbarVisible');
    });
  }

  void _onContentChanged() {
    final newTitle = _getCurrentTitle();

    if (newTitle.isNotEmpty && widget.file.path.contains('yyyy-MM-dd')) {
      _renameFileIfNeeded(newTitle);
    }

    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(seconds: 2), _save);
  }

  String _getCurrentTitle() {
    final plainText = _controller.document.toPlainText();
    final lines = plainText.split('\n');
    return lines.isNotEmpty ? lines.first.trim() : '';
  }

  Future<void> _renameFileIfNeeded(String newTitle) async {
    final sanitizedTitle = newTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final directory = widget.file.parent;
    final newPath = '${directory.path}/$sanitizedTitle.md';

    if (widget.file.path != newPath && !File(newPath).existsSync()) {
      await widget.file.rename(newPath);
      setState(() {
        widget.file = File(newPath); // ACHTUNG: ggf. final entfernen!
        title = newTitle;
      });
      widget.onSave(); // damit die Liste aktualisiert wird
    }
  }

  Future<void> _save() async {
    if (!editing) return;
    setState(() => saving = true);

    try {
      final converter = mdq.DeltaToMarkdown();
      String markdown = converter.convert(_controller.document.toDelta());

      final currentTitle = _getCurrentTitle();
      if (currentTitle.isEmpty) return;

      // Entferne erste Zeile, wenn sie dem Titel entspricht
      final lines = markdown.split('\n');
      if (widget.createNew &&
          lines.isNotEmpty &&
          lines.first.replaceAll(RegExp(r'^#+\s*'), '').trim() ==
              currentTitle.trim()) {
        lines.removeAt(0);
        markdown = lines.join('\n').trimLeft();
      }

      // Pfad festlegen, falls neue Datei
      if (widget.createNew &&
          widget.folderPath != null &&
          widget.file.path.isEmpty) {
        final safeTitle = currentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final newPath = '${widget.folderPath!}/$safeTitle.md';
        widget.file = File(newPath);
      }

      await widget.file.writeAsString(markdown);
      widget.onSave();

      setState(() {
        saving = false;
        title = currentTitle;
      });
    } catch (e) {
      setState(() => saving = false);
      // Fehlerbehandlung, z. B. Dialog anzeigen
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _save();
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: GestureDetector(
          child: Icon(CupertinoIcons.back),
          onTap: () {
            _save();
            setState(() => editing = false);
            Navigator.of(context).pop();
          },
        ),
        middle: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: quill.QuillEditor.basic(
                  controller: _controller,
                  focusNode: _focusNode,
                  config: quill.QuillEditorConfig(
                    placeholder: 'Start writing your note...',
                    customStyles: quill.DefaultStyles(
                      paragraph: quill.DefaultTextBlockStyle(
                        const TextStyle(
                          color: CupertinoColors.black,
                          fontWeight: FontWeight.normal,
                          fontSize: 16,
                        ),
                        const quill.HorizontalSpacing(0, 0),
                        const quill.VerticalSpacing(0, 0),
                        const quill.VerticalSpacing(0, 0),
                        null,
                      ),
                      h1: quill.DefaultTextBlockStyle(
                        const TextStyle(
                          color: CupertinoColors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        const quill.HorizontalSpacing(0, 0),
                        const quill.VerticalSpacing(8, 0),
                        const quill.VerticalSpacing(0, 0),
                        null,
                      ),
                      h2: quill.DefaultTextBlockStyle(
                        const TextStyle(
                          color: Colors.black54,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                        const quill.HorizontalSpacing(0, 0),
                        const quill.VerticalSpacing(6, 0),
                        const quill.VerticalSpacing(0, 0),
                        null,
                      ),
                      h3: quill.DefaultTextBlockStyle(
                        const TextStyle(
                          color: CupertinoColors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        const quill.HorizontalSpacing(0, 0),
                        const quill.VerticalSpacing(8, 0),
                        const quill.VerticalSpacing(0, 0),
                        null,
                      ),
                      h4: quill.DefaultTextBlockStyle(
                        const TextStyle(
                          color: CupertinoColors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        const quill.HorizontalSpacing(0, 0),
                        const quill.VerticalSpacing(8, 0),
                        const quill.VerticalSpacing(0, 0),
                        null,
                      ),
                      // Füge den Stil für Listen hinzu
                      lists: quill.DefaultListBlockStyle(
                        const TextStyle(
                          color: CupertinoColors
                              .black, // Das gilt für Text UND Bullet
                          fontSize: 16,
                        ),
                        const quill.HorizontalSpacing(0, 0),
                        const quill.VerticalSpacing(4, 0),
                        const quill.VerticalSpacing(0, 0),
                        null,
                        null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isToolbarVisible)
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  border: Border(
                    top: BorderSide(color: CupertinoColors.separator),
                  ),
                ),
                child: quill.QuillSimpleToolbar(
                  controller: _controller,
                  config: quill.QuillSimpleToolbarConfig(
                    showBoldButton: true,
                    showItalicButton: true,
                    showUnderLineButton: true,
                    showStrikeThrough: true,
                    showInlineCode: false,
                    showColorButton: false,
                    showBackgroundColorButton: false,
                    showClearFormat: false,
                    showHeaderStyle: true,
                    showListNumbers: true,
                    showListBullets: true,
                    showListCheck: false,
                    showCodeBlock: false,
                    showQuote: false,
                    showIndent: false,
                    showLink: false,
                    showUndo: false,
                    showRedo: false,
                    showDirection: false,
                    showAlignmentButtons: false,
                    showFontFamily: false,
                    showFontSize: false,
                    showDividers: false,
                    showSearchButton: false,
                    showSuperscript: false,
                    showSubscript: false,
                    buttonOptions: quill.QuillSimpleToolbarButtonOptions(
                      base: quill.QuillToolbarBaseButtonOptions(
                        iconTheme: quill.QuillIconTheme(
                          iconButtonSelectedData: quill.IconButtonData(
                            color: CupertinoColors.black,
                            iconSize: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
