# MCP Integration

`riverpod_devtools` ships an optional [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server that lets AI tools like Claude Code read live Riverpod provider event logs from your running Flutter app.

With this set up, you can ask Claude Code things like:

> "Look at the current provider logs and fix any behavior that differs from the spec."

## How it works

1. `RiverpodDevToolsObserver` (already required for the DevTools extension — see [README](README.md#getting-started)) starts a local HTTP server on `localhost:8788` whenever your Flutter app runs in debug mode.
2. The bundled `riverpod_devtools_mcp` executable runs as a separate process (started by your AI tool over stdio) and relays requests to that HTTP server.
3. It exposes two tools: `get_riverpod_logs` and `clear_riverpod_logs`.

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

| Tool | Description |
|---|---|
| `get_riverpod_logs` | Returns buffered provider lifecycle events (`provider_added`, `provider_updated`, `provider_failed`, `provider_disposed`) as JSON. Not a general app log — Riverpod state changes only. Optional parameters: `limit` (return only the most recent N events), `provider` (return only events for the provider with this exact name), and `type` (return only events of one type — pass `provider_failed` to fetch only errors, each carrying the error type, message, and a trimmed stack trace). Use them to keep responses small — the buffer holds up to 1000 events. Every event carries a monotonic `seq` number for unambiguous ordering, and `provider_updated` events may carry `triggeredBy` — the dependency update(s) that likely caused the recomputation, inferred from the static dependency graph plus temporal proximity (marked `triggerConfidence: "inferred"`) — so update cascades ("why did this provider rebuild?") can be traced. |
| `get_provider_state` | Returns the **current** state of live providers (one snapshot entry per provider: name, status `active`/`failed`, latest value, error details when failed, last-update timestamp) — use this instead of `get_riverpod_logs` when you want current values rather than history. Disposed providers are not listed. Optional `provider` parameter to fetch a single provider. |
| `get_dependency_graph` | Returns the provider dependency graph: nodes (providers with runtime status `active`/`failed`/`unknown`) and directed edges from dependent to dependency with the dependency kind (`watch`/`read`/`listen`) and source location. Edges come from static analysis, so the app must have loaded `riverpod_dependencies.json` (see setup step 1). Optional `provider` parameter restricts the result to that provider's transitive dependencies and dependents. |
| `get_provider_stats` | Returns aggregated activity/health stats per provider: update count (total and in the last 10s, plus a rate), async load duration (min/avg/max of observed `loading`→`data`/`error` transitions), dispose→re-create churn count, and `isHighFrequency`/`isSlowLoading` flags. Use this to answer "which provider is rebuilding excessively?" or "is anything loading unusually slowly?" without analyzing the full event log yourself. Optional `provider` parameter to fetch a single provider. |
| `invalidate_provider` | **Mutates app state**: invalidates the named provider, forcing it to recompute (state resets to what `build()` produces). Pass `refresh: true` to re-read it immediately instead of waiting for the next read/listener. The provider must be currently alive. Useful for reproducing flows (`clear_riverpod_logs` → `invalidate_provider` → `get_riverpod_logs`) or testing how the UI reacts to a state reset. |
| `clear_riverpod_logs` | Clears the event buffer (the `get_provider_state` snapshot is unaffected — clearing history does not change current state). |

## Requirements & limitations

- The HTTP server only starts in debug mode (`kDebugMode == true`) and only on native platforms (Android, iOS, macOS, Linux, Windows). Web is not supported.
- The machine running this MCP server must be able to reach `localhost:8788` where the Flutter app is running. This holds for:
  - Desktop apps (macOS/Linux/Windows) running on the same machine
  - iOS Simulator (shares the host's network)
- It does **not** work out of the box for:
  - Real devices (iOS/Android) — the device has its own network namespace; you'd need manual port forwarding (e.g. `iproxy` for iOS, `adb forward tcp:8788 tcp:8788` for Android)
  - Android Emulator — same reason, needs `adb forward tcp:8788 tcp:8788`
