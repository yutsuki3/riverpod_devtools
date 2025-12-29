import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

final counterProvider = StateProvider<int>((ref) => 0);
final nameProvider = StateProvider<String>((ref) => 'Flutter');

void main() {
  runApp(
    ProviderScope(
      observers: [RiverpodDevToolsObserver()],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riverpod DevTools Test',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    final name = ref.watch(nameProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('DevTools Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Count: $count', style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 16),
            Text('Name: $name', style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed:
                  () => ref.read(nameProvider.notifier).state = 'Riverpod',
              child: const Text('Change Name'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(counterProvider.notifier).state++,
        child: const Icon(Icons.add),
      ),
    );
  }
}
