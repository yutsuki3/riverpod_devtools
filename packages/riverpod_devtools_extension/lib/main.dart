import 'dart:async';
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
  StreamSubscription? _extensionSubscription;
  final Set<String> _processedEventKeys = {};

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _extensionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _subscribeToEvents() async {
    await serviceManager.onServiceAvailable;

    final service = serviceManager.service!;
    const streamId = 'Extension';

    await service.streamListen(streamId);

    _extensionSubscription = service.onExtensionEvent.listen((Event event) {
      final kind = event.extensionKind;
      if (kind == null || !kind.startsWith('riverpod:')) return;

      final data = event.extensionData?.data ?? {};
      final providerName = data['provider'] as String? ?? 'Unknown';
      final providerId = data['providerId'] as String? ?? 'Unknown';
      final value = (data['newValue'] ?? data['value'])?.toString() ?? 'null';
      final timestamp = data['timestamp'] as int?;

      // Create a unique key for this event to deduplicate
      // Format: kind:providerId:value
      // We don't use timestamp in the key because we WANT to deduplicate
      // identically valued updates that happen inside the same logical "tick"
      final eventKey = '$kind:$providerId:$value';

      if (_processedEventKeys.contains(eventKey)) {
        return;
      }

      _processedEventKeys.add(eventKey);
      // Clear the key after a short period to allow future identical updates
      Timer(const Duration(milliseconds: 100), () {
        _processedEventKeys.remove(eventKey);
      });

      setState(() {
        final eventTimestamp = timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(timestamp)
            : DateTime.now();

        if (kind == 'riverpod:provider_added') {
          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: value,
            status: ProviderStatus.active,
          );
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.added,
                providerId: providerId,
                providerName: providerName,
                value: value,
                timestamp: eventTimestamp,
              ));
        } else if (kind == 'riverpod:provider_updated') {
          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: value,
            status: ProviderStatus.active,
          );
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.updated,
                providerId: providerId,
                providerName: providerName,
                previousValue: data['previousValue']?.toString(),
                value: value,
                timestamp: eventTimestamp,
              ));
        } else if (kind == 'riverpod:provider_disposed') {
          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: _providers[providerName]?.value ?? 'null',
            status: ProviderStatus.disposed,
          );
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.disposed,
                providerId: providerId,
                providerName: providerName,
                timestamp: eventTimestamp,
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
  final String id;
  final String name;
  final String value;
  final ProviderStatus status;

  ProviderInfo({
    required this.id,
    required this.name,
    required this.value,
    required this.status,
  });
}

class ProviderEvent {
  final EventType type;
  final String providerId;
  final String providerName;
  final String? previousValue;
  final String? value;
  final DateTime timestamp;

  ProviderEvent({
    required this.type,
    required this.providerId,
    required this.providerName,
    this.previousValue,
    this.value,
    required this.timestamp,
  });
}
