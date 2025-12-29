import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  runApp(const RiverpodDevToolsExtension());
}

class RiverpodDevToolsExtension extends StatelessWidget {
  const RiverpodDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RiverpodInspector(),
    );
  }
}

class RiverpodInspector extends StatefulWidget {
  const RiverpodInspector({super.key});

  @override
  State<RiverpodInspector> createState() => _RiverpodInspectorState();
}

class _RiverpodInspectorState extends State<RiverpodInspector> {
  final List<ProviderEvent> _events = [];
  final Map<String, ProviderInfo> _providers = {};

  String? _lastEventKey;
  DateTime? _lastEventTime;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
  }

  Future<void> _subscribeToEvents() async {
    await serviceManager.onServiceAvailable;

    final service = serviceManager.service!;
    const streamId = 'Extension';

    await service.streamListen(streamId);

    service.onExtensionEvent.listen((Event event) {
      final kind = event.extensionKind;
      if (kind == null || !kind.startsWith('riverpod:')) return;

      final data = event.extensionData?.data ?? {};
      final providerName = data['provider'] as String? ?? 'Unknown';

      final eventKey =
          '$kind:$providerName:${data['newValue'] ?? data['value']}';
      final now = DateTime.now();
      if (_lastEventKey == eventKey &&
          _lastEventTime != null &&
          now.difference(_lastEventTime!).inMilliseconds < 100) {
        return;
      }
      _lastEventKey = eventKey;
      _lastEventTime = now;

      setState(() {
        if (kind == 'riverpod:provider_added') {
          _providers[providerName] = ProviderInfo(
            name: providerName,
            value: data['value']?.toString() ?? 'null',
            status: ProviderStatus.active,
          );
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.added,
                providerName: providerName,
                value: data['value']?.toString(),
                timestamp: DateTime.now(),
              ));
        } else if (kind == 'riverpod:provider_updated') {
          _providers[providerName] = ProviderInfo(
            name: providerName,
            value: data['newValue']?.toString() ?? 'null',
            status: ProviderStatus.active,
          );
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.updated,
                providerName: providerName,
                previousValue: data['previousValue']?.toString(),
                value: data['newValue']?.toString(),
                timestamp: DateTime.now(),
              ));
        } else if (kind == 'riverpod:provider_disposed') {
          _providers[providerName] = ProviderInfo(
            name: providerName,
            value: _providers[providerName]?.value ?? 'null',
            status: ProviderStatus.disposed,
          );
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.disposed,
                providerName: providerName,
                timestamp: DateTime.now(),
              ));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: _buildProviderList(),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _buildEventLog(),
        ),
      ],
    );
  }

  Widget _buildProviderList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Colors.grey[900],
          width: double.infinity,
          height: 48,
          alignment: Alignment.centerLeft,
          child: Text(
            'Providers (${_providers.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: _providers.isEmpty
              ? const Center(child: Text('No providers yet'))
              : ListView.builder(
                  itemCount: _providers.length,
                  itemBuilder: (context, index) {
                    final provider = _providers.values.elementAt(index);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        provider.status == ProviderStatus.active
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: 12,
                        color: provider.status == ProviderStatus.active
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: Text(provider.name),
                      subtitle: Text(
                        provider.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEventLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Colors.grey[900],
          width: double.infinity,
          height: 48,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Text(
                'Event Log',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => setState(() => _events.clear()),
                tooltip: 'Clear log',
              ),
            ],
          ),
        ),
        Expanded(
          child: _events.isEmpty
              ? const Center(child: Text('No events yet'))
              : ListView.builder(
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return _buildEventTile(event);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEventTile(ProviderEvent event) {
    final color = switch (event.type) {
      EventType.added => Colors.green,
      EventType.updated => Colors.blue,
      EventType.disposed => Colors.orange,
    };

    final icon = switch (event.type) {
      EventType.added => Icons.add_circle_outline,
      EventType.updated => Icons.edit_outlined,
      EventType.disposed => Icons.remove_circle_outline,
    };

    final subtitle = switch (event.type) {
      EventType.added => event.value ?? 'null',
      EventType.updated => '${event.previousValue} → ${event.value}',
      EventType.disposed => 'disposed',
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 18),
      title: Text(event.providerName),
      subtitle: Text(subtitle),
      trailing: Text(
        '${event.timestamp.hour.toString().padLeft(2, '0')}:'
        '${event.timestamp.minute.toString().padLeft(2, '0')}:'
        '${event.timestamp.second.toString().padLeft(2, '0')}',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
    );
  }
}

enum ProviderStatus { active, disposed }

enum EventType { added, updated, disposed }

class ProviderInfo {
  final String name;
  final String value;
  final ProviderStatus status;

  ProviderInfo({
    required this.name,
    required this.value,
    required this.status,
  });
}

class ProviderEvent {
  final EventType type;
  final String providerName;
  final String? previousValue;
  final String? value;
  final DateTime timestamp;

  ProviderEvent({
    required this.type,
    required this.providerName,
    this.previousValue,
    this.value,
    required this.timestamp,
  });
}
