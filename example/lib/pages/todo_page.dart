import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  name: 'todoListProvider',
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
