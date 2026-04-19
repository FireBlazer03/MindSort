import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiHelper {
  static Future<String?> processAudio(String filePath, String apiKey) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: apiKey,
    );

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final now = DateTime.now();

    final prompt = TextPart(
      "You are an executive assistant. The current date and time is $now. "
      "Listen to this audio clip and extract lists. \n"
      "1. 'tasks': Objects with 'title' (string) and 'priority' (High, Medium, or Low based on tone/content).\n"
      "2. 'events': Objects with 'title' (string), 'time' (ISO 8601), and 'priority'.\n"
      "3. 'notes': Objects with 'title' (string) and 'priority'.\n\n"
      "Return ONLY valid JSON. Format:\n"
      "{ \n"
      "  'tasks': [{ 'title': 'Buy milk', 'priority': 'Medium' }], \n"
      "  'events': [{ 'title': 'Meeting', 'time': '2026-02-12T14:30:00', 'priority': 'High' }], \n"
      "  'notes': [{ 'title': 'I am tired', 'priority': 'Low' }] \n"
      "}"
    );

    final content = Content.multi([
      prompt,
      DataPart('audio/mp4', bytes),
    ]);

    int attempts = 0;
    while (attempts < 3) {
      try {
        final response = await model.generateContent([content]);
        return response.text;
      } catch (e) {
        attempts++;
        if (e.toString().contains('429') || e.toString().contains('503') || e.toString().contains('500')) {
          await Future.delayed(Duration(seconds: attempts * 2));
        } else {
          return "Error: $e";
        }
      }
    }
    return "Error: Server is too busy. Please try a shorter recording.";
  }

  static Future<String?> processImage(String filePath, String apiKey) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: apiKey,
    );

    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final now = DateTime.now();

    final prompt = TextPart(
      "You are an executive assistant. The current date and time is $now. "
      "Look at this image (note, receipt, or screenshot) and extract lists. \n"
      "1. 'tasks': Objects with 'title' (string) and 'priority' (High, Medium, or Low).\n"
      "2. 'events': Objects with 'title' (string), 'time' (ISO 8601 String), and 'priority'.\n"
      "3. 'notes': Objects with 'title' (string) and 'priority'.\n\n"
      "Return ONLY valid JSON. Format:\n"
      "{ \n"
      "  'tasks': [{ 'title': 'Buy milk', 'priority': 'Medium' }], \n"
      "  'events': [{ 'title': 'Meeting', 'time': '2026-02-12T14:30:00', 'priority': 'High' }], \n"
      "  'notes': [{ 'title': 'I am tired', 'priority': 'Low' }] \n"
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

  static Future<String?> chunkTask(String taskTitle, String apiKey) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: apiKey,
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

  static Future<String?> generateRecap(String allTasksJson, String apiKey) async {
    final model = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: apiKey,
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
