"use client";

import { useState } from "react";
import styles from "./EditDialog.module.css";

interface EditDialogProps {
  initialTitle: string;
  onSave: (newTitle: string) => void;
  onClose: () => void;
}

export default function EditDialog({
  initialTitle,
  onSave,
  onClose,
}: EditDialogProps) {
  const [title, setTitle] = useState(initialTitle);

  const handleSave = () => {
    const trimmed = title.trim();
    if (trimmed) {
      onSave(trimmed);
    }
  };

  return (
    <div className={styles.overlay} onClick={onClose}>
      <div className={styles.dialog} onClick={(e) => e.stopPropagation()}>
        <h3 className={styles.heading}>Edit Task</h3>
        <input
          className={styles.input}
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleSave()}
          placeholder="Enter new text"
          autoFocus
        />
        <div className={styles.actions}>
          <button className={styles.cancelBtn} onClick={onClose}>
            Cancel
          </button>
          <button
            className={styles.saveBtn}
            onClick={handleSave}
            disabled={!title.trim()}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
