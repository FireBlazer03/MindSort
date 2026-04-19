import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:add_2_calendar/add_2_calendar.dart'; 
import 'package:image_picker/image_picker.dart';
import 'gemini_helper.dart';

// --- DATA MODEL ---
class MindTask {
  final String id;
  final String title;
  final String type;
  final DateTime? startTime;
  final List<String> subTasks;

  MindTask({
    required this.id, 
    required this.title, 
    required this.type,
    this.startTime,
    this.subTasks = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'startTime': startTime?.toIso8601String(),
    'subTasks': subTasks,
  };

  factory MindTask.fromJson(Map<String, dynamic> json) {
    return MindTask(
      id: json['id'] ?? DateTime.now().toString(),
      title: json['title'],
      type: json['type'],
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
      subTasks: List<String>.from(json['subTasks'] ?? []),
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
        
        final result = await GeminiHelper.processImage(image.path);
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
    
    final result = await GeminiHelper.chunkTask(task.title);
    
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
              icon: const Icon(Icons.delete_forever_rounded, color: Colors.white24),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: const Text("Clear All?"),
                    content: const Text("This will permanently delete all your sorted thoughts."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                      TextButton(
                        onPressed: () {
                          setState(() => _parsedTasks = []);
                          _saveTasks();
                          Navigator.pop(context);
                        }, 
                        child: const Text("Clear", style: TextStyle(color: Colors.redAccent))
                      ),
                    ],
                  ),
                );
              },
            )
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIconButton(Icons.photo_library_rounded, () => _pickImage(ImageSource.gallery)),
              const SizedBox(width: 20),
              Center(
                child: GestureDetector(
                  onTap: _isProcessing ? null : _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: _isListening ? 160 : 130,
                    width: _isListening ? 160 : 130,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isProcessing 
                            ? [Colors.amber, Colors.orange]
                            : (_isListening 
                                ? [Colors.redAccent, Colors.pinkAccent] 
                                : [const Color(0xFF6200EE), const Color(0xFF3700B3)]),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening || _isProcessing)
                              ? (_isProcessing ? Colors.amber : Colors.redAccent).withOpacity(0.5)
                              : Colors.black45,
                          blurRadius: 30,
                          spreadRadius: _isListening ? 10 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isProcessing ? Icons.sync_rounded : (_isListening ? Icons.stop_rounded : Icons.mic_rounded),
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              _buildIconButton(Icons.camera_alt_rounded, () => _pickImage(ImageSource.camera)),
            ],
          ),
          
          const SizedBox(height: 24),
          Text(
            _isProcessing ? "Sorting Brain..." : (_isListening ? "Listening..." : "Voice or Visual Dump"),
            style: TextStyle(
              color: _isProcessing ? Colors.amber : Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w300,
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
        icon = Icons.calendar_today_rounded;
        accentColor = Colors.orangeAccent;
        break;
      case 'note':
        icon = Icons.lightbulb_rounded;
        accentColor = Colors.tealAccent;
        break;
      default:
        icon = Icons.check_circle_rounded;
        accentColor = Colors.blueAccent;
    }

    return Dismissible(
      key: Key(item.id),
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.check, color: Colors.green),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      onDismissed: (direction) {
        final deletedItem = item;
        final deletedIndex = index;
        _deleteTask(index);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.grey[900],
            content: Text('${deletedItem.title} completed', style: const TextStyle(color: Colors.white)),
            action: SnackBarAction(
              label: 'UNDO', 
              textColor: accentColor,
              onPressed: () => _restoreTask(deletedIndex, deletedItem)
            ),
          )
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              onLongPress: () => _showEditDialog(context, index),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              title: Text(
                item.title, 
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  letterSpacing: 0.3,
                )
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, py: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.type.toUpperCase(), 
                        style: TextStyle(
                          fontSize: 10, 
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                          letterSpacing: 0.5,
                        )
                      ),
                    ),
                    if (item.startTime != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time, size: 14, color: Colors.white38),
                      const SizedBox(width: 4),
                      Text(
                        "${item.startTime!.hour}:${item.startTime!.minute.toString().padLeft(2, '0')}",
                        style: const TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.subTasks.isEmpty && item.type != 'event')
                    IconButton(
                      icon: const Icon(Icons.auto_fix_high_rounded, color: Colors.white24, size: 20),
                      onPressed: () => _chunkTask(index),
                    ),
                  if (item.type == 'event')
                    IconButton(
                      icon: const Icon(Icons.calendar_add_on_rounded, color: Colors.amber, size: 20),
                      onPressed: () => _addToCalendar(item),
                    ),
                ],
              ),
            ),
            if (item.subTasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(60, 0, 20, 16),
                child: Column(
                  children: item.subTasks.asMap().entries.map((entry) {
                    final bool isDone = entry.value.startsWith('✓ ');
                    return InkWell(
                      onTap: () => _toggleSubTask(index, entry.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              isDone ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              size: 18,
                              color: isDone ? Colors.greenAccent : Colors.white24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isDone ? entry.value.replaceFirst('✓ ', '') : entry.value,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDone ? Colors.white38 : Colors.white70,
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
              ),
          ],
        ),
      ),
    );
  }
}