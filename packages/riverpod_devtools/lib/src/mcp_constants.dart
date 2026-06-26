/// Port used by the local HTTP server that bridges Riverpod provider events
/// to the riverpod_devtools_mcp server. Both [RiverpodDevToolsHttpServer]
/// (the observer side) and the MCP server (the AI-tool side) must agree on
/// this value.
const int riverpodDevToolsMcpPort = 8788;
