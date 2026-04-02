"use client";

import { RecordingState } from "@/types";
import styles from "./StatusText.module.css";

interface StatusTextProps {
  state: RecordingState;
}

const labels: Record<RecordingState, string> = {
  idle: "Tap to Dump",
  recording: "Listening...",
  processing: "Sorting Brain...",
};

export default function StatusText({ state }: StatusTextProps) {
  return (
    <p className={`${styles.text} ${state === "processing" ? styles.amber : ""}`}>
      {labels[state]}
    </p>
  );
}
