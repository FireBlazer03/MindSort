import 'dart:convert';
import 'dart:io';
import 'dart:ui';
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
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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

// --- THEME SYSTEM ---
enum MindTheme { zinc, cyberpunk, midnight }

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
            seedColor: const Color(0xFF00F0FF),
            brightness: Brightness.dark,
            surface: const Color(0xFF050511),
            background: const Color(0xFF050511),
            primary: const Color(0xFFFF003C), // Cyberpunk pink
            secondary: const Color(0xFFFCEE09), // Cyber yellow
          ),
          textTheme: GoogleFonts.orbitronTextTheme(ThemeData.dark().textTheme),
          cardTheme: CardThemeData(
            color: const Color(0xFF101026),
            elevation: 10,
            shadowColor: const Color(0xFF00F0FF).withOpacity(0.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: const Color(0xFF00F0FF).withOpacity(0.5), width: 1),
            ),
          ),
          scaffoldBackgroundColor: const Color(0xFF050511),
        );
      case MindTheme.midnight:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00FF9C),
            brightness: Brightness.dark,
            surface: const Color(0xFF02040A), // Deepest midnight black
            background: const Color(0xFF02040A),
            primary: const Color(0xFF00FF9C), // Spring Green accent
            secondary: const Color(0xFF7000FF), // Deep purple contrast
          ),
          textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.dark().textTheme),
          cardTheme: CardThemeData(
            color: const Color(0xFF0A0E17), // Slightly lifted dark blue-grey
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: const Color(0xFF1E293B).withOpacity(0.8), width: 1),
            ),
          ),
          scaffoldBackgroundColor: const Color(0xFF02040A),
        );
      default: // Zinc
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6366F1),
            brightness: Brightness.dark,
            surface: const Color(0xFF09090B),
            background: const Color(0xFF09090B),
            primary: const Color(0xFF6366F1),
          ),
          textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
          cardTheme: CardThemeData(
            color: const Color(0xFF18181B), // Zinc 900
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
            ),
          ),
          scaffoldBackgroundColor: const Color(0xFF09090B),
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

// --- INTERACTIVE RECAP SCREEN (STORY STYLE) ---
class WrappedScreen extends StatefulWidget {
  final List<MindTask> tasks;
  final int completedCount;

  const WrappedScreen({super.key, required this.tasks, required this.completedCount});

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _startStoryTimer();
  }

  void _startStoryTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return false;
      setState(() {
        _progress += 0.01;
      });
      if (_progress >= 1.0) {
        if (_currentPage < 3) {
          _progress = 0.0;
          _currentPage++;
          _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
        } else {
          return false;
        }
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() { _currentPage = i; _progress = 0.0; }),
            children: [
              _buildIntroPage(),
              _buildStatsPage(),
              _buildCompositionPage(),
              _buildFinalPage(),
            ],
          ),
          // Progress Bars
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: List.generate(4, (index) => Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: index < _currentPage ? 1.0 : (index == _currentPage ? _progress : 0.0),
                      child: Container(color: Colors.white),
                    ),
                  ),
                )),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroPage() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInDown(child: const Icon(Icons.auto_awesome, size: 80, color: Colors.white)),
            const SizedBox(height: 30),
            FadeInUp(
              child: Text(
                "YOUR MINDSORT\nWRAPPED",
                textAlign: TextAlign.center,
                style: GoogleFonts.syne(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, height: 1),
              ),
            ),
            const SizedBox(height: 20),
            FadeIn(
              delay: const Duration(milliseconds: 500),
              child: const Text("Take a moment to see how far you've come.", style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsPage() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeInLeft(
            child: _buildBigStatCard("Thoughts Captured", (widget.tasks.length + widget.completedCount).toString(), Icons.psychology_outlined),
          ),
          const SizedBox(height: 20),
          FadeInRight(
            delay: const Duration(milliseconds: 300),
            child: _buildBigStatCard("Tasks Completed", widget.completedCount.toString(), Icons.verified_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildCompositionPage() {
    final taskCount = widget.tasks.where((t) => t.type == 'task').length;
    final eventCount = widget.tasks.where((t) => t.type == 'event').length;
    final noteCount = widget.tasks.where((t) => t.type == 'note').length;

    return Container(
      color: const Color(0xFF09090B),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("YOUR MIND COMPOSITION", style: GoogleFonts.syne(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 40),
          SizedBox(
            height: 250,
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(value: taskCount.toDouble(), title: 'Tasks', color: const Color(0xFF6366F1), radius: 60, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                  PieChartSectionData(value: eventCount.toDouble(), title: 'Events', color: const Color(0xFFF97316), radius: 60, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                  PieChartSectionData(value: noteCount.toDouble(), title: 'Notes', color: const Color(0xFF2DD4BF), radius: 60, titleStyle: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          FadeInUp(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSmallLegend("Tasks", const Color(0xFF6366F1)),
                _buildSmallLegend("Events", const Color(0xFFF97316)),
                _buildSmallLegend("Notes", const Color(0xFF2DD4BF)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFinalPage() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF000000), Color(0xFF1E293B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ZoomIn(child: const Icon(Icons.celebration, size: 80, color: Colors.amberAccent)),
            const SizedBox(height: 30),
            Text("Keep Growing.", style: GoogleFonts.syne(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Back to My Mind", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBigStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 40, color: Colors.indigoAccent),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
              Text(label, style: const TextStyle(fontSize: 14, color: Colors.white54)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallLegend(String label, Color color) {
    return Column(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      ],
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
    String csv = "Title,Type,Priority,Start Time\n";
    for (var task in _parsedTasks) {
      csv += "${task.title},${task.type},${task.priority},${task.startTime?.toString() ?? ""}\n";
    }
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
    final task = _parsedTasks[index];
    setState(() {
      _parsedTasks.removeAt(index);
    });
    _saveTasks();
    try {
      _firestore.collection('tasks').doc(task.id).delete();
    } catch (e) {
      debugPrint("Firestore delete failed: $e");
    }
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
      backgroundColor: themeManager.themeData.scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      extendBody: true,
      bottomNavigationBar: _buildMorphingBottomBar(context),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverAppBar(
              expandedHeight: 110,
              collapsedHeight: 80,
              floating: false,
              pinned: true,
              backgroundColor: themeManager.themeData.scaffoldBackgroundColor.withOpacity(0.9),
              flexibleSpace: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                    title: Text(
                      "MindSort",
                      style: GoogleFonts.syne(
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        letterSpacing: -1.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.account_circle_rounded,
                    color: _isGoogleConnected ? Colors.blueAccent : Colors.white24,
                  ),
                  onPressed: _handleGoogleSignIn,
                ),
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
                    if (value == 'zinc') themeManager.setTheme(MindTheme.zinc);
                    if (value == 'cyberpunk') themeManager.setTheme(MindTheme.cyberpunk);
                    if (value == 'midnight') themeManager.setTheme(MindTheme.midnight);
                    if (value == 'api') _showApiKeyPopup();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'wrapped', child: Text("View Wrapped")),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'zinc', child: Text("Theme: Zinc")),
                    const PopupMenuItem(value: 'cyberpunk', child: Text("Theme: Cyberpunk")),
                    const PopupMenuItem(value: 'midnight', child: Text("Theme: Midnight")),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'pdf', child: Text("Export PDF")),
                    const PopupMenuItem(value: 'csv', child: Text("Export CSV")),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'api', child: Text("Change API Key")),
                  ],
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    
                    // BENTO STATS GRID
                    Row(
                      children: [
                        _buildBentoStat("Mind Done", _completedCount.toString(), const Color(0xFF2DD4BF), Icons.verified_rounded),
                        const SizedBox(width: 12),
                        _buildBentoStat("In Mind", _parsedTasks.length.toString(), themeManager.themeData.colorScheme.primary, Icons.bubble_chart_rounded),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // PREMIUM SEARCH BAR
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: themeManager.themeData.cardTheme.color,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                        style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: "Search your mind...",
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 15, fontWeight: FontWeight.w400),
                          prefixIcon: Icon(Icons.search_rounded, size: 20, color: Colors.white.withOpacity(0.2)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                      ),
                    ),

                    if (_error != null) _buildErrorContainer(),

                    const SizedBox(height: 32),

                    // FILTER TABS
                    if (_parsedTasks.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text("FILTERS", style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.2), letterSpacing: 1)),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: ['All', 'Task', 'Event', 'Note'].map((filter) {
                            final isSelected = _currentFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _currentFilter = filter);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.white : Colors.white.withOpacity(0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? Colors.white : Colors.white.withOpacity(0.05),
                                    ),
                                  ),
                                  child: Text(
                                    filter,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected ? Colors.black : Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),

            if (_isProcessing)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: _buildProcessingIndicator(),
                ),
              ),

            if (_parsedTasks.isEmpty && !_isProcessing)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else if (_parsedTasks.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _parsedTasks[index];
                      final bool matchesCategory = _currentFilter == 'All' || item.type.toLowerCase() == _currentFilter.toLowerCase();
                      final bool matchesSearch = item.title.toLowerCase().contains(_searchQuery);

                      if (matchesCategory && matchesSearch) {
                        return FadeInUp(
                          duration: const Duration(milliseconds: 400),
                          delay: Duration(milliseconds: index * 50),
                          child: _buildTaskCard(item, index),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    childCount: _parsedTasks.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMorphingBottomBar(BuildContext context) {
    final bottomPadding = 30.0; // Let resizeToAvoidBottomInset handle the keyboard lifting
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeManager.themeData.scaffoldBackgroundColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: -5,
                      )
                    ]
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildIslandButton(Icons.image_rounded, () => _pickImage(ImageSource.gallery)),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: _isProcessing ? null : _toggleRecording,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isListening) _buildPulseEffect(),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutBack,
                              height: _isListening ? 64 : 56,
                              width: _isListening ? 64 : 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _isProcessing 
                                      ? [const Color(0xFFFACC15), const Color(0xFFEAB308)]
                                      : (_isListening 
                                          ? [const Color(0xFFF43F5E), const Color(0xFFE11D48)]
                                          : [themeManager.themeData.colorScheme.primary, themeManager.themeData.colorScheme.primary.withBlue(255)]),
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isListening || _isProcessing)
                                        ? (_isProcessing ? Colors.amber : Colors.pinkAccent).withOpacity(0.5)
                                        : themeManager.themeData.colorScheme.primary.withOpacity(0.4),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isProcessing ? Icons.sync_rounded : (_isListening ? Icons.stop_rounded : Icons.mic_rounded),
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildIslandButton(Icons.camera_alt_rounded, () => _pickImage(ImageSource.camera)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: themeManager.themeData.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeManager.themeData.colorScheme.primary.withOpacity(0.1)),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(themeManager.themeData.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Shimmer.fromColors(
              baseColor: themeManager.themeData.colorScheme.primary.withOpacity(0.5),
              highlightColor: Colors.white,
              child: Text(
                "Processing thought...",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoStat(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.15), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 20),
                Text(
                  value,
                  style: GoogleFonts.syne(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color.withOpacity(0.6),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIslandButton(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact();
        onPressed();
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 22),
      ),
    );
  }

  Widget _buildPulseEffect() {
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 1),
      builder: (context, double value, child) {
        return Container(
          width: 56 + (40 * value),
          height: 56 + (40 * value),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFF43F5E).withOpacity(1 - value), width: 2),
          ),
        );
      },
    );
  }

  Widget _buildErrorContainer() {
    return FadeIn(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(top: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: FadeIn(
        duration: const Duration(seconds: 1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 64, color: Colors.white.withOpacity(0.05)),
            ),
            const SizedBox(height: 24),
            Text(
              "YOUR MIND IS CLEAR",
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white.withOpacity(0.2),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Dump your thoughts to get started",
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white.withOpacity(0.1),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
        HapticFeedback.lightImpact();
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
        icon = Icons.calendar_today_rounded;
        accentColor = const Color(0xFFFB923C);
        break;
      case 'note':
        icon = Icons.sticky_note_2_rounded;
        accentColor = const Color(0xFF2DD4BF);
        break;
      default:
        icon = Icons.task_alt_rounded;
        accentColor = themeManager.themeData.colorScheme.primary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: themeManager.themeData.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Slidable(
        key: Key(item.id),
        endActionPane: ActionPane(
          motion: const StretchMotion(),
          children: [
            SlidableAction(
              onPressed: (context) => _handleDismiss(item, index, accentColor),
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.redAccent,
              icon: Icons.delete_rounded,
              label: 'Handle',
              borderRadius: BorderRadius.circular(20),
            ),
          ],
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              onLongPress: () {
                HapticFeedback.mediumImpact();
                _showEditDialog(context, index);
              },
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              title: Text(
                item.title, 
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.white,
                  letterSpacing: -0.3,
                  height: 1.3,
                )
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPriorityDot(item.priority),
                        const SizedBox(width: 6),
                        Text(
                          item.priority.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.3)),
                        ),
                      ],
                    ),
                    if (item.startTime != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_filled_rounded, size: 14, color: Colors.white.withOpacity(0.2)),
                          const SizedBox(width: 4),
                          Text(
                            "${item.startTime!.day}/${item.startTime!.month} ${item.startTime!.hour}:${item.startTime!.minute.toString().padLeft(2, '0')}",
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.3)),
                          ),
                        ],
                      ),
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
    ).animate().scaleXY(begin: 0.95, end: 1.0, curve: Curves.easeOutBack, duration: 400.ms).fadeIn(duration: 400.ms);
  }

  void _handleDismiss(MindTask item, int index, Color accentColor) {
    HapticFeedback.heavyImpact();
    final deletedItem = item;
    final deletedIndex = index;
    _deleteTask(index);
    _incrementCompletedCount();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF18181B),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text('${deletedItem.title} handled', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        action: SnackBarAction(
          label: 'UNDO', 
          textColor: accentColor,
          onPressed: () {
            HapticFeedback.mediumImpact();
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
      case 'High': color = const Color(0xFFF43F5E); break;
      case 'Low': color = const Color(0xFF38BDF8); break;
      default: color = const Color(0xFFFACC15);
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle, 
        color: color,
        boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1)],
      ),
    );
  }

  Widget _buildCardActions(MindTask item, int index) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionIconButton(Icons.edit_note_rounded, () {
          HapticFeedback.selectionClick();
          _showEditDialog(context, index);
        }),
        if (_isGoogleConnected && item.type != 'event')
          _buildActionIconButton(Icons.sync_rounded, () {
            HapticFeedback.selectionClick();
            _syncToGoogle(item);
          }),
        if (item.subTasks.isEmpty && item.type != 'event')
          _buildActionIconButton(Icons.auto_awesome_mosaic_rounded, () {
            HapticFeedback.selectionClick();
            _chunkTask(index);
          }),
        if (item.type == 'event')
          _buildActionIconButton(Icons.event_available_rounded, () {
            HapticFeedback.selectionClick();
            _addToCalendar(item);
          }),
      ],
    );
  }

  Widget _buildActionIconButton(IconData icon, VoidCallback onPressed) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(icon, color: Colors.white.withOpacity(0.2), size: 22),
      onPressed: onPressed,
      splashRadius: 20,
    );
  }

  Widget _buildSubTaskList(MindTask item, int taskIndex) {
    return Container(
      padding: const EdgeInsets.fromLTRB(68, 0, 20, 20),
      child: Column(
        children: item.subTasks.asMap().entries.map((entry) {
          final bool isDone = entry.value.startsWith('✓ ');
          return InkWell(
            onTap: () => _toggleSubTask(taskIndex, entry.key),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isDone ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 16,
                    color: isDone ? const Color(0xFF2DD4BF) : Colors.white.withOpacity(0.1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isDone ? entry.value.replaceFirst('✓ ', '') : entry.value,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDone ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.6),
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