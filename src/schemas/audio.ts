import { z } from 'zod';

export const AppItemSchema = z.object({
  pid: z.number(),
  name: z.string(),
  bundleId: z.string().optional().default(''),
});

export const AppListSchema = z.array(AppItemSchema);

export type AppItem = z.infer<typeof AppItemSchema>;

export const InputDeviceItemSchema = z.object({
  id: z.string(),
  name: z.string(),
  uniqueId: z.string().optional().default(''),
});

export const InputDeviceListSchema = z.array(InputDeviceItemSchema);

export type InputDeviceItem = z.infer<typeof InputDeviceItemSchema>;
