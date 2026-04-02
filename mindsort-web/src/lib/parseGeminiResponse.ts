import { MindTask } from "@/types";

export function parseGeminiResponse(raw: string): {
  tasks: MindTask[];
  error?: string;
} {
  try {
    const cleaned = raw
      .replace(/```json/g, "")
      .replace(/```/g, "")
      .trim();

    const data = JSON.parse(cleaned);
    const newTasks: MindTask[] = [];

    if (data.tasks) {
      for (const item of data.tasks) {
        newTasks.push({
          id: Date.now().toString() + Math.random().toString(36).slice(2),
          title: String(item),
          type: "task",
          startTime: null,
        });
      }
    }

    if (data.events) {
      for (const item of data.events) {
        if (typeof item === "object" && item !== null) {
          newTasks.push({
            id: Date.now().toString() + Math.random().toString(36).slice(2),
            title: String(item.title || item),
            type: "event",
            startTime: item.time || null,
          });
        } else {
          newTasks.push({
            id: Date.now().toString() + Math.random().toString(36).slice(2),
            title: String(item),
            type: "event",
            startTime: null,
          });
        }
      }
    }

    if (data.notes) {
      for (const item of data.notes) {
        newTasks.push({
          id: Date.now().toString() + Math.random().toString(36).slice(2),
          title: String(item),
          type: "note",
          startTime: null,
        });
      }
    }

    return { tasks: newTasks };
  } catch {
    return { tasks: [], error: `Parsing Error. Raw: ${raw}` };
  }
}
