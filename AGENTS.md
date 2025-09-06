# Foodie - Calorie Counter Application (Vite, React, Node, Express, Monorepo, Tailwind, Zod)

This document defines the rules we strictly follow to keep the codebase readable, maintainable, reliable, and pragmatic. The philosophy is functional-first: pure logic at the core, side effects at the edges.

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

- Server: see `apps/server/AGENTS.md`
- Client: see `apps/client/AGENTS.md`

## Security Baselines

- Validate all inputs from clients, env, and external APIs. Never trust strings.
- Redact secrets in logs. Never log tokens, cookies, or Authorization headers.
- Enforce CORS/origin checks for HTTP surfaces where applicable. Bind to localhost for local servers.

## Performance and Pragmatism

- Avoid premature optimization and caching. Measure first; optimize only hotspots.
- Keep modules small. Split when files exceed reasonable cognitive load.
- Prefer streaming or pagination for large data.

## Typical mistakes to avoid

- Using any or implicit any, weakening strictness, or bypassing type errors instead of fixing design.
- Sequential await in loops when work is independent; ignoring timeouts and cancellation.
- Logging unstructured strings, secrets, or excessive data; hindering observability.
- Overengineering generic abstractions and utility layers before real use cases exist.
- Creating classes for simple data transformations that are better expressed as pure functions.

## Implementation Checklist

- Inputs validated with Zod at boundaries; outputs typed and validated where practical.
- Pure functions for core logic; side effects isolated in thin adapters.
- Timeouts and AbortSignal wired through I/O calls; no unbounded awaits.
- Structured logging with stable keys; no console noise.
- MCP tools register inputSchema and outputSchema; errors set isError: true.
- No usage of any; minimal unknown with prompt narrowing.
- No dead code; remove scaffolding and examples not in use.

## Naming conventions

- Avoid single-letter identifiers for variables, parameters, and functions. Exceptions: conventional loop indexes (i, j) inside short, local loops only.
- Prefer explicit descriptive names (response, devicesResponse, playlistTracks, normalizedTracks).
- File and directory names use kebab-case (e.g., `search-controller.ts`, `open-food-facts-service.ts`).

## Imports

- While importing things from other files, use .ts extension at the end
- If imported value is used only as a type, alywas add `type` key word (e.g., `import { type User } from ./schemas/user.ts`)
