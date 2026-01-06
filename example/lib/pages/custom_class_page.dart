import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class User {
  final int id;
  final String name;
  final Company company;
  final List<Role> roles;

  User({
    required this.id,
    required this.name,
    required this.company,
    required this.roles,
  });

  User copyWith({int? id, String? name, Company? company, List<Role>? roles}) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      company: company ?? this.company,
      roles: roles ?? this.roles,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, company: $company, roles: $roles)';
  }
}

class Company {
  final String name;
  final String location;

  Company({required this.name, required this.location});

  @override
  String toString() {
    return 'Company(name: $name, location: $location)';
  }
}

enum Role { admin, editor, viewer }

final userProvider = NotifierProvider<UserNotifier, User>(UserNotifier.new);

class UserNotifier extends Notifier<User> {
  @override
  User build() {
    return User(
      id: 1,
      name: 'Taro Yamada',
      company: Company(name: 'Google', location: 'Tokyo'),
      roles: [Role.admin, Role.editor],
    );
  }

  void updateName(String name) {
    state = state.copyWith(name: name);
  }

  void makeComplex() {
    state = state.copyWith(name: 'Complex User', roles: [Role.admin]);
    // Note: To show deeply nested lists in toString(), we'd need a field that supports it.
    // Let's add a dummy field or just explain it to the user.
  }

  void updateCompany(String name, String location) {
    state = state.copyWith(company: Company(name: name, location: location));
  }

  void addRole(Role role) {
    if (!state.roles.contains(role)) {
      state = state.copyWith(roles: [...state.roles, role]);
    }
  }
}

class CustomClassPage extends ConsumerWidget {
  const CustomClassPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Custom Class Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'This page demonstrates how custom classes without toJson() '
            'are displayed in DevTools using their toString() representation.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current User:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('ID: ${user.id}'),
                  Text('Name: ${user.name}'),
                  Text(
                    'Company: ${user.company.name} (${user.company.location})',
                  ),
                  Text('Roles: ${user.roles.map((r) => r.name).join(', ')}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            decoration: const InputDecoration(labelText: 'Update Name'),
            onSubmitted:
                (value) => ref.read(userProvider.notifier).updateName(value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      () => ref
                          .read(userProvider.notifier)
                          .updateCompany('Apple', 'California'),
                  child: const Text('Move to Apple'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      () =>
                          ref.read(userProvider.notifier).addRole(Role.viewer),
                  child: const Text('Add Viewer Role'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
