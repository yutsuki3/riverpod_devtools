import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Scene 1: Lifecycle (Init/Dispose)
final lifecycleCounterProvider =
    NotifierProvider.autoDispose<LifecycleCounter, int>(
      LifecycleCounter.new,
      name: 'lifecycleCounterProvider',
    );

class LifecycleCounter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() {
    state++;
  }
}

class LifecyclePage extends ConsumerWidget {
  const LifecyclePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(lifecycleCounterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lifecycle: Init & Dispose')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Leaving this page will DISPOSE user provider.\n'
                'Entering initialized it.',
                textAlign: TextAlign.center,
              ),
            ),
            Text('Count: $count', style: const TextStyle(fontSize: 24)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:
            () => ref.read(lifecycleCounterProvider.notifier).increment(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
