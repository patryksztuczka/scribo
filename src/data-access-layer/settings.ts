import { DEFAULT_SETTINGS, settingsSchema, type AppSettings } from '../schemas/settings.ts';

const STORAGE_KEY = 'scribo.settings';

function readFromStorage(): unknown {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as unknown;
  } catch {
    return undefined;
  }
}

export function loadSettings(): AppSettings {
  const candidate = readFromStorage();
  const parsed = settingsSchema.safeParse(candidate ?? {});
  if (!parsed.success) {
    return DEFAULT_SETTINGS;
  }
  return { ...DEFAULT_SETTINGS, ...parsed.data };
}

export function saveSettings(next: AppSettings): void {
  const validated = settingsSchema.parse(next);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(validated));
}

export function updateSettings(partial: Partial<AppSettings>): AppSettings {
  const current = loadSettings();
  const merged = { ...current, ...partial } satisfies AppSettings;
  saveSettings(merged);
  return merged;
}
