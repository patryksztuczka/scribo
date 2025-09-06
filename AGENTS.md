# Scribo — Audio Capture, Transcription, and Summaries (Tauri, React, Rust, Tailwind, Zod)

This document defines the rules we strictly follow to keep the codebase readable, maintainable, reliable, and pragmatic. The philosophy is functional-first: pure logic at the core, side effects at the edges.

Scribo is a desktop app that:

- Captures audio from selected applications and microphones (system + mic).
- Produces transcriptions and concise summaries from those recordings.

Frontend is React/Vite. Native surface is Tauri (Rust + platform native). All cross-boundary data is validated.

## Core principles

- Purity first: business logic is composed of small, pure functions. Perform I/O (HTTP, FS, env, time) at the edges.
- Explicitness: explicit types, narrow interfaces, descriptive names. No magic, no implicit behavior.
- Defensive boundaries: validate all external inputs at module boundaries with Zod; never trust runtime data.
- YAGNI and small surface area: build only what is necessary; remove dead or demo code promptly.

## TypeScript Rules

### Strict typing

- tsconfig.json uses strict mode; do not weaken it.
- Do not use any. Prefer unknown at boundaries, then narrow via Zod or TypeScript guards.
- Prefer type aliases for unions/intersections; use interface only for extensible object shapes.
- Use readonly in arrays/tuples/object properties for intent and safety.
- Model precise domain types. Avoid over-generic types that hide meaning.

### Names and structure

- Functions are verbs; values are nouns. Avoid abbreviations. Prefer clarity over brevity.
- Exported APIs must have full, explicit signatures. Avoid optional output shapes.
- Co-locate types with their modules if scope is local; lift only shared, stable types.

### Error typing

- Treat unknown errors explicitly. Convert to domain errors early.
- Never throw strings. If throwing, throw Error (or a narrow subclass), and prefer returning typed Results at boundaries.

## App-specific practices

- Native backend (Tauri/Rust): see `src-tauri/AGENTS.md`
- Frontend (React/Vite): see `src/AGENTS.md`

Domain notes:

- Audio capture and processing are side effects. Keep the core logic (selection, scheduling, chunking, summarization prompts) as pure functions.

## Security Baselines

- Validate all inputs from the renderer, env, and external APIs. Never trust strings.
- Never start recording without explicit user intent. Always show a visible recording indicator in the UI.
- Store audio and transcripts locally by default (e.g., under the user's downloads directory `scribo/`).
- Redact secrets in logs. Never log file contents, transcripts, or authorization headers.
- Sanitize and restrict file-system access. Only allow writes within an allowlisted base directory.
- If remote APIs are used for transcription, clearly surface network usage, and remove any PII before sending when applicable.

## Performance and Pragmatism

- Avoid premature optimization. Measure first (capture overhead, transcription throughput, UI responsiveness).
- Keep modules small. Split when files exceed reasonable cognitive load.
- Prefer streaming where possible (e.g., incremental transcription UI updates).
- Prefer mono 16 kHz PCM for ASR when compatible to reduce bandwidth and processing.
- Throttle/animate meters efficiently; avoid tight loops on the UI thread.

## Typical mistakes to avoid

- Using any or implicit any, weakening strictness, or bypassing type errors instead of fixing design.
- Sequential await in loops when work is independent; ignoring timeouts and cancellation.
- Invoking Tauri commands deep inside presentational components instead of via a thin bridge.
- Forgetting to stop capture on errors/window close; leaking file handles or threads.
- Logging unstructured strings, secrets, transcripts, or excessive data.
- Overengineering abstractions before real use cases exist.

## Implementation Checklist

- Inputs validated with Zod at TS boundaries and with Rust types/Zod-equivalent checks on the native side.
- Pure functions for core UI logic; side effects isolated in a `data-access-layer` and Rust commands.
- Long-running native operations (capture/transcribe) are cancellable; provide a `stop` command and handle cleanup.
- Structured logging with stable keys; redact content; no console noise.
- No usage of any; minimal unknown with prompt narrowing.
- No dead code; remove scaffolding and examples not in use.
- Persist files only under the app's allowlisted directory; sanitize user-supplied paths.

## Naming conventions

- Avoid single-letter identifiers for variables, parameters, and functions. Exceptions: conventional loop indexes (i, j) inside short, local loops only.
- Prefer explicit descriptive names (response, devicesResponse, playlistTracks, normalizedTracks).
- File and directory names use kebab-case (e.g., `search-controller.ts`, `open-food-facts-service.ts`).

## Imports

- While importing things from other files, use .ts extension at the end
- If imported value is used only as a type, always add `type` keyword (e.g., `import { type User } from './schemas/user.ts'`)
