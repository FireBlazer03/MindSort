"use client";

import { useState } from "react";
import { Key } from "lucide-react";
import styles from "./ApiKeyModal.module.css";

interface ApiKeyModalProps {
  onSave: (key: string) => void;
  onClose?: () => void;
  initialKey?: string;
}

export default function ApiKeyModal({
  onSave,
  onClose,
  initialKey = "",
}: ApiKeyModalProps) {
  const [key, setKey] = useState(initialKey);

  const handleSave = () => {
    const trimmed = key.trim();
    if (trimmed) {
      onSave(trimmed);
    }
  };

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.iconWrap}>
          <Key size={32} color="var(--color-amber)" />
        </div>
        <h2 className={styles.title}>Enter your Gemini API Key</h2>
        <p className={styles.subtitle}>
          Your key is stored locally in your browser and never sent to our
          servers.
        </p>
        <input
          type="password"
          className={styles.input}
          placeholder="AIza..."
          value={key}
          onChange={(e) => setKey(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleSave()}
          autoFocus
        />
        <a
          href="https://aistudio.google.com/apikey"
          target="_blank"
          rel="noopener noreferrer"
          className={styles.link}
        >
          Get a free API key from Google AI Studio
        </a>
        <div className={styles.actions}>
          {onClose && (
            <button className={styles.cancelBtn} onClick={onClose}>
              Cancel
            </button>
          )}
          <button
            className={styles.saveBtn}
            onClick={handleSave}
            disabled={!key.trim()}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}
