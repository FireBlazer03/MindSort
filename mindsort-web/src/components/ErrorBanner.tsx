"use client";

import styles from "./ErrorBanner.module.css";

interface ErrorBannerProps {
  message: string;
}

export default function ErrorBanner({ message }: ErrorBannerProps) {
  return (
    <div className={styles.banner}>
      <p className={styles.text}>{message}</p>
    </div>
  );
}
