import { z } from 'zod';

const LAST_APP_PID_KEY = 'scribo.lastSelectedAppPid';
const LAST_MIC_ID_KEY = 'scribo.lastSelectedMicId';

const StoredIdSchema = z.string().trim().min(1);

export function loadLastSelectedAppPid(): string | undefined {
  const raw = localStorage.getItem(LAST_APP_PID_KEY);
  if (!raw) return undefined;
  const parsed = StoredIdSchema.safeParse(raw);
  return parsed.success ? parsed.data : undefined;
}

export function saveLastSelectedAppPid(pid: string): void {
  const validated = StoredIdSchema.parse(pid);
  localStorage.setItem(LAST_APP_PID_KEY, validated);
}

export function loadLastSelectedMicId(): string | undefined {
  const raw = localStorage.getItem(LAST_MIC_ID_KEY);
  if (!raw) return undefined;
  const parsed = StoredIdSchema.safeParse(raw);
  return parsed.success ? parsed.data : undefined;
}

export function saveLastSelectedMicId(id: string): void {
  const validated = StoredIdSchema.parse(id);
  localStorage.setItem(LAST_MIC_ID_KEY, validated);
}
