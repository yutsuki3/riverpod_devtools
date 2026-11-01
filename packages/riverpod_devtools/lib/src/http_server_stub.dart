class RiverpodDevToolsHttpServer {
  RiverpodDevToolsHttpServer({int maxBufferSize = 1000});
  Map<String, Object?> Function(String action, String provider)?
      commandHandler;
  int? get boundPort => null;
  Future<void> start() async {}
  void stop() {}
  void addEvent(
    Map<String, Object?> event, {
    bool providerStillExists = false,
  }) {}
  void clearEvents() {}
  List<Map<String, Object?>> providerSnapshot({String? provider}) => const [];
  int? get oldestSeq => null;
  List<Map<String, Object?>> eventsFor({
    String? provider,
    String? type,
    int? limit,
    int? since,
    int? until,
    int? sinceSeq,
  }) =>
      const [];
}
