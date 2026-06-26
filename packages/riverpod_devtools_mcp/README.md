# riverpod_devtools_mcp

A [Model Context Protocol](https://modelcontextprotocol.io/) (MCP) server that lets AI tools like Claude Code read live Riverpod provider event logs from your running Flutter app.

This is an optional companion to [riverpod_devtools](../riverpod_devtools). With this set up, you can ask Claude Code things like:

> "Look at the current provider logs and fix any behavior that differs from the spec."

## How it works

1. `RiverpodDevToolsObserver` (from `riverpod_devtools`) starts a local HTTP server on `localhost:8788` whenever your Flutter app runs in debug mode.
2. This MCP server runs as a separate process (started by your AI tool over stdio) and relays requests to that HTTP server.
3. It exposes two tools: `get_riverpod_logs` and `clear_riverpod_logs`.

## Setup

**1. Set up `riverpod_devtools` in your Flutter app**

This server is only useful if your app already has the observer registered. See the [riverpod_devtools README](../riverpod_devtools#getting-started) if you haven't done this yet:

```dart
runApp(
  ProviderScope(
    observers: [RiverpodDevToolsObserver()],
    child: const MyApp(),
  ),
);
```

**2. Add the MCP server to Claude Code**

Create a `.mcp.json` in your project root (commit it so your whole team gets it):

```json
{
  "mcpServers": {
    "riverpod_devtools_mcp": {
      "type": "stdio",
      "command": "dart",
      "args": [
        "run",
        "${CLAUDE_PROJECT_DIR}/packages/riverpod_devtools_mcp/bin/riverpod_devtools_mcp.dart"
      ]
    }
  }
}
```

Or register it with the CLI instead of editing the file by hand:

```bash
claude mcp add --scope project riverpod_devtools_mcp -- \
  dart run '${CLAUDE_PROJECT_DIR}/packages/riverpod_devtools_mcp/bin/riverpod_devtools_mcp.dart'
```

Adjust the path to wherever `riverpod_devtools_mcp` actually lives relative to your project root.

**3. Run your Flutter app in debug mode**

```bash
flutter run
```

**4. Ask Claude Code to inspect the logs**

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

## License

See the [repository LICENSE](../../LICENSE).
