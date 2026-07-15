# CLAUDE.md

Guidance for AI agents (and new contributors) working in this repository.
Read this before making changes — the architecture has a few non-obvious
shapes that are easy to get wrong.

## What this project is

A [Flutter DevTools](https://flutter.dev/devtools) extension for
[Riverpod](https://riverpod.dev): it inspects and monitors providers in
real time (event log, current values, dependency graph, health stats). It
also bundles an optional **MCP server** so AI tools can read the same live
state and drive it (invalidate / refresh / set a provider).

Design values, in priority order: **clear for users, lightweight, stable,
easy for AI to consume.** New features are *not* a goal — prefer making the
existing surface clearer, lighter, and more reliable.

## Repository layout

```
packages/
  riverpod_devtools/            # Published package (pub.dev)
    lib/src/observer.dart          # RiverpodDevToolsObserver (in-app entry point)
    lib/src/http_server_io.dart    # In-app HTTP server (debug only, ports 8788–8797)
    lib/src/mcp/                    # MCP server + compact.dart (payload reshaping)
    lib/src/cli/                    # Static dependency analyzer (AST-based)
    bin/analyze.dart, bin/riverpod_devtools_mcp.dart  # Executables
    test/                           # Unit tests (strong coverage here)
  riverpod_devtools_extension/   # DevTools extension UI (Flutter web app)
    lib/src/providers/inspector_notifier.dart  # Consumes the event stream
example/                         # Standalone example app
tool/release.sh                  # Builds the extension web app + copies it into the package
```

## Data flow — there are TWO parallel paths

The observer is the single source of events. Each Riverpod lifecycle
callback serializes the value, builds an event map, and fans out to **two
independent consumers**:

```
                                   ┌─ developer.postEvent('riverpod:*')  ──▶ DevTools UI
RiverpodDevToolsObserver ──event──┤    (VM service Extension stream)         (extension package)
                                   └─ in-app HTTP server (debug only)  ──▶ MCP server ──▶ AI tool
                                        ports 8788–8797                     (compact.dart reshapes)
```

- **Path 1 (UI):** `postEvent` → the extension package's `InspectorNotifier`
  decodes events into typed models and renders them.
- **Path 2 (MCP):** the observer feeds an in-app HTTP server; the separate
  `riverpod_devtools_mcp` process discovers it (probes the port range),
  fetches `/logs` `/providers` `/graph` `/stats`, and reshapes payloads via
  `lib/src/mcp/compact.dart` before returning them to the AI.

**Naming gotcha:** "MCP server" is overloaded. The in-app **HTTP server**
(`http_server_io.dart`) is what MCP connects to; the **MCP process**
(`bin/riverpod_devtools_mcp.dart`) is a separate stdio server. Be explicit
about which one you mean.

HTTP endpoints: `/ping`, `/logs`, `/providers`, `/graph`, `/stats`,
`POST /commands`, `DELETE /logs`.
MCP tools: `list_riverpod_apps`, `get_riverpod_logs`, `get_provider_state`,
`get_dependency_graph`, `get_provider_stats`, `invalidate_provider`,
`set_provider_value`, `clear_riverpod_logs`.

## The two packages do NOT share code

This is deliberate (`packages/riverpod_devtools/lib/src/provider_stats.dart`
documents it) and the single biggest footgun. Logic is **implemented twice**,
so a rule change must be made in both places or the UI and MCP will disagree:

| Concept        | Package copy                                        | Extension copy                                                    |
|----------------|-----------------------------------------------------|-------------------------------------------------------------------|
| Provider stats | `lib/src/provider_stats.dart`                       | `lib/src/utils/provider_stats.dart`                               |
| Event model    | serialized in `observer.dart` / `utils/serialization.dart` | `lib/src/models/provider_event.dart`, `provider_info.dart` |

When you change stats thresholds or the event shape, **grep both packages.**
A drift guard (`test/provider_stats_sync_test.dart` in the main package)
machine-checks that the shared stats constants and the sparkline bucketing
function stay identical across the two copies.

## Wire format is an implicit contract across THREE places

The serialized event/value shape is coupled, with no shared schema. If you
change it, update all three:

1. **Producer** — `lib/src/utils/serialization.dart` + `observer.dart`
   (`_buildProviderEventData`).
2. **MCP reshaper** — `lib/src/mcp/compact.dart`.
3. **UI decoder** — extension `inspector_notifier.dart` (`_normalizeValue`, `_subscribeToEvents`).

## Compact vs full (MCP output contract)

`compact.dart` is the AI-facing reshaping layer and is purely functional /
heavily unit-tested. Keep it that way.

- Values over `_maxValueChars` (200) collapse to summaries like
  `Type(n items)` / `{…n keys}`; the `lossy: true` flag is preserved so the
  AI knows truncation happened.
- Stats are ordered most-interesting-first.
- `edgesNote` setup hints are preserved even in compact view.
- `view: "full"` is the escape hatch that returns the untruncated payload.

The MCP tool descriptions (in `riverpod_devtools_mcp_server.dart`) are
carefully written — they state mutation effects, auto-port behavior, and
ambiguity handling. Treat them as part of the product; keep them accurate.

**Serializer caps (upstream of compact).** `serializeValue`
(`lib/src/utils/serialization.dart`) bounds work/payload *at the source*, on
both paths: depth (10), collection breadth (first 100 elements, with
`truncated`/`totalItems`), and toString() length (4000 chars). Anything
trimmed is flagged `lossy: true`. `compactValue` prefers `totalItems` when
summarizing a truncated collection so the reported count is the true size.

## Commands

```bash
# Main package (from packages/riverpod_devtools)
flutter pub get
flutter analyze
flutter test

# Extension UI (from packages/riverpod_devtools_extension)
flutter pub get
flutter analyze
flutter test

# Rebuild the extension and copy the web build into the published package
./tool/release.sh          # builds riverpod_devtools_extension and copies to
                           # packages/riverpod_devtools/extension/devtools/build

# Regenerate an example's static dependency graph (run from that example dir)
dart run riverpod_devtools:analyze
```

The built extension lives in
`packages/riverpod_devtools/extension/devtools/build/` and ships with the
package. `analyzer` and `dart_mcp` are runtime dependencies (used by the
CLI / MCP binaries), which is why the SDK minimums are relatively high.

## Conventions

- The observer's HTTP server and MCP path only run in **debug mode**; they
  never start in profile/release or on web.
- Keep changes minimal and behavior-preserving unless the task says
  otherwise. Prefer adding a regression test over expanding scope.
