import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiHelper {
  // ⚠️ PASTE YOUR API KEY HERE
  static const String _apiKey = 'AIzaSyCVxVXVYXrRo0NOuOf3szlsKWpwwFrr8h4';

  static Future<String?> processAudio(String filePath) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: _apiKey,
    );

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final now = DateTime.now();

    final prompt = TextPart(
      "You are an executive assistant. The current date and time is $now. "
      "Listen to this audio clip and extract lists. \n"
      "1. 'tasks': Simple strings.\n"
      "2. 'events': Objects with 'title' (string) and 'time' (ISO 8601 String, e.g., '2026-02-12T14:30:00'). If no time is mentioned, use null.\n"
      "3. 'notes': Simple strings.\n\n"
      "Return ONLY valid JSON. Do not use Markdown formatting. Format:\n"
      "{ \n"
      "  'tasks': ['Buy milk'], \n"
      "  'events': [{ 'title': 'Meeting', 'time': '2026-02-12T14:30:00' }], \n"
      "  'notes': ['I am tired'] \n"
      "}"
    );

    final content = Content.multi([
      prompt,
      DataPart('audio/mp4', bytes),
    ]);

    // --- NEW: RETRY LOGIC (The Patient System) ---
    int attempts = 0;
    while (attempts < 3) {
      try {
        final response = await model.generateContent([content]);
        return response.text;
      } catch (e) {
        attempts++;
        // If it's a "High Traffic" or "Server" error, wait and retry
        if (e.toString().contains('429') || e.toString().contains('503') || e.toString().contains('500')) {
          print("⚠️ Traffic High. Retrying in ${attempts * 2} seconds...");
          await Future.delayed(Duration(seconds: attempts * 2)); // Wait 2s, then 4s...
        } else {
          // If it's a real error (like Bad API Key), fail immediately
          return "Error: $e";
        }
      }
    }
    return "Error: Server is too busy. Please try a shorter recording.";
  }

  static Future<String?> processImage(String filePath) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: _apiKey,
    );

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final now = DateTime.now();

    final prompt = TextPart(
      "You are an executive assistant. The current date and time is $now. "
      "Look at this image (note, receipt, or screenshot) and extract lists. \n"
      "1. 'tasks': Simple strings.\n"
      "2. 'events': Objects with 'title' (string) and 'time' (ISO 8601 String). If no time is mentioned, use null.\n"
      "3. 'notes': Simple strings.\n\n"
      "Return ONLY valid JSON. Format:\n"
      "{ \n"
      "  'tasks': ['Buy milk'], \n"
      "  'events': [{ 'title': 'Meeting', 'time': '2026-02-12T14:30:00' }], \n"
      "  'notes': ['I am tired'] \n"
      "}"
    );

    final content = Content.multi([
      prompt,
      DataPart('image/jpeg', bytes),
    ]);

    try {
      final response = await model.generateContent([content]);
      return response.text;
    } catch (e) {
      return "Error: $e";
    }
  }

  static Future<String?> chunkTask(String taskTitle) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: _apiKey,
    );

    final prompt = [
      Content.text(
        "Break down this complex task or note into a logical list of 3-5 small, actionable sub-tasks. \n"
        "Task: '$taskTitle' \n\n"
        "Return ONLY a JSON array of strings. Example: ['Step 1', 'Step 2', 'Step 3']"
      )
    ];

    try {
      final response = await model.generateContent(prompt);
      return response.text;
    } catch (e) {
      return null;
    }
  }

  static Future<String?> generateRecap(String allTasksJson) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: _apiKey,
    );

    final prompt = [
      Content.text(
        "You are a productivity coach. Here is a JSON list of my current tasks, events, and notes: \n"
        "$allTasksJson \n\n"
        "Generate a brief, encouraging 'Weekly Recap' (3-4 short paragraphs). "
        "Highlight my main priorities, group similar tasks together, and gently remind me of any events. "
        "Keep the tone professional yet motivational. Do not use markdown code blocks, just plain text with emojis."
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