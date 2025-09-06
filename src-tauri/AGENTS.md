# Scribo Native — Tauri/Rust/macOS AVFoundation

Guidelines for native code and Tauri commands. Keep effects at the edges; validate all cross-boundary data.

## Structure

- `src/`: Rust crate entry and Tauri command definitions.
- `native/`: Platform-specific implementations (e.g., macOS Objective‑C++ files `sources.mm`, `capture.mm`).
- `capabilities/`: Tauri capabilities configuration. Only expose necessary APIs to the renderer.

## Tauri commands

- Define narrow, explicit commands for: `list_apps`, `list_input_devices`, `start_capture`, `stop_capture`.
- Commands MUST:
  - Validate inputs (e.g., app PID, device identifiers, output path under allowlist base dir).
  - Return deterministic, serializable shapes. Avoid optional fields unless genuinely optional.
  - Be cancellable when long-running (capture, transcription). Provide `stop_capture` that performs cleanup.
- Do not block the main thread. Spawn tasks where appropriate; ensure proper shutdown on window close.

## Audio capture

- macOS: Use AVFoundation/AudioUnit to capture per‑application audio and input devices. Prefer mono 16 kHz PCM for ASR compatibility and efficiency.
- Always write under the allowlisted directory (e.g., `~/Downloads/scribo/`). Sanitize/normalize file names.
- Emit lightweight progress or level events if needed, but avoid high-frequency UI traffic.

## Error handling and logging

- Convert platform errors into structured Rust errors; map to concise messages across the Tauri boundary.
- Never log transcripts or audio contents. Redact identifiers if sensitive. Use structured logs with stable keys.

## Security

- Enforce a strict capabilities manifest. Expose only what the renderer needs.
- Validate all inbound parameters; reject unexpected shapes. Never accept arbitrary FS paths from the renderer.

## Testing and cleanup

- Ensure capture is stopped on error and on window close. Release file handles and audio units deterministically.
- Add smoke tests where reasonable (list devices/apps, start/stop capture in a temp directory).

## Scripts

- Build and run via Tauri CLI from repo root:
- `pnpm tauri dev`
- `pnpm tauri build`
