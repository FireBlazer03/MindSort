import { GoogleGenerativeAI } from "@google/generative-ai";
import { MindTask } from "@/types";
import { parseGeminiResponse } from "./parseGeminiResponse";

export async function processAudio(
  audioBlob: Blob,
  apiKey: string
): Promise<{ tasks: MindTask[]; error?: string }> {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "gemini-3-flash-preview" });

  const arrayBuffer = await audioBlob.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const base64Audio = btoa(binary);

  const now = new Date().toISOString();

  const prompt =
    `You are a strict transcription assistant. The current date and time is ${now}.\n\n` +
    "Listen to this audio clip carefully. Extract ONLY what the speaker EXPLICITLY said. Categorize into:\n" +
    "1. 'tasks': Action items the speaker explicitly mentioned.\n" +
    "2. 'events': Events the speaker explicitly mentioned, as objects with 'title' (string) and 'time' (ISO 8601 string). If no specific time was spoken, use null.\n" +
    "3. 'notes': Other thoughts or information the speaker explicitly stated.\n\n" +
    "CRITICAL RULES:\n" +
    "- ONLY include things the speaker ACTUALLY SAID. Do NOT invent, assume, or infer tasks.\n" +
    "- If the audio is silent, unclear, contains only noise, or has no actionable speech, return: { \"tasks\": [], \"events\": [], \"notes\": [] }\n" +
    "- Do NOT generate example or placeholder content. Empty arrays are the correct response for unclear audio.\n" +
    "- Use the speaker's exact words. Do not rephrase or embellish.\n\n" +
    "Return ONLY valid JSON. No Markdown formatting. Format:\n" +
    '{ "tasks": [], "events": [], "notes": [] }';

  const mimeType = audioBlob.type || "audio/webm";

  let attempts = 0;
  while (attempts < 3) {
    try {
      const result = await model.generateContent([
        { text: prompt },
        {
          inlineData: {
            mimeType,
            data: base64Audio,
          },
        },
      ]);

      const text = result.response.text();
      if (!text) {
        return { tasks: [], error: "Gemini was silent. Try again." };
      }

      return parseGeminiResponse(text);
    } catch (e: unknown) {
      attempts++;
      const errorStr = String(e);

      if (
        errorStr.includes("429") ||
        errorStr.includes("503") ||
        errorStr.includes("500")
      ) {
        if (attempts < 3) {
          await new Promise((r) => setTimeout(r, attempts * 2000));
          continue;
        }
      }

      if (errorStr.includes("API_KEY_INVALID") || errorStr.includes("401")) {
        return {
          tasks: [],
          error: "Invalid API key. Please check your Gemini API key in settings.",
        };
      }

      return { tasks: [], error: `Error: ${errorStr}` };
    }
  }

  return {
    tasks: [],
    error: "Server is too busy. Please try a shorter recording.",
  };
}
