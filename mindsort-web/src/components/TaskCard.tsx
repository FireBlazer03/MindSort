"use client";

import { useRef, useState, useCallback } from "react";
import { Calendar, Lightbulb, CheckCircle, CalendarPlus, GripVertical } from "lucide-react";
import { MindTask } from "@/types";
import styles from "./TaskCard.module.css";

interface TaskCardProps {
  task: MindTask;
  onDelete: () => void;
  onEdit: () => void;
  onAddToCalendar: () => void;
}

const typeConfig = {
  event: { icon: Calendar, color: "var(--color-orange)", label: "EVENT" },
  note: { icon: Lightbulb, color: "var(--color-teal)", label: "NOTE" },
  task: { icon: CheckCircle, color: "var(--color-blue)", label: "TASK" },
} as const;

export default function TaskCard({
  task,
  onDelete,
  onEdit,
  onAddToCalendar,
}: TaskCardProps) {
  const config = typeConfig[task.type];
  const Icon = config.icon;

  // Swipe state
  const [offsetX, setOffsetX] = useState(0);
  const [swiping, setSwiping] = useState(false);
  const startXRef = useRef(0);
  const currentXRef = useRef(0);

  // Long press
  const longPressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handlePointerDown = useCallback(
    (e: React.PointerEvent) => {
      startXRef.current = e.clientX;
      currentXRef.current = e.clientX;

      longPressTimer.current = setTimeout(() => {
        onEdit();
        longPressTimer.current = null;
      }, 500);
    },
    [onEdit]
  );

  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    currentXRef.current = e.clientX;
    const diff = currentXRef.current - startXRef.current;

    // Cancel long press if dragging
    if (Math.abs(diff) > 10 && longPressTimer.current) {
      clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }

    if (Math.abs(diff) > 20) {
      setSwiping(true);
      setOffsetX(diff);
    }
  }, []);

  const handlePointerUp = useCallback(() => {
    if (longPressTimer.current) {
      clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }

    if (Math.abs(offsetX) > 150) {
      // Dismiss
      setOffsetX(offsetX > 0 ? 500 : -500);
      setTimeout(onDelete, 200);
    } else {
      setOffsetX(0);
    }
    setSwiping(false);
  }, [offsetX, onDelete]);

  const handlePointerLeave = useCallback(() => {
    if (longPressTimer.current) {
      clearTimeout(longPressTimer.current);
      longPressTimer.current = null;
    }
    if (swiping) {
      setOffsetX(0);
      setSwiping(false);
    }
  }, [swiping]);

  const formatTime = (iso: string) => {
    const d = new Date(iso);
    return `${d.getHours()}:${d.getMinutes().toString().padStart(2, "0")}`;
  };

  return (
    <div className={styles.wrapper}>
      {/* Background colors for swipe */}
      <div
        className={styles.bg}
        style={{
          background: offsetX > 0 ? "#4CAF50" : "#F44336",
          opacity: Math.min(Math.abs(offsetX) / 150, 1),
        }}
      />
      <div
        className={styles.card}
        style={{
          transform: `translateX(${offsetX}px)`,
          transition: swiping ? "none" : "transform 200ms ease",
          ['--type-color' as string]: config.color,
        }}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerLeave={handlePointerLeave}
        onContextMenu={(e) => e.preventDefault()}
      >
        <div className={styles.leading}>
          <Icon size={22} color={config.color} />
        </div>
        <div className={styles.content}>
          <p className={styles.title}>{task.title}</p>
          <span className={styles.typeLabel} style={{ color: config.color }}>
            {config.label}
          </span>
          {task.startTime && (
            <span className={styles.time}>{formatTime(task.startTime)}</span>
          )}
        </div>
        <div className={styles.trailing}>
          {task.type === "event" ? (
            <button
              className={styles.calBtn}
              onClick={(e) => {
                e.stopPropagation();
                onAddToCalendar();
              }}
              aria-label="Add to calendar"
            >
              <CalendarPlus size={18} color="var(--color-amber)" />
            </button>
          ) : (
            <GripVertical size={18} color="var(--text-hint)" />
          )}
        </div>
      </div>
    </div>
  );
}
