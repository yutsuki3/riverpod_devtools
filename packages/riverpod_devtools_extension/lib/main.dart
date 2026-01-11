import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';
import 'package:riverpod_devtools_extension/src/widgets/inspector/inspector_view.dart';

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
  late final InspectorNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = InspectorNotifier();
    _notifier.initialize();
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InspectorView(notifier: _notifier);
  }
}
