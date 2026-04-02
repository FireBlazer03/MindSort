"use client";

import { useState, useCallback } from "react";
import { Trash2, KeyRound } from "lucide-react";
import { MindTask, RecordingState } from "@/types";
import { useLocalStorage } from "@/hooks/useLocalStorage";
import { useAudioRecorder } from "@/hooks/useAudioRecorder";
import { processAudio } from "@/lib/gemini";
import { downloadICS } from "@/lib/calendarExport";
import MicButton from "@/components/MicButton";
import StatusText from "@/components/StatusText";
import ErrorBanner from "@/components/ErrorBanner";
import TaskList from "@/components/TaskList";
import EditDialog from "@/components/EditDialog";
import SnackBar from "@/components/SnackBar";
import ApiKeyModal from "@/components/ApiKeyModal";
import styles from "./page.module.css";

interface SnackBarState {
  message: string;
  deletedTask: MindTask;
  deletedIndex: number;
}

export default function Home() {
  const [tasks, setTasks] = useLocalStorage<MindTask[]>("saved_tasks", []);
  const [apiKey, setApiKey] = useLocalStorage<string>("gemini_api_key", "");
  const [recordingState, setRecordingState] = useState<RecordingState>("idle");
  const [error, setError] = useState<string | null>(null);
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [snackBar, setSnackBar] = useState<SnackBarState | null>(null);
  const [showApiKeyModal, setShowApiKeyModal] = useState(false);

  const { startRecording, stopRecording, isSupported } = useAudioRecorder();

  const needsApiKey = !apiKey;

  const handleToggleRecording = useCallback(async () => {
    if (!apiKey) {
      setShowApiKeyModal(true);
      return;
    }

    try {
      if (recordingState === "recording") {
        setRecordingState("processing");
        setError(null);

        const blob = await stopRecording();
        if (!blob || blob.size === 0) {
          setError("Recording failed — no audio captured. Please try again.");
          setRecordingState("idle");
          return;
        }

        // Audio blobs under 1KB are almost certainly silence/empty
        if (blob.size < 1000) {
          setError("Recording too short or silent. Please speak clearly and try again.");
          setRecordingState("idle");
          return;
        }

        const result = await processAudio(blob, apiKey);

        if (result.error) {
          setError(result.error);
        }

        if (result.tasks.length > 0) {
          setTasks((prev) => [...result.tasks, ...prev]);
        } else if (!result.error) {
          setError("No tasks, events, or notes were found in your recording. Try speaking more clearly.");
        }

        setRecordingState("idle");
      } else {
        setError(null);
        await startRecording();
        setRecordingState("recording");
      }
    } catch (e) {
      setRecordingState("idle");
      setError(`Error: ${e}`);
    }
  }, [recordingState, apiKey, startRecording, stopRecording, setTasks]);

  const handleDelete = useCallback(
    (index: number) => {
      const deleted = tasks[index];
      setTasks((prev) => prev.filter((_, i) => i !== index));
      setSnackBar({
        message: `${deleted.title} completed`,
        deletedTask: deleted,
        deletedIndex: index,
      });
    },
    [tasks, setTasks]
  );

  const handleUndo = useCallback(() => {
    if (snackBar) {
      setTasks((prev) => {
        const newTasks = [...prev];
        newTasks.splice(snackBar.deletedIndex, 0, snackBar.deletedTask);
        return newTasks;
      });
      setSnackBar(null);
    }
  }, [snackBar, setTasks]);

  const handleEdit = useCallback(
    (newTitle: string) => {
      if (editingIndex !== null) {
        setTasks((prev) =>
          prev.map((t, i) =>
            i === editingIndex ? { ...t, title: newTitle } : t
          )
        );
        setEditingIndex(null);
      }
    },
    [editingIndex, setTasks]
  );

  const handleClearAll = useCallback(() => {
    setTasks([]);
  }, [setTasks]);

  const handleSaveApiKey = useCallback(
    (key: string) => {
      setApiKey(key);
      setShowApiKeyModal(false);
    },
    [setApiKey]
  );

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <div className={styles.headerSpacer} />
        <h1 className={styles.title}>MindSort</h1>
        <div className={styles.headerActions}>
          {tasks.length > 0 && (
            <button
              className={styles.iconBtn}
              onClick={handleClearAll}
              aria-label="Clear all tasks"
            >
              <Trash2 size={20} />
            </button>
          )}
          <button
            className={styles.iconBtn}
            onClick={() => setShowApiKeyModal(true)}
            aria-label="API key settings"
          >
            <KeyRound size={20} />
          </button>
        </div>
      </header>

      <div className={styles.micSection}>
        <MicButton
          state={recordingState}
          onClick={handleToggleRecording}
          disabled={!isSupported || needsApiKey}
        />
        <div className={styles.statusWrap}>
          <StatusText state={recordingState} />
        </div>
        {!isSupported && (
          <ErrorBanner message="Your browser does not support audio recording." />
        )}
        {error && <ErrorBanner message={error} />}
      </div>

      <div className={styles.divider} />

      <TaskList
        tasks={tasks}
        onDelete={handleDelete}
        onEdit={(i) => setEditingIndex(i)}
        onAddToCalendar={(i) => downloadICS(tasks[i])}
      />

      {(needsApiKey || showApiKeyModal) && (
        <ApiKeyModal
          onSave={handleSaveApiKey}
          onClose={needsApiKey ? undefined : () => setShowApiKeyModal(false)}
          initialKey={apiKey}
        />
      )}

      {editingIndex !== null && (
        <EditDialog
          initialTitle={tasks[editingIndex].title}
          onSave={handleEdit}
          onClose={() => setEditingIndex(null)}
        />
      )}

      {snackBar && (
        <SnackBar
          message={snackBar.message}
          onUndo={handleUndo}
          onDismiss={() => setSnackBar(null)}
        />
      )}
    </div>
  );
}
