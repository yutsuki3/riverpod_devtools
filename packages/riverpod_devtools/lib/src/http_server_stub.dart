class RiverpodDevToolsHttpServer {
  const RiverpodDevToolsHttpServer({int maxBufferSize = 1000});
  Future<void> start() async {}
  void stop() {}
  void addEvent(Map<String, Object?> event) {}
  void clearEvents() {}
  List<Map<String, Object?>> eventsFor({String? provider, int? limit}) =>
      const [];
}
