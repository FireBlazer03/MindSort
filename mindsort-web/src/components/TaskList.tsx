"use client";

import { MindTask } from "@/types";
import TaskCard from "./TaskCard";
import styles from "./TaskList.module.css";

interface TaskListProps {
  tasks: MindTask[];
  onDelete: (index: number) => void;
  onEdit: (index: number) => void;
  onAddToCalendar: (index: number) => void;
}

export default function TaskList({
  tasks,
  onDelete,
  onEdit,
  onAddToCalendar,
}: TaskListProps) {
  if (tasks.length === 0) {
    return (
      <div className={styles.empty}>
        <p>Your organized thoughts will appear here</p>
      </div>
    );
  }

  return (
    <div className={styles.list}>
      {tasks.map((task, index) => (
        <TaskCard
          key={task.id}
          task={task}
          onDelete={() => onDelete(index)}
          onEdit={() => onEdit(index)}
          onAddToCalendar={() => onAddToCalendar(index)}
        />
      ))}
    </div>
  );
}
