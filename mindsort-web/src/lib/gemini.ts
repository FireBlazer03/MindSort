import { GoogleGenerativeAI } from "@google/generative-ai";
import { MindTask } from "@/types";
import { parseGeminiResponse } from "./parseGeminiResponse";

export async function processAudio(
  audioBlob: Blob,
  apiKey: string
): Promise<{ tasks: MindTask[]; error?: string }> {
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash-preview" });

  const arrayBuffer = await audioBlob.arrayBuffer();
  const base64Audio = btoa(
    String.fromCharCode(...new Uint8Array(arrayBuffer))
  );

  const now = new Date().toISOString();

  const prompt =
    `You are an executive assistant. The current date and time is ${now}. ` +
    "Listen to this audio clip and extract lists. \n" +
    "1. 'tasks': Simple strings.\n" +
    "2. 'events': Objects with 'title' (string) and 'time' (ISO 8601 String, e.g., '2026-02-12T14:30:00'). If no time is mentioned, use null.\n" +
    "3. 'notes': Simple strings.\n\n" +
    "Return ONLY valid JSON. Do not use Markdown formatting. Format:\n" +
    "{ \n" +
    "  \"tasks\": [\"Buy milk\"], \n" +
    '  "events": [{ "title": "Meeting", "time": "2026-02-12T14:30:00" }], \n' +
    '  "notes": ["I am tired"] \n' +
    "}";

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
