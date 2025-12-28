import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

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

class RiverpodInspector extends StatelessWidget {
  const RiverpodInspector({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Riverpod Inspector - Coming Soon'),
    );
  }
}