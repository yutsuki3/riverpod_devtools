import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

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
          ],
        ),
      ),
    );
  }
}

// Scene 1: Lifecycle (Init/Dispose)
final lifecycleCounterProvider =
    NotifierProvider.autoDispose<LifecycleCounter, int>(
      LifecycleCounter.new,
      name: 'CounterProvider',
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

// Scene 2: Complex State (Edit)
class Todo {
  final String id;
  final String description;
  final bool completed;

  Todo({required this.id, required this.description, this.completed = false});

  Todo copyWith({String? id, String? description, bool? completed}) {
    return Todo(
      id: id ?? this.id,
      description: description ?? this.description,
      completed: completed ?? this.completed,
    );
  }

  @override
  String toString() =>
      'Todo(id: $id, description: $description, completed: $completed)';
}

final todoListProvider = NotifierProvider.autoDispose<TodoList, List<Todo>>(
  TodoList.new,
  name: 'TodoListProvider',
);

class TodoList extends Notifier<List<Todo>> {
  @override
  List<Todo> build() => [];

  void add(String description) {
    state = [
      ...state,
      Todo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        description: description,
      ),
    ];
  }

  void toggle(String id) {
    state = [
      for (final todo in state)
        if (todo.id == id) todo.copyWith(completed: !todo.completed) else todo,
    ];
  }

  void remove(String id) {
    state = state.where((target) => target.id != id).toList();
  }
}

class ComplexStatePage extends ConsumerWidget {
  const ComplexStatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todoListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Complex State: List Edit')),
      body: ListView.builder(
        itemCount: todos.length,
        itemBuilder: (context, index) {
          final todo = todos[index];
          return ListTile(
            title: Text(todo.description),
            leading: Checkbox(
              value: todo.completed,
              onChanged:
                  (_) => ref.read(todoListProvider.notifier).toggle(todo.id),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed:
                  () => ref.read(todoListProvider.notifier).remove(todo.id),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ref.read(todoListProvider.notifier).add('Task ${todos.length + 1}');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Scene 3: Async State
final asyncNumberProvider = FutureProvider.autoDispose<int>((ref) async {
  await Future.delayed(const Duration(seconds: 2));
  return Random().nextInt(100);
}, name: 'AsyncNumberProvider');

// Scene 4: Collections (Set/Map/Nested)
class CollectionState {
  final Set<String> tags;
  final Map<String, int> scores;
  final List<Map<String, dynamic>> nested;

  CollectionState({
    required this.tags,
    required this.scores,
    required this.nested,
  });

  Map<String, dynamic> toJson() {
    return {
      'tags': tags.toList(),
      'scores': scores,
      'nested': nested,
    };
  }

  @override
  String toString() =>
      'CollectionState(tags: $tags, scores: $scores, nested: $nested)';
}

final collectionsProvider =
    NotifierProvider.autoDispose<CollectionsNotifier, CollectionState>(
  CollectionsNotifier.new,
  name: 'CollectionsProvider',
);

class CollectionsNotifier extends Notifier<CollectionState> {
  @override
  CollectionState build() {
    return CollectionState(
      tags: {'flutter', 'dart', 'riverpod'},
      scores: {'alice': 100, 'bob': 85, 'charlie': 92},
      nested: [
        {
          'user': 'alice',
          'data': {'age': 25, 'city': 'Tokyo'},
          'items': [1, 2, 3],
        },
        {
          'user': 'bob',
          'data': {'age': 30, 'city': 'Osaka'},
          'items': [4, 5],
        },
      ],
    );
  }

  void addTag(String tag) {
    state = CollectionState(
      tags: {...state.tags, tag},
      scores: state.scores,
      nested: state.nested,
    );
  }

  void removeTag(String tag) {
    state = CollectionState(
      tags: state.tags.where((t) => t != tag).toSet(),
      scores: state.scores,
      nested: state.nested,
    );
  }

  void updateScore(String name, int score) {
    state = CollectionState(
      tags: state.tags,
      scores: {...state.scores, name: score},
      nested: state.nested,
    );
  }

  void addNestedItem() {
    final newItem = {
      'user': 'user${state.nested.length + 1}',
      'data': {
        'age': Random().nextInt(50) + 20,
        'city': ['Tokyo', 'Osaka', 'Kyoto'][Random().nextInt(3)],
      },
      'items': List.generate(Random().nextInt(5) + 1, (_) => Random().nextInt(100)),
    };
    state = CollectionState(
      tags: state.tags,
      scores: state.scores,
      nested: [...state.nested, newItem],
    );
  }
}

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

class CollectionsPage extends ConsumerWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Collections: Set/Map/Nested')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check DevTools to see tree structure for:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Set<String> tags'),
            const Text('• Map<String, int> scores'),
            const Text('• Nested List<Map<String, dynamic>>'),
            const Divider(height: 32),
            // Set section
            const Text(
              'Set (Tags):',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: collections.tags
                  .map((tag) => Chip(
                        label: Text(tag),
                        onDeleted: () =>
                            ref.read(collectionsProvider.notifier).removeTag(tag),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final newTag = 'tag${collections.tags.length + 1}';
                ref.read(collectionsProvider.notifier).addTag(newTag);
              },
              child: const Text('Add Tag'),
            ),
            const Divider(height: 32),
            // Map section
            const Text(
              'Map (Scores):',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...collections.scores.entries.map((entry) => ListTile(
                  title: Text(entry.key),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${entry.value}', style: const TextStyle(fontSize: 18)),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => ref
                            .read(collectionsProvider.notifier)
                            .updateScore(entry.key, entry.value + 5),
                      ),
                    ],
                  ),
                )),
            const Divider(height: 32),
            // Nested section
            const Text(
              'Nested Structures:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Count: ${collections.nested.length}'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                ref.read(collectionsProvider.notifier).addNestedItem();
              },
              child: const Text('Add Nested Item'),
            ),
          ],
        ),
      ),
    );
  }
}
