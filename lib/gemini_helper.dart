import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiHelper {
  static const String _modelName = 'gemini-flash-lite-latest';

  static Future<String?> processAudio(String filePath, String apiKey) async {
    final model = GenerativeModel(
      model: _modelName,
      apiKey: apiKey,
    );

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final now = DateTime.now();

    final prompt = TextPart(
      "Current time: $now. Extract tasks, events, and notes from this audio. "
      "Output ONLY JSON: "
      "{ 'tasks': [{'title', 'priority'}], 'events': [{'title', 'time', 'priority'}], 'notes': [{'title', 'priority'}] }. "
      "Priority: High/Medium/Low. Time: ISO 8601."
    );

    final content = [
      Content.multi([
        prompt,
        DataPart('audio/mp4', bytes),
      ])
    ];

    int attempts = 0;
    while (attempts < 2) {
      try {
        final response = await model.generateContent(content);
        return response.text;
      } catch (e) {
        attempts++;
        if (e.toString().contains('429')) {
          await Future.delayed(Duration(seconds: 1));
        } else if (attempts >= 2) {
          return "Error: $e";
        }
      }
    }
    return "Error: Request failed.";
  }

  static Future<String?> processImage(String filePath, String apiKey) async {
    final model = GenerativeModel(
      model: _modelName,
      apiKey: apiKey,
    );

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final now = DateTime.now();

    final prompt = TextPart(
      "Current time: $now. Extract tasks, events, and notes from this image. "
      "Output ONLY JSON: "
      "{ 'tasks': [{'title', 'priority'}], 'events': [{'title', 'time', 'priority'}], 'notes': [{'title', 'priority'}] }. "
      "Priority: High/Medium/Low. Time: ISO 8601."
    );

    final content = [
      Content.multi([
        prompt,
        DataPart('image/jpeg', bytes),
      ])
    ];

    try {
      final response = await model.generateContent(content);
      return response.text;
    } catch (e) {
      return "Error: $e";
    }
  }

  static Future<String?> chunkTask(String taskTitle, String apiKey) async {
    final model = GenerativeModel(
      model: _modelName,
      apiKey: apiKey,
    );

    final prompt = [
      Content.text(
        "Break '$taskTitle' into 3-5 actionable sub-tasks. "
        "Return ONLY a JSON array of strings."
      )
    ];

    try {
      final response = await model.generateContent(prompt);
      return response.text;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> generateRecap(String allTasksJson, String apiKey) async {
    final model = GenerativeModel(
      model: _modelName,
      apiKey: apiKey,
    );

    final prompt = [
      Content.text(
        "Generate a brief, motivational recap of these tasks: $allTasksJson. "
        "Focus on priorities. Plain text + emojis only."
      )
    ];

    try {
      final response = await model.generateContent(prompt);
      return response.text;
    } catch (e) {
      return "Error generating recap: $e";
    }
  }
}
