import { z } from 'zod';

// Single source of truth for settings shape
export const settingsSchema = z.object({
  geminiApiKey: z.string().trim(),
});

export type AppSettings = z.infer<typeof settingsSchema>;

export const DEFAULT_SETTINGS: AppSettings = { geminiApiKey: '' };
