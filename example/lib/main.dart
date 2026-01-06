import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

import 'pages/async_page.dart';
import 'pages/collections_page.dart';
import 'pages/dependencies_page.dart';
import 'pages/lifecycle_page.dart';
import 'pages/performance_page.dart';
import 'pages/todo_page.dart';

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
      title: 'Riverpod DevTools Example',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DevTools Example Home')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LifecyclePage()),
                  ),
              child: const Text('Lifecycle Demo (Init & Dispose)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ComplexStatePage()),
                  ),
              child: const Text('Complex State Demo (Edit)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AsyncStatePage()),
                  ),
              child: const Text('Async State Demo'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CollectionsPage()),
                  ),
              child: const Text('Collections Demo (Set/Map/Nested)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DependenciesPage()),
                  ),
              child: const Text('Dependencies Demo'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PerformancePage()),
                  ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.withValues(alpha: 0.2),
              ),
              child: const Text('Performance Demo (Large Data Test)'),
            ),
          ],
        ),
      ),
    );
  }
}
