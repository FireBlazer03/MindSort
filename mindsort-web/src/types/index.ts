export interface MindTask {
  id: string;
  title: string;
  type: 'task' | 'event' | 'note';
  startTime: string | null; // ISO 8601
}

export type RecordingState = 'idle' | 'recording' | 'processing';
