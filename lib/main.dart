// lib/main.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:uuid/uuid.dart';
import 'notes_services.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Notes Upgraded',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const NotesHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SavedItem {
  final String id;
  final String title;
  final String path;
  final String dateIso;
  SavedItem({required this.id, required this.title, required this.path, required this.dateIso});
  Map<String, String> toMap() => {'id': id, 'title': title, 'path': path, 'dateIso': dateIso};
  static SavedItem fromMap(Map<String, dynamic> m) =>
      SavedItem(id: m['id'], title: m['title'], path: m['path'], dateIso: m['dateIso']);
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});
  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final TextEditingController _topicCtrl = TextEditingController();
  bool _loading = false;
  bool _generating = false;
  List<SavedItem> _history = [];
  String _saveDirectoryHint = "Downloads (default)";
  final _prefsKey = "saved_pdf_list";
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _determineDefaultSaveDir();
  }

  Future<void> _determineDefaultSaveDir() async {
    if (Platform.isAndroid) {
      _saveDirectoryHint = "Downloads (default)";
    } else {
      _saveDirectoryHint = "Documents";
    }
    setState(() {});
  }

  Future<void> _loadHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_prefsKey) ?? [];
    final items = raw.map((s) {
      final map = Map<String, dynamic>.from(jsonDecode(s));
      return SavedItem.fromMap(map);
    }).toList();
    setState(() => _history = items.reversed.toList());
  }

  Future<void> _saveToHistory(SavedItem item) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_prefsKey) ?? [];
    list.add(jsonEncode(item.toMap()));
    await sp.setStringList(_prefsKey, list);
    await _loadHistory();
  }

  Future<void> _removeFromHistory(String id) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_prefsKey) ?? [];
    list.removeWhere((s) => jsonDecode(s)['id'] == id);
    await sp.setStringList(_prefsKey, list);
    await _loadHistory();
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdk = androidInfo.version.sdkInt;

    if (sdk >= 33) {
      // Android 13+: no permission needed to write PDFs to the Download folder
      return true;
    } else if (sdk >= 30) {
      // Android 11 & 12
      final p = await Permission.manageExternalStorage.request();
      if (p.isGranted) return true;
      // if denied open settings
      if (p.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return p.isGranted;
    } else {
      // Android <=10
      final p = await Permission.storage.request();
      return p.isGranted;
    }
  }

  Future<Directory> _defaultSaveDirectory() async {
    if (Platform.isAndroid) {
      // Use Downloads folder (works across devices)
      final d = Directory("/storage/emulated/0/Download");
      return d;
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  Future<String> _askUserForDirectory() async {
    // Allow selecting a directory via file_picker (Android returns path)
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath != null) return dirPath;
    // fallback:
    final def = await _defaultSaveDirectory();
    return def.path;
  }

  Future<String> _savePdf(Uint8List bytes, String title, {String? folderPath}) async {
    final dirPath = folderPath ?? (await _defaultSaveDirectory()).path;
    final safe = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final filename = "$safe-${DateTime.now().toIso8601String().replaceAll(':', '-')}.pdf";
    final file = File("$dirPath/$filename");
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // Main generate flow (UI + permissions + choose save dir)
  Future<void> _onGeneratePressed() async {
    final topic = _topicCtrl.text.trim();
    if (topic.isEmpty) {
      _showSnack("Please enter a topic");
      return;
    }

    setState(() {
      _generating = true;
      _loading = true;
    });

    try {
      // request permission
      final ok = await _requestStoragePermission();
      if (!ok) {
        _showSnack("Storage permission not granted");
        return;
      }

      // allow user to pick a folder (optional)
      final pickedDir = await showDialog<String>(
        context: context,
        builder: (ctx) => _SaveFolderDialog(defaultHint: _saveDirectoryHint),
      );

      final chosenFolder = pickedDir ?? await _defaultSaveDirectory().then((d) => d.path);

      // start animated "AI typing" indicator while backend works
      setState(() {
        _loading = true;
      });

      final bytes = await NotesService.generatePdfBytes(topic, timeout: const Duration(seconds: 180));

      final savedPath = await _savePdf(bytes, topic, folderPath: chosenFolder);
      final savedItem = SavedItem(id: _uuid.v4(), title: topic, path: savedPath, dateIso: DateTime.now().toIso8601String());
      await _saveToHistory(savedItem);
      _showSnack("Saved: ${savedPath.split('/').last}");

      // open file
      await OpenFile.open(savedPath);
    } catch (e) {
      _showSnack("Failed: $e");
    } finally {
      setState(() {
        _loading = false;
        _generating = false;
      });
    }
  }

  void _showSnack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Widget _buildTopCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 20, offset: Offset(0, 8)),
        ],
        // backdropFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("AI Notes Generator", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text("Type a topic and get a 10-page summary as PDF", style: TextStyle(fontSize: 13, color: Colors.grey[300])),
          const SizedBox(height: 12),
          TextField(
            controller: _topicCtrl,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.03),
              hintText: "e.g. Data Structures in C++",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _generating ? null : _onGeneratePressed,
                icon: _generating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_generating ? "Generating…" : "Generate PDF"),
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () async {
                try {
                  final resp = await NotesService.ping();
                  _showSnack("Backend OK");
                } catch (e) {
                  _showSnack("Backend not reachable");
                }
              },
              child: const Text("Check"),
            )
          ]),
          const SizedBox(height: 10),
          // Animated helper text
          if (_generating)
            Row(children: [
              const SizedBox(width: 6),
              AnimatedTextKit(
                animatedTexts: [
                  TypewriterAnimatedText('AI is writing your notes...', speed: Duration(milliseconds: 60), textStyle: TextStyle(color: Colors.white70)),
                ],
                totalRepeatCount: 1,
              ),
            ])
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return Center(
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade800,
          highlightColor: Colors.grey.shade700,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: const [
                Icon(Icons.inbox, size: 64, color: Colors.white54),
                SizedBox(height: 8),
                Text("No PDFs yet — generate one!", style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _history.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white12),
      itemBuilder: (context, idx) {
        final it = _history[idx];
        return ListTile(
          leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
          title: Text(it.title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(DateTime.parse(it.dateIso).toLocal().toString(), style: TextStyle(color: Colors.white60, fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.open_in_new, color: Colors.white70),
              onPressed: () async {
                await OpenFile.open(it.path);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.white54),
              onPressed: () async {
                try {
                  final f = File(it.path);
                  if (await f.exists()) await f.delete();
                } catch (_) {}
                await _removeFromHistory(it.id);
                _showSnack("Deleted");
              },
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b1020),
      appBar: AppBar(
        title: const Text("AI Notes"),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopCard(),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildHistoryList(),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// simple dialog to let user choose folder or accept default
class _SaveFolderDialog extends StatelessWidget {
  final String defaultHint;
  const _SaveFolderDialog({required this.defaultHint});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Choose save location"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Default: $defaultHint", style: TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.folder_open),
          label: const Text("Pick folder"),
          onPressed: () async {
            final dir = await FilePicker.platform.getDirectoryPath();
            Navigator.of(context).pop(dir);
          },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text("Use Default")),
      ],
    );
  }
}
