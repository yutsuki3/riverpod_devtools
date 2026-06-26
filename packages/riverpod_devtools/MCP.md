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
| `get_riverpod_logs` | Returns buffered provider lifecycle events (`provider_added`, `provider_updated`, `provider_disposed`) as JSON. Not a general app log — Riverpod state changes only. |
| `clear_riverpod_logs` | Clears the event buffer. |

## Requirements & limitations

- The HTTP server only starts in debug mode (`kDebugMode == true`) and only on native platforms (Android, iOS, macOS, Linux, Windows). Web is not supported.
- The machine running this MCP server must be able to reach `localhost:8788` where the Flutter app is running. This holds for:
  - Desktop apps (macOS/Linux/Windows) running on the same machine
  - iOS Simulator (shares the host's network)
- It does **not** work out of the box for:
  - Real devices (iOS/Android) — the device has its own network namespace; you'd need manual port forwarding (e.g. `iproxy` for iOS, `adb forward tcp:8788 tcp:8788` for Android)
  - Android Emulator — same reason, needs `adb forward tcp:8788 tcp:8788`
