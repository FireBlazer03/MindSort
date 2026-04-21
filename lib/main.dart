import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:add_2_calendar/add_2_calendar.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';
import 'gemini_helper.dart';
import 'platform_utils.dart';
import 'google_tasks_helper.dart';

// --- DATA MODEL ---
class MindTask {
  final String id;
  final String title;
  final String type;
  final String priority; // NEW: High, Medium, Low
  final DateTime? startTime;
  final List<String> subTasks;

  MindTask({
    required this.id, 
    required this.title, 
    required this.type,
    this.priority = 'Medium',
    this.startTime,
    this.subTasks = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'priority': priority,
    'startTime': startTime?.toIso8601String(),
    'subTasks': subTasks,
  };

  factory MindTask.fromJson(Map<String, dynamic> json) {
    return MindTask(
      id: json['id'] ?? DateTime.now().toString(),
      title: json['title'],
      type: json['type'],
      priority: json['priority'] ?? 'Medium',
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
      subTasks: List<String>.from(json['subTasks'] ?? []),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MindSortApp());
}

// --- THEME SYSTEM ---
enum MindTheme { zinc, cyberpunk, paper }

class ThemeManager extends ChangeNotifier {
  MindTheme _currentTheme = MindTheme.zinc;
  MindTheme get currentTheme => _currentTheme;

  void setTheme(MindTheme theme) {
    _currentTheme = theme;
    notifyListeners();
  }

  ThemeData get themeData {
    switch (_currentTheme) {
      case MindTheme.cyberpunk:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.cyanAccent,
            brightness: Brightness.dark,
            surface: const Color(0xFF0D0221),
            background: const Color(0xFF0D0221),
          ),
          textTheme: GoogleFonts.orbitronTextTheme(ThemeData.dark().textTheme),
          cardTheme: CardThemeData(
            color: const Color(0xFF1B065E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Colors.cyanAccent, width: 0.5),
            ),
          ),
        );
      case MindTheme.paper:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.brown,
            brightness: Brightness.light,
            surface: const Color(0xFFF5F5DC),
            background: const Color(0xFFF5F5DC),
          ),
          textTheme: GoogleFonts.specialEliteTextTheme(ThemeData.light().textTheme),
          cardTheme: CardThemeData(
            color: const Color(0xFFFFF8E1),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(0),
              side: const BorderSide(color: Colors.brown, width: 0.2),
            ),
          ),
        );
      default:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
            brightness: Brightness.dark,
            surface: const Color(0xFF09090B),
            background: const Color(0xFF09090B),
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
          cardTheme: CardThemeData(
            color: const Color(0xFF18181B),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        );
    }
  }
}

final themeManager = ThemeManager();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MindSortApp());
}

class MindSortApp extends StatefulWidget {
  const MindSortApp({super.key});

  @override
  State<MindSortApp> createState() => _MindSortAppState();
}

class _MindSortAppState extends State<MindSortApp> {
  @override
  void initState() {
    super.initState();
    themeManager.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MindSort',
      theme: themeManager.themeData,
      home: const RecordingScreen(),
    );
  }
}

// --- INTERACTIVE RECAP SCREEN ---
class WrappedScreen extends StatelessWidget {
  final List<MindTask> tasks;
  final int completedCount;

  const WrappedScreen({super.key, required this.tasks, required this.completedCount});

  @override
  Widget build(BuildContext context) {
    final taskCount = tasks.where((t) => t.type == 'task').length;
    final eventCount = tasks.where((t) => t.type == 'event').length;
    final noteCount = tasks.where((t) => t.type == 'note').length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.primary.withOpacity(0.2),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              FadeInDown(
                child: const Text(
                  "YOUR MINDSORT\nWRAPPED",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.black, height: 1),
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FadeInUp(
                    delay: const Duration(milliseconds: 500),
                    child: PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(value: taskCount.toDouble(), title: 'Tasks', color: Colors.indigoAccent, radius: 100),
                          PieChartSectionData(value: eventCount.toDouble(), title: 'Events', color: Colors.orangeAccent, radius: 100),
                          PieChartSectionData(value: noteCount.toDouble(), title: 'Notes', color: Colors.tealAccent, radius: 100),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              FadeIn(
                delay: const Duration(seconds: 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      _buildWrappedStat("Thoughts Captured", (tasks.length + completedCount).toString()),
                      _buildWrappedStat("Insights Processed", completedCount.toString()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Keep Sorting"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWrappedStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, opacity: 0.7)),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final AudioRecorder _audioRecorder;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isListening = false;
  bool _isProcessing = false;
  List<MindTask> _parsedTasks = []; 
  int _completedCount = 0;
  String? _error;
  String _currentFilter = 'All';
  String? _userApiKey;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  bool _isGoogleConnected = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _loadInitialData();
    _checkGoogleConnection();
  }

  // --- EXPORT LOGIC ---
  Future<void> _exportToCSV() async {
    List<List<dynamic>> rows = [
      ["Title", "Type", "Priority", "Start Time"]
    ];
    for (var task in _parsedTasks) {
      rows.add([task.title, task.type, task.priority, task.startTime?.toString() ?? ""]);
    }
    String csv = const ListToCsvConverter().convert(rows);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/mindsort_tasks.csv');
    await file.writeAsString(csv);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Exported to ${file.path}")));
  }

  Future<void> _exportToPDF() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      build: (pw.Context context) => pw.Column(
        children: [
          pw.Text("MindSort Task Export", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),
          ..._parsedTasks.map((t) => pw.Bullet(text: "${t.title} (${t.type}) - ${t.priority}")),
        ],
      ),
    ));
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/mindsort_tasks.pdf');
    await file.writeAsBytes(await pdf.save());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF Exported to ${file.path}")));
  }

  Future<void> _checkGoogleConnection() async {
    final connected = await GoogleTasksHelper.isConnected();
    setState(() => _isGoogleConnected = connected);
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleConnected) {
      await GoogleTasksHelper.signOut();
      setState(() => _isGoogleConnected = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Google Tasks Disconnected")),
        );
      }
    } else {
      final user = await GoogleTasksHelper.signIn();
      if (user != null) {
        setState(() => _isGoogleConnected = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Connected as ${user.displayName}")),
          );
        }
      }
    }
  }

  Future<void> _syncToGoogle(MindTask task) async {
    if (!_isGoogleConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please connect Google Tasks first")),
      );
      return;
    }

    final success = await GoogleTasksHelper.addTask(
      task.title,
      notes: "Type: ${itemTypeToDisplay(task.type)}",
      priority: task.priority,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? "Synced to Google Tasks!" : "Sync failed."),
          backgroundColor: success ? Colors.green : Colors.redAccent,
        ),
      );
    }
  }

  String itemTypeToDisplay(String type) {
    switch (type) {
      case 'event': return 'Event';
      case 'note': return 'Note';
      default: return 'Task';
    }
  }

  // --- APP INITIALIZATION ---
  Future<void> _loadInitialData() async {
    await _loadTasks();
    await _loadApiKey();
    await _loadCompletedCount(); // NEW
    
    // If no API Key, show the popup after a short delay
    if (_userApiKey == null || _userApiKey!.isEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () => _showApiKeyPopup());
    }
  }

  Future<void> _loadCompletedCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _completedCount = prefs.getInt('completed_count') ?? 0;
    });
  }

  Future<void> _incrementCompletedCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _completedCount++;
    });
    await prefs.setInt('completed_count', _completedCount);
    HapticFeedback.mediumImpact(); // Satisfaction!
  }

  Future<void> _decrementCompletedCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_completedCount > 0) _completedCount--;
    });
    await prefs.setInt('completed_count', _completedCount);
  }

  // --- STORAGE LOGIC ---
  Future<void> _loadTasks() async {
    // Load local first for speed
    final prefs = await SharedPreferences.getInstance();
    final String? tasksString = prefs.getString('saved_tasks');
    
    if (tasksString != null) {
      final List<dynamic> decoded = jsonDecode(tasksString);
      setState(() {
        _parsedTasks = decoded.map((item) => MindTask.fromJson(item)).toList();
      });
    }

    // Then sync from Firestore if available
    try {
      final snapshot = await _firestore.collection('tasks').orderBy('id', descending: true).get();
      final cloudTasks = snapshot.docs.map((doc) => MindTask.fromJson(doc.data())).toList();
      if (cloudTasks.isNotEmpty) {
        setState(() {
          _parsedTasks = cloudTasks;
        });
      }
    } catch (e) {
      debugPrint("Firestore load failed: $e");
    }
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userApiKey = prefs.getString('user_api_key');
    });
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_api_key', key);
    setState(() {
      _userApiKey = key;
    });
  }

  void _showApiKeyPopup() {
    final TextEditingController controller = TextEditingController(text: _userApiKey);
    showDialog(
      context: context,
      barrierDismissible: _userApiKey != null && _userApiKey!.isNotEmpty,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Colors.amber),
            SizedBox(width: 10),
            Text("Enter Gemini API Key"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Get your free key from Google AI Studio:",
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
            InkWell(
              onTap: () => launchUrl(Uri.parse("https://aistudio.google.com/app/apikey")),
              child: const Text(
                "https://aistudio.google.com/app/apikey",
                style: TextStyle(fontSize: 12, color: Colors.blueAccent, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Your key is saved locally on this device and never sent to our servers.",
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "AIzaSy...",
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _saveApiKey(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text("Save Key", style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_parsedTasks.map((t) => t.toJson()).toList());
    await prefs.setString('saved_tasks', encoded);

    // Sync to Firestore
    try {
      for (var task in _parsedTasks) {
        await _firestore.collection('tasks').doc(task.id).set(task.toJson());
      }
    } catch (e) {
      debugPrint("Firestore save failed: $e");
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  // --- CALENDAR LOGIC ---
  void _addToCalendar(MindTask task) {
    final DateTime start = task.startTime ?? DateTime.now().add(const Duration(minutes: 15));
    final DateTime end = start.add(const Duration(minutes: 60));

    final Event event = Event(
      title: task.title,
      description: 'Added via MindSort Voice',
      location: 'MindSort App',
      startDate: start,
      endDate: end,
      allDay: false,
    );

    Add2Calendar.addEvent2Cal(event);
  }

  // --- EDIT LOGIC (NEW) ---
  void _editTask(int index, String newTitle) {
    setState(() {
      // Create a new task with the updated title but same ID/Type
      final oldTask = _parsedTasks[index];
      _parsedTasks[index] = MindTask(
        id: oldTask.id,
        title: newTitle,
        type: oldTask.type,
        startTime: oldTask.startTime,
      );
    });
    _saveTasks();
  }

  void _showEditDialog(BuildContext context, int index) {
    final task = _parsedTasks[index];
    final TextEditingController controller = TextEditingController(text: task.title);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Edit Task"),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter new text",
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _editTask(index, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRecording() async {
    try {
      HapticFeedback.heavyImpact(); // Vibrate on tap
      if (_isListening) {
        final path = await _audioRecorder.stop();

        setState(() {
          _isListening = false;
          _isProcessing = true;
          _error = null;
        });
        
        if (path != null) {
          final result = await GeminiHelper.processAudio(path, _userApiKey!);
          _handleGeminiResult(result);
        }

      } else {
        if (!kIsWeb) {
          var status = await Permission.microphone.status;
          if (!status.isGranted) {
            status = await Permission.microphone.request();
            if (!status.isGranted) return;
          }
        }

        final tempDir = await PlatformUtils.getTempPath();
        final fileName = 'mindsort_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final filePath = PlatformUtils.joinPath(tempDir, fileName);

        await _audioRecorder.start(const RecordConfig(), path: filePath);
        
        setState(() {
          _isListening = true;
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _isListening = false;
        _isProcessing = false;
        _error = "Error: $e";
      });
    }
  }

  String _cleanJson(String raw) {
    return raw.replaceAll('```json', '').replaceAll('```', '').trim();
  }

  void _handleGeminiResult(String? result) {
    if (result == null) {
      setState(() {
        _isProcessing = false;
        _error = "Gemini was silent. Try again.";
      });
      return;
    }

    try {
      final cleanResult = _cleanJson(result);
      final Map<String, dynamic> data = jsonDecode(cleanResult);
      
      List<MindTask> newTasks = [];
      
      if (data['tasks'] != null) {
        for (var item in data['tasks']) {
          final String title = item is Map ? (item['title'] ?? '') : item.toString();
          final String priority = item is Map ? (item['priority'] ?? 'Medium') : 'Medium';
          newTasks.add(MindTask(
            id: DateTime.now().toString() + title,
            title: title,
            priority: priority,
            type: 'task'
          ));
        }
      }

      if (data['events'] != null) {
        for (var item in data['events']) {
          if (item is Map) {
             newTasks.add(MindTask(
              id: DateTime.now().toString() + (item['title'] ?? ''),
              title: item['title'] ?? '',
              priority: item['priority'] ?? 'Medium',
              type: 'event',
              startTime: item['time'] != null ? DateTime.parse(item['time']) : null,
            ));
          }
        }
      }

      if (data['notes'] != null) {
        for (var item in data['notes']) {
          final String title = item is Map ? (item['title'] ?? '') : item.toString();
          final String priority = item is Map ? (item['priority'] ?? 'Low') : 'Low';
          newTasks.add(MindTask(
            id: DateTime.now().toString() + title,
            title: title,
            priority: priority,
            type: 'note'
          ));
        }
      }

      setState(() {
        _parsedTasks = [...newTasks, ..._parsedTasks]; 
        _isProcessing = false;
      });
      
      _saveTasks(); 

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = "Parsing Error. Raw: $result";
      });
    }
  }

  void _deleteTask(int index) {
    setState(() {
      _parsedTasks.removeAt(index);
    });
    _saveTasks();
  }

  void _restoreTask(int index, MindTask task) {
    setState(() {
      _parsedTasks.insert(index, task);
    });
    _saveTasks();
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white70),
        onPressed: _isProcessing ? null : onPressed,
      ),
    );
  }

  // --- IMAGE LOGIC ---
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source);
      
      if (image != null) {
        setState(() {
          _isProcessing = true;
          _error = null;
        });
        
        final result = await GeminiHelper.processImage(image.path, _userApiKey!);
        _handleGeminiResult(result);
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = "Image Error: $e";
      });
    }
  }

  Future<void> _chunkTask(int index) async {
    final task = _parsedTasks[index];
    setState(() => _isProcessing = true);
    
    final result = await GeminiHelper.chunkTask(task.title, _userApiKey!);
    
    if (result != null) {
      try {
        final List<dynamic> chunks = jsonDecode(_cleanJson(result));
        setState(() {
          _parsedTasks[index] = MindTask(
            id: task.id,
            title: task.title,
            type: task.type,
            startTime: task.startTime,
            subTasks: List<String>.from(chunks),
          );
          _isProcessing = false;
        });
        _saveTasks();
      } catch (e) {
        setState(() => _isProcessing = false);
      }
    } else {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _showRecapDialog() async {
    setState(() => _isProcessing = true);
    
    final tasksJson = jsonEncode(_parsedTasks.map((t) => t.toJson()).toList());
    final recap = await GeminiHelper.generateRecap(tasksJson, _userApiKey!);
    
    setState(() => _isProcessing = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text("Weekly Recap"),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            recap ?? "Failed to generate recap.",
            style: const TextStyle(color: Colors.white70, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "MindSort",
          style: GoogleFonts.syne(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            letterSpacing: -1,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: PopupMenuButton<MindTheme>(
          icon: const Icon(Icons.palette_outlined),
          onSelected: (theme) => themeManager.setTheme(theme),
          itemBuilder: (context) => [
            const PopupMenuItem(value: MindTheme.zinc, child: Text("Zinc (Default)")),
            const PopupMenuItem(value: MindTheme.cyberpunk, child: Text("Cyberpunk")),
            const PopupMenuItem(value: MindTheme.paper, child: Text("Paper")),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'pdf') _exportToPDF();
              if (value == 'csv') _exportToCSV();
              if (value == 'wrapped') {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => WrappedScreen(tasks: _parsedTasks, completedCount: _completedCount)
                ));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'wrapped', child: Text("View Wrapped")),
              const PopupMenuItem(value: 'pdf', child: Text("Export PDF")),
              const PopupMenuItem(value: 'csv', child: Text("Export CSV")),
            ],
          ),
          IconButton(
            icon: Icon(
              Icons.account_circle_rounded,
              color: _isGoogleConnected ? Colors.blueAccent : Colors.white24,
            ),
            onPressed: _handleGoogleSignIn,
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_rounded, color: Colors.white24),
            onPressed: () => _showApiKeyPopup(),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          
          // STATS COUNTER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _buildStatChip("Done", _completedCount.toString(), const Color(0xFF2DD4BF)),
                const SizedBox(width: 12),
                _buildStatChip("Pending", _parsedTasks.length.toString(), const Color(0xFF6366F1)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // SEARCH BAR (shadcn style)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search thoughts...",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14),
                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.white.withOpacity(0.2)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // RECORDING ACTION AREA
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModernIconButton(Icons.image_outlined, () => _pickImage(ImageSource.gallery)),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: _isProcessing ? null : _toggleRecording,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isListening)
                      _buildPulseEffect(),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      height: _isListening ? 120 : 100,
                      width: _isListening ? 120 : 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isProcessing 
                              ? [const Color(0xFFFACC15), const Color(0xFFEAB308)] // Yellow-400 to 600
                              : (_isListening 
                                  ? [const Color(0xFFF43F5E), const Color(0xFFE11D48)] // Rose-500 to 600
                                  : [const Color(0xFF6366F1), const Color(0xFF4F46E5)]), // Indigo-500 to 600
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening || _isProcessing)
                                ? (_isProcessing ? Colors.amber : Colors.pinkAccent).withOpacity(0.4)
                                : const Color(0xFF6366F1).withOpacity(0.3),
                            blurRadius: 40,
                            spreadRadius: _isListening ? 10 : 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isProcessing ? Icons.sync : (_isListening ? Icons.stop : Icons.mic_none),
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              _buildModernIconButton(Icons.camera_outlined, () => _pickImage(ImageSource.camera)),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            _isProcessing ? "Analyzing..." : (_isListening ? "Listening..." : "Voice or Visual Dump"),
            style: TextStyle(
              color: _isProcessing ? const Color(0xFFFACC15) : Colors.white.withOpacity(0.5),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          
          if (_error != null)
            _buildErrorContainer(),

          const SizedBox(height: 32),

          // FILTER TABS (Pill style)
          if (_parsedTasks.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: ['All', 'Task', 'Event', 'Note'].map((filter) {
                  final isSelected = _currentFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _currentFilter = filter),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? Colors.black : Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          const Divider(color: Colors.white10, height: 1),

          Expanded(
            child: _parsedTasks.isEmpty && !_isProcessing
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                  itemCount: _parsedTasks.length,
                  itemBuilder: (context, index) {
                    final item = _parsedTasks[index];
                    final bool matchesCategory = _currentFilter == 'All' || item.type.toLowerCase() == _currentFilter.toLowerCase();
                    final bool matchesSearch = item.title.toLowerCase().contains(_searchQuery);

                    if (matchesCategory && matchesSearch) {
                      return _buildTaskCard(item, index);
                    }
                    return const SizedBox.shrink();
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.6),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernIconButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.6), size: 20),
      ),
    );
  }

  Widget _buildPulseEffect() {
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 1),
      builder: (context, double value, child) {
        return Container(
          width: 100 + (60 * value),
          height: 100 + (60 * value),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFF43F5E).withOpacity(1 - value), width: 2),
          ),
        );
      },
    );
  }

  Widget _buildErrorContainer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(
            "Your organized thoughts will appear here",
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _toggleSubTask(int taskIndex, int subIndex) {
    setState(() {
      final task = _parsedTasks[taskIndex];
      final List<String> updatedSubTasks = List.from(task.subTasks);
      final String subTask = updatedSubTasks[subIndex];
      
      if (subTask.startsWith('✓ ')) {
        updatedSubTasks[subIndex] = subTask.replaceFirst('✓ ', '');
      } else {
        updatedSubTasks[subIndex] = '✓ $subTask';
      }
      
      _parsedTasks[taskIndex] = MindTask(
        id: task.id,
        title: task.title,
        type: task.type,
        startTime: task.startTime,
        subTasks: updatedSubTasks,
      );
    });
    _saveTasks();
  }

  Widget _buildTaskCard(MindTask item, int index) {
    IconData icon;
    Color accentColor;

    switch (item.type) {
      case 'event':
        icon = Icons.calendar_today_outlined;
        accentColor = const Color(0xFFFB923C); // Orange-400
        break;
      case 'note':
        icon = Icons.sticky_note_2_outlined;
        accentColor = const Color(0xFF2DD4BF); // Teal-400
        break;
      default:
        icon = Icons.check_circle_outline;
        accentColor = const Color(0xFF818CF8); // Indigo-400
    }

    return Dismissible(
      key: Key(item.id),
      background: _buildDismissBackground(Alignment.centerLeft, Colors.green),
      secondaryBackground: _buildDismissBackground(Alignment.centerRight, Colors.redAccent),
      onDismissed: (direction) => _handleDismiss(item, index, accentColor),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF09090B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onLongPress: () => _showEditDialog(context, index),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              title: Text(
                item.title, 
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Colors.white,
                  letterSpacing: -0.2,
                )
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    _buildPriorityDot(item.priority),
                    const SizedBox(width: 8),
                    Text(
                      item.type.toUpperCase(), 
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.4),
                        letterSpacing: 0.5,
                      )
                    ),
                    if (item.startTime != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.calendar_month_outlined, size: 12, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(width: 4),
                      Text(
                        "${item.startTime!.day}/${item.startTime!.month} ${item.startTime!.hour}:${item.startTime!.minute.toString().padLeft(2, '0')}",
                        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3)),
                      ),
                    ],
                  ],
                ),
              ),
              trailing: _buildCardActions(item, index),
            ),
            if (item.subTasks.isNotEmpty)
              _buildSubTaskList(item, index),
          ],
        ),
      ),
    );
  }

  Widget _buildDismissBackground(Alignment alignment, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: alignment,
      padding: EdgeInsets.only(
        left: alignment == Alignment.centerLeft ? 20 : 0,
        right: alignment == Alignment.centerRight ? 20 : 0,
      ),
      child: Icon(
        alignment == Alignment.centerLeft ? Icons.check : Icons.delete_outline,
        color: color,
      ),
    );
  }

  void _handleDismiss(MindTask item, int index, Color accentColor) {
    final deletedItem = item;
    final deletedIndex = index;
    _deleteTask(index);
    _incrementCompletedCount(); // Satisfaction!

    ScaffoldMessenger.of(context).clearSnackBars(); // Ensure old ones are gone
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2), // Fix: Dismiss after 2s
        backgroundColor: const Color(0xFF18181B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Text('${deletedItem.title} handled', style: const TextStyle(color: Colors.white, fontSize: 13)),
        action: SnackBarAction(
          label: 'UNDO', 
          textColor: accentColor,
          onPressed: () {
            _restoreTask(deletedIndex, deletedItem);
            _decrementCompletedCount();
          }
        ),
      )
    );
  }

  Widget _buildPriorityDot(String priority) {
    Color color;
    switch (priority) {
      case 'High': color = const Color(0xFFF43F5E); break; // Rose-500
      case 'Low': color = const Color(0xFF38BDF8); break; // Sky-400
      default: color = const Color(0xFFFACC15); // Yellow-400
    }
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildCardActions(MindTask item, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isGoogleConnected && item.type != 'event')
          IconButton(
            icon: Icon(Icons.sync, color: Colors.white.withOpacity(0.2), size: 18),
            onPressed: () => _syncToGoogle(item),
          ),
        if (item.subTasks.isEmpty && item.type != 'event')
          IconButton(
            icon: Icon(Icons.auto_awesome_mosaic_outlined, color: Colors.white.withOpacity(0.2), size: 18),
            onPressed: () => _chunkTask(index),
          ),
        if (item.type == 'event')
          IconButton(
            icon: Icon(Icons.event_available_outlined, color: Colors.white.withOpacity(0.2), size: 18),
            onPressed: () => _addToCalendar(item),
          ),
      ],
    );
  }

  Widget _buildSubTaskList(MindTask item, int taskIndex) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
      child: Column(
        children: item.subTasks.asMap().entries.map((entry) {
          final bool isDone = entry.value.startsWith('✓ ');
          return InkWell(
            onTap: () => _toggleSubTask(taskIndex, entry.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isDone ? Icons.check_circle : Icons.circle_outlined,
                    size: 14,
                    color: isDone ? const Color(0xFF2DD4BF) : Colors.white.withOpacity(0.2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isDone ? entry.value.replaceFirst('✓ ', '') : entry.value,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDone ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.7),
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}