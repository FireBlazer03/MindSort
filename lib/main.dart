import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:add_2_calendar/add_2_calendar.dart'; 
import 'gemini_helper.dart';

// --- DATA MODEL ---
class MindTask {
  final String id;
  final String title;
  final String type;
  final DateTime? startTime;

  MindTask({
    required this.id, 
    required this.title, 
    required this.type,
    this.startTime,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'startTime': startTime?.toIso8601String(),
  };

  factory MindTask.fromJson(Map<String, dynamic> json) {
    return MindTask(
      id: json['id'] ?? DateTime.now().toString(),
      title: json['title'],
      type: json['type'],
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
    );
  }
}

void main() {
  runApp(const MindSortApp());
}

class MindSortApp extends StatelessWidget {
  const MindSortApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MindSort',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6200EE),
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: const RecordingScreen(),
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
  
  bool _isListening = false;
  bool _isProcessing = false;
  List<MindTask> _parsedTasks = []; 
  String? _error;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _loadTasks();
  }

  // --- STORAGE LOGIC ---
  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksString = prefs.getString('saved_tasks');
    
    if (tasksString != null) {
      final List<dynamic> decoded = jsonDecode(tasksString);
      setState(() {
        _parsedTasks = decoded.map((item) => MindTask.fromJson(item)).toList();
      });
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_parsedTasks.map((t) => t.toJson()).toList());
    await prefs.setString('saved_tasks', encoded);
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
      if (_isListening) {
        final path = await _audioRecorder.stop();

        setState(() {
          _isListening = false;
          _isProcessing = true;
          _error = null;
        });
        
        if (path != null) {
          final result = await GeminiHelper.processAudio(path);
          _handleGeminiResult(result);
        }

      } else {
        var status = await Permission.microphone.status;
        if (!status.isGranted) {
           status = await Permission.microphone.request();
           if (!status.isGranted) return;
        }

        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'mindsort_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final filePath = '${directory.path}/$fileName';

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
          newTasks.add(MindTask(
            id: DateTime.now().toString() + item.toString(),
            title: item.toString(),
            type: 'task'
          ));
        }
      }

      if (data['events'] != null) {
        for (var item in data['events']) {
          if (item is Map) {
             newTasks.add(MindTask(
              id: DateTime.now().toString() + item['title'],
              title: item['title'],
              type: 'event',
              startTime: item['time'] != null ? DateTime.parse(item['time']) : null,
            ));
          } else {
             newTasks.add(MindTask(
              id: DateTime.now().toString() + item.toString(),
              title: item.toString(),
              type: 'event'
            ));
          }
        }
      }

      if (data['notes'] != null) {
        for (var item in data['notes']) {
          newTasks.add(MindTask(
            id: DateTime.now().toString() + item.toString(),
            title: item.toString(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MindSort"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_parsedTasks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: () {
                setState(() => _parsedTasks = []);
                _saveTasks();
              },
            )
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          Center(
            child: GestureDetector(
              onTap: _isProcessing ? null : _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _isListening ? 160 : 120,
                width: _isListening ? 160 : 120,
                decoration: BoxDecoration(
                  color: _isProcessing 
                      ? Colors.amber 
                      : (_isListening ? Colors.redAccent : Colors.blueGrey[800]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening || _isProcessing)
                          ? (_isProcessing ? Colors.amber : Colors.redAccent).withOpacity(0.4)
                          : Colors.black45,
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  _isProcessing ? Icons.sync : (_isListening ? Icons.stop : Icons.mic),
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          Text(
            _isProcessing ? "Sorting Brain..." : (_isListening ? "Listening..." : "Tap to Dump"),
            style: TextStyle(
              color: _isProcessing ? Colors.amber : Colors.white60,
              fontSize: 16,
              letterSpacing: 1.2
            ),
          ),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(12),
              color: Colors.redAccent.withOpacity(0.1),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10, thickness: 1),
          
          Expanded(
            child: _parsedTasks.isEmpty && !_isProcessing
              ? const Center(
                  child: Text(
                    "Your organized thoughts will appear here", 
                    style: TextStyle(color: Colors.white24)
                  )
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 50),
                  itemCount: _parsedTasks.length,
                  itemBuilder: (context, index) {
                    final item = _parsedTasks[index];
                    return _buildTaskCard(item, index); // Passing Index for editing
                  },
                ),
          ),
        ],
      ),
    );
  }

  // UPDATED: Now accepts 'index' to know which task to edit
  Widget _buildTaskCard(MindTask item, int index) {
    IconData icon;
    Color iconColor;

    switch (item.type) {
      case 'event':
        icon = Icons.calendar_today;
        iconColor = Colors.orangeAccent;
        break;
      case 'note':
        icon = Icons.lightbulb_outline;
        iconColor = Colors.tealAccent;
        break;
      default:
        icon = Icons.check_circle_outline;
        iconColor = Colors.blueAccent;
    }

    return Dismissible(
      key: Key(item.id),
      background: Container(color: Colors.green),
      secondaryBackground: Container(color: Colors.red),
      onDismissed: (direction) {
         final deletedItem = item;
         final deletedIndex = index;
         _deleteTask(index);
         ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${deletedItem.title} completed'),
              action: SnackBarAction(label: 'UNDO', onPressed: () => _restoreTask(deletedIndex, deletedItem)),
            )
         );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: Colors.white10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          // NEW: Long Press to Edit!
          onLongPress: () => _showEditDialog(context, index),
          leading: Icon(icon, color: iconColor),
          title: Text(
            item.title, 
            style: const TextStyle(fontWeight: FontWeight.w500)
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.type.toUpperCase(), style: TextStyle(fontSize: 10, color: iconColor.withOpacity(0.7))),
              if (item.startTime != null)
                Text(
                  "📅 ${item.startTime!.hour}:${item.startTime!.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
            ],
          ),
          trailing: item.type == 'event' 
              ? IconButton(
                  icon: const Icon(Icons.edit_calendar, color: Colors.amber),
                  onPressed: () => _addToCalendar(item),
                )
              : const Icon(Icons.drag_handle, size: 18, color: Colors.white24),
        ),
      ),
    );
  }
}