/// Ports used by the local HTTP server that bridges Riverpod provider
/// events to the riverpod_devtools_mcp server. Both
/// [RiverpodDevToolsHttpServer] (the observer side) and the MCP server
/// (the AI-tool side) must agree on these.
///
/// The observer binds the first free port in the range so that two debug
/// apps can run at once; the MCP server probes the whole range to discover
/// them.
const int riverpodDevToolsMcpPort = 8788;

/// Number of consecutive ports (starting at [riverpodDevToolsMcpPort])
/// the observer will try to bind and the MCP server will probe.
const int riverpodDevToolsMcpPortCount = 10;

/// The full port range, inclusive of the first, exclusive of the last.
Iterable<int> get riverpodDevToolsMcpPorts => Iterable.generate(
  riverpodDevToolsMcpPortCount,
  (i) => riverpodDevToolsMcpPort + i,
);
