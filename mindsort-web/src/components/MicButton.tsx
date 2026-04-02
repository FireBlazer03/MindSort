"use client";

import { Mic, Square, Loader } from "lucide-react";
import { RecordingState } from "@/types";
import styles from "./MicButton.module.css";

interface MicButtonProps {
  state: RecordingState;
  onClick: () => void;
  disabled?: boolean;
}

export default function MicButton({ state, onClick, disabled }: MicButtonProps) {
  const isRecording = state === "recording";
  const isProcessing = state === "processing";

  return (
    <button
      className={`${styles.btn} ${styles[state]}`}
      onClick={onClick}
      disabled={disabled || isProcessing}
      aria-label={
        isProcessing
          ? "Processing audio"
          : isRecording
            ? "Stop recording"
            : "Start recording"
      }
    >
      {isProcessing ? (
        <Loader size={50} className={styles.spinner} />
      ) : isRecording ? (
        <Square size={50} fill="white" />
      ) : (
        <Mic size={50} />
      )}
    </button>
  );
}
