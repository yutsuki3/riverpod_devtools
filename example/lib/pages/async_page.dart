import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Scene 3: Async State
final asyncNumberProvider = FutureProvider.autoDispose<int>((ref) async {
  await Future.delayed(const Duration(seconds: 2));
  return Random().nextInt(100);
}, name: 'AsyncNumberProvider');

class AsyncStatePage extends ConsumerWidget {
  const AsyncStatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(asyncNumberProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Async State')),
      body: Center(
        child: asyncValue.when(
          data:
              (value) =>
                  Text('Value: $value', style: const TextStyle(fontSize: 24)),
          loading: () => const CircularProgressIndicator(),
          error: (e, st) => Text('Error: $e'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.invalidate(asyncNumberProvider),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
