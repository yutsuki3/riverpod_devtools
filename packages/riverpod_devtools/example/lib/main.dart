import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';
import 'providers.dart';

final counterProvider = StateProvider<int>((ref) => 0);
final nameProvider = StateProvider<String>((ref) => 'Flutter');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load static dependencies from JSON
  try {
    final jsonString = await rootBundle.loadString(
      'lib/riverpod_dependencies.json',
    );
    RiverpodDevToolsRegistry.instance.loadFromJson(jsonString);
    // ignore: avoid_print
    print('✅ Loaded ${RiverpodDevToolsRegistry.instance.count} providers with static analysis');
  } catch (e) {
    // ignore: avoid_print
    print('⚠️  Static analysis not available: $e');
    // ignore: avoid_print
    print('   Run: dart run riverpod_devtools:analyze');
  }

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
    final doubleCount = ref.watch(doubleCounterProvider);
    final displayText = ref.watch(displayTextProvider);
    final asyncData = ref.watch(asyncDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('DevTools Test')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Simple providers
              const Text('Simple Providers:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Count: $count', style: const TextStyle(fontSize: 20)),
              Text('Name: $name', style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 24),

              // Providers with dependencies
              const Text('Providers with Dependencies:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Double Count: $doubleCount', style: const TextStyle(fontSize: 20, color: Colors.blue)),
              Text('Display: $displayText', style: const TextStyle(fontSize: 20, color: Colors.green)),
              const SizedBox(height: 8),
              asyncData.when(
                data: (data) => Text('Async: $data', style: const TextStyle(fontSize: 20, color: Colors.purple)),
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e', style: const TextStyle(fontSize: 16, color: Colors.red)),
              ),
              const SizedBox(height: 32),

              // Action buttons
              ElevatedButton(
                onPressed: () => ref.read(nameProvider.notifier).state = 'Riverpod',
                child: const Text('Change Name'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(counterProvider.notifier).state++,
        child: const Icon(Icons.add),
      ),
    );
  }
}
