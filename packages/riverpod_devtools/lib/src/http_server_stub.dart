class RiverpodDevToolsHttpServer {
  RiverpodDevToolsHttpServer({int maxBufferSize = 1000});
  Map<String, Object?> Function(String action, String provider)?
      commandHandler;
  Future<void> start() async {}
  void stop() {}
  void addEvent(Map<String, Object?> event) {}
  void clearEvents() {}
  List<Map<String, Object?>> eventsFor({
    String? provider,
    String? type,
    int? limit,
  }) =>
      const [];
}
