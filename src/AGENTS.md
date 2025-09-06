# Scribo Client — React/Vite/Tailwind/Tauri Bridge

Guidelines for the renderer process (React). Optimize for purity, narrow edges, and defensive boundaries.

## Folders and roles

All names are kebab-case. Keep components pure; push side effects to a thin bridge.

- `src/components/`: Presentational and container components only. No direct `invoke` calls; import bridge functions. Props are explicit and fully typed.
- `src/hooks/`: Reusable hooks for local UI concerns (e.g., debouncing, visibility, metering animations). No cross-cutting app state.
- `src/tauri/data-access-layer`: Layer that calls Tauri commands or external APIs.
- `src/lib/`: Pure domain logic (chunking, prompt builders, transcript post-processing). No I/O.
- `src/`: App bootstrap (`App.tsx`), entry (`main.tsx`), global styles.

Create `src/tauri/bridge.ts` and `src/lib/` if missing.

## Components and side-effects

- Do not call Tauri `invoke` directly in components. Wrap each command in `src/data-access-layer` with Zod-validated I/O.
- Keep UI state local; lift only when multiple components need it. Represent long-running operations with explicit state and cancellers.
- Always show a visible recording indicator while capturing. Disable start controls until inputs are valid.

### Example bridge wrapper

```
// src/data-access-layer/audio.ts
import { invoke } from '@tauri-apps/api/core';
import { z } from 'zod';

const AppItem = z.object({ pid: z.number(), name: z.string(), bundleId: z.string().optional().default('') });
export type AppItem = z.infer<typeof AppItem>;

export async function listApps(): Promise<readonly AppItem[]> {
  const raw = await invoke('list_apps');
  return z.array(AppItem).parse(raw);
}
```

## State, data flow, and validation

- Zod-validate all data from native commands and events at the bridge. Components consume typed values only.
- All file paths passed from UI must originate from the allowlisted base directory provided by the bridge. Never accept arbitrary user-supplied paths.

## Styling

- Use Tailwind utility classes. Keep animations cheap; throttle/animate VU meters off the main render path (e.g., `setTimeout` or `requestAnimationFrame`).
- Keep global styles minimal in `src/index.css`.

## Accessibility and UX

- Use clear labels for system audio and microphone selection.
- Provide progress/feedback on long operations (listing apps/devices, capturing, transcribing).
- Respect platform conventions; avoid surprising keyboard shortcuts.

## Performance

- Avoid unnecessary re-renders by stabilizing props and keys.
- Code-split heavy views when needed.

## Security

- Never start recording without explicit user action.
- Redact secrets and never log transcript contents. Avoid logging large payloads.

## Scripts

- Install deps: `pnpm install`
- React dev: `pnpm dev`
- Lint: `pnpm lint` (use `type` on type-only imports; include `.ts` extension in internal imports)
