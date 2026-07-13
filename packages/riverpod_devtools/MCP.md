# MCP Integration

`riverpod_devtools` ships an optional [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server that lets AI tools like Claude Code read live Riverpod provider state from your running Flutter app — event logs, current values, the dependency graph, and health stats — and drive it (invalidate/refresh a provider, or set its value).

With this set up, you can ask Claude Code things like:

> "Look at the current provider logs and fix any behavior that differs from the spec."

## How it works

1. `RiverpodDevToolsObserver` (already required for the DevTools extension — see [README](README.md#getting-started)) starts a local HTTP server on `localhost` (the first free port in `8788`–`8797`) whenever your Flutter app runs in debug mode.
2. The bundled `riverpod_devtools_mcp` executable runs as a separate process (started by your AI tool over stdio) and relays requests to that HTTP server.
3. It exposes a set of tools for **reading** state (logs, current state, dependency graph, stats) and **acting** on it (invalidate/refresh a provider, set a value) — see [Tools](#tools) below.

## Setup

This requires `riverpod_devtools` to already be set up per the main [README](README.md#getting-started) (dependency added, `RiverpodDevToolsObserver` registered).

**1. Add the MCP server to Claude Code**

Create a `.mcp.json` in your project root (commit it so your whole team gets it):

```json
{
  "mcpServers": {
    "riverpod_devtools_mcp": {
      "type": "stdio",
      "command": "dart",
      "args": ["run", "riverpod_devtools:riverpod_devtools_mcp"]
    }
  }
}
```

Or register it with the CLI instead of editing the file by hand:

```bash
claude mcp add --scope project riverpod_devtools_mcp -- dart run riverpod_devtools:riverpod_devtools_mcp
```

This works the same way as `dart run riverpod_devtools:analyze` — no path needed, since `riverpod_devtools` is already a dependency of your Flutter app.

**2. Run your Flutter app in debug mode**

```bash
flutter run
```

**3. Ask Claude Code to inspect the logs**

The `get_riverpod_logs` tool is now available and Claude Code will call it automatically when you ask about provider state or runtime behavior. Ask it to clear the buffer (`clear_riverpod_logs`) before reproducing a specific flow so only the relevant events show up.

## Tools

Every tool below (except `list_riverpod_apps`) accepts an optional `port` parameter. When a single app is running it is selected automatically; when several are running, call `list_riverpod_apps` first and pass the chosen `port`.

| Tool | Description |
|---|---|
| `list_riverpod_apps` | Lists the running debug apps that expose Riverpod events, with each app's `port`, provider count, and event count (each app binds the first free port in `8788`–`8797`). Use this only when more than one app is running, to pick a `port` for the other tools. |
| `get_riverpod_logs` | Returns buffered provider lifecycle events (`provider_added`, `provider_updated`, `provider_failed`, `provider_disposed`). Not a general app log — Riverpod state changes only. **Responses are compact by default** (slim events with summarized values), which is typically ~4× smaller than the raw payload; pass `view: "summary"` for a per-provider overview (counts by kind + each provider's latest value, no per-event stream) or `view: "full"` for the complete raw events (full nested value trees, stack traces, static-dependency metadata) when you need a value the compact form summarized. Filter with `limit` (most recent N), `provider` (exact name), `type` (one kind — e.g. `provider_failed` for errors only), and `since`/`until` (a timestamp window in epoch ms — narrows to a recent window without clearing the buffer); the buffer holds up to 1000 events. Every event carries a monotonic `seq`, and `provider_updated` events may carry `triggeredBy` — the dependency update(s) that likely caused the recomputation (inferred from the static graph + temporal proximity) — so update cascades ("why did this provider rebuild?") can be traced. |
| `get_provider_state` | Returns the **current** state of live providers (one entry per provider: name, a stable `instanceId`, status `active`/`failed`, latest value, error details when failed, last-update timestamp) — use this instead of `get_riverpod_logs` when you want current values rather than history. **Compact by default**; pass `view: "full"` for the complete snapshot (includes `providerId` and the static dependency list). When `nameIsUnique` is `false` the name is shared by several providers, so use the `instanceId` to target a specific one. Disposed providers are not listed. Optional `provider` parameter matches a name or an exact `instanceId`. |
| `get_dependency_graph` | Returns the provider dependency graph: nodes (providers with runtime status `active`/`failed`/`unknown`) and directed edges from dependent to dependency with the dependency kind (`watch`/`read`/`listen`). Edges come from static analysis, so the app must have loaded `riverpod_dependencies.json` (see setup step 1). **Compact by default** (topology only); pass `view: "full"` for each edge's source location (file/line/column) and per-node metadata. Optional `provider` parameter restricts the result to that provider's transitive dependencies and dependents. |
| `get_provider_stats` | Returns aggregated activity/health stats per provider: update count and rate, async load duration (min/avg/max of observed `loading`→`data`/`error` transitions), dispose→re-create churn count, and `highFrequency`/`slowLoading` warning flags. **Compact by default**, ordered most-interesting-first (flagged, then by rate) and without the 30s sparkline buckets; pass `view: "full"` for the raw stats including `updateBuckets`. Use this to answer "which provider is rebuilding excessively?" or "is anything loading unusually slowly?" without analyzing the full event log yourself. Optional `provider` parameter to fetch a single provider. |
| `invalidate_provider` | **Mutates app state**: invalidates a provider (by name or by exact `instanceId`), forcing it to recompute (state resets to what `build()` produces). Pass `refresh: true` to re-read it immediately instead of waiting for the next read/listener. The provider must have been observed by the app at least once; it can be invalidated repeatedly, and `refresh` recreates it even if it was since disposed. If several providers share the same name the call is rejected with `ambiguous: true` and the candidate `instanceId`s — pass the exact one. Useful for reproducing flows (`clear_riverpod_logs` → `invalidate_provider` → `get_riverpod_logs`) or testing how the UI reacts to a state reset. |
| `set_provider_value` | **Mutates app state**: sets a provider (by name or exact `instanceId`) to a specific primitive `value` (number, boolean, string, or null) — unlike `invalidate_provider`, which only resets it to what `build()` produces. Only providers with a writable notifier and primitive state are supported (e.g. `StateProvider`, `NotifierProvider`); plain/`Future`/`Stream` providers, or providers whose state is an object or `AsyncValue`, are rejected with `supported: false` and a reason. If several providers share the name the call is rejected with the candidate `instanceId`s. Use it to force an edge-case state and observe how the UI reacts. |
| `clear_riverpod_logs` | Clears the event buffer (the `get_provider_state` snapshot is unaffected — clearing history does not change current state). |

## Requirements & limitations

- The HTTP server only starts in debug mode (`kDebugMode == true`) and only on native platforms (Android, iOS, macOS, Linux, Windows). Web is not supported.
- Each debug app binds the first free port in the range `8788`–`8797`, so two apps can run at once; the MCP server discovers them by probing the range (see `list_riverpod_apps`). Manual `adb forward` / `iproxy` for real devices should forward whichever port the app logged.
- The machine running this MCP server must be able to reach `localhost:8788` (or the next free port) where the Flutter app is running. This holds for:
  - Desktop apps (macOS/Linux/Windows) running on the same machine
  - iOS Simulator (shares the host's network)
- It does **not** work out of the box for:
  - Real devices (iOS/Android) — the device has its own network namespace; you'd need manual port forwarding (e.g. `iproxy` for iOS, `adb forward tcp:8788 tcp:8788` for Android)
  - Android Emulator — same reason, needs `adb forward tcp:8788 tcp:8788`
