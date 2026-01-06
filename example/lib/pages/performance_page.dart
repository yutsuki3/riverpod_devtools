import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Providers using Notifier as per guidelines ---

class LargeListNotifier extends Notifier<List<int>> {
  @override
  List<int> build() => [];
  void set(List<int> value) => state = value;
}

final largeListProvider = NotifierProvider<LargeListNotifier, List<int>>(
  LargeListNotifier.new,
);

class LargeMapNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() => {};
  void set(Map<String, dynamic> value) => state = value;
}

final largeMapProvider =
    NotifierProvider<LargeMapNotifier, Map<String, dynamic>>(
      LargeMapNotifier.new,
    );

class DeepNestedNotifier extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() => {};
  void set(Map<String, dynamic> value) => state = value;
}

final deepNestedProvider =
    NotifierProvider<DeepNestedNotifier, Map<String, dynamic>>(
      DeepNestedNotifier.new,
    );

// --- UI ---

class PerformancePage extends ConsumerWidget {
  const PerformancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(title: 'Large List Test'),
            _ActionButton(
              label: 'List: 100 items',
              onPressed:
                  () => ref
                      .read(largeListProvider.notifier)
                      .set(List.generate(100, (i) => i)),
            ),
            _ActionButton(
              label: 'List: 1,000 items',
              onPressed:
                  () => ref
                      .read(largeListProvider.notifier)
                      .set(List.generate(1000, (i) => i)),
            ),
            _ActionButton(
              label: 'List: 10,000 items (Ultra)',
              color: Colors.redAccent,
              onPressed:
                  () => ref
                      .read(largeListProvider.notifier)
                      .set(List.generate(10000, (i) => i)),
            ),
            const Divider(height: 32),
            _SectionHeader(title: 'Large Map Test'),
            _ActionButton(
              label: 'Map: 50 keys',
              onPressed:
                  () => ref.read(largeMapProvider.notifier).set({
                    for (var i = 0; i < 50; i++) 'key_$i': 'value_$i',
                  }),
            ),
            _ActionButton(
              label: 'Map: 500 keys',
              onPressed:
                  () => ref.read(largeMapProvider.notifier).set({
                    for (var i = 0; i < 500; i++) 'key_$i': 'value_$i',
                  }),
            ),
            _ActionButton(
              label: 'Map: 5,000 keys (Ultra)',
              color: Colors.redAccent,
              onPressed:
                  () => ref.read(largeMapProvider.notifier).set({
                    for (var i = 0; i < 5000; i++) 'key_$i': 'value_$i',
                  }),
            ),
            const Divider(height: 32),
            _SectionHeader(title: 'Deep Nesting Test'),
            _ActionButton(
              label: 'Nest: 5 levels',
              onPressed:
                  () => ref
                      .read(deepNestedProvider.notifier)
                      .set(_createNested(5)),
            ),
            _ActionButton(
              label: 'Nest: 20 levels',
              onPressed:
                  () => ref
                      .read(deepNestedProvider.notifier)
                      .set(_createNested(20)),
            ),
            _ActionButton(
              label: 'Nest: 50 levels (Ultra)',
              color: Colors.redAccent,
              onPressed:
                  () => ref
                      .read(deepNestedProvider.notifier)
                      .set(_createNested(50)),
            ),
            const Divider(height: 32),
            const Text(
              'Tips: Open Riverpod DevTools and check the Event Log while clicking these buttons. '
              'The app should not freeze even with "Ultra" buttons.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _createNested(int levels) {
    if (levels <= 0) return {'leaf': 'done'};
    return {
      'level_$levels': _createNested(levels - 1),
      'metadata': {'timestamp': DateTime.now().toString(), 'level': levels},
    };
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ElevatedButton(
        style:
            color != null
                ? ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                )
                : null,
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
