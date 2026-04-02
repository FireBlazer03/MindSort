"use client";

import { useEffect } from "react";
import styles from "./SnackBar.module.css";

interface SnackBarProps {
  message: string;
  onUndo: () => void;
  onDismiss: () => void;
}

export default function SnackBar({ message, onUndo, onDismiss }: SnackBarProps) {
  useEffect(() => {
    const timer = setTimeout(onDismiss, 4000);
    return () => clearTimeout(timer);
  }, [onDismiss]);

  return (
    <div className={styles.bar}>
      <span className={styles.message}>{message}</span>
      <button className={styles.undoBtn} onClick={onUndo}>
        UNDO
      </button>
    </div>
  );
}
