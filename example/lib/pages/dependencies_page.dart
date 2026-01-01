import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Base provider - no dependencies
final authTokenProvider = NotifierProvider<AuthTokenNotifier, String?>(
  AuthTokenNotifier.new,
  name: 'authTokenProvider',
);

class AuthTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void login(String token) => state = token;
  void logout() => state = null;
}

// Depends on authTokenProvider
final userIdProvider = Provider<String?>(
  (ref) {
    final token = ref.watch(authTokenProvider);
    return token != null ? 'user_123' : null;
  },
  name: 'userIdProvider',
);

// Depends on userIdProvider
final userNameProvider = Provider<String?>(
  (ref) {
    final userId = ref.watch(userIdProvider);
    return userId != null ? 'John Doe' : null;
  },
  name: 'userNameProvider',
);

// Depends on userIdProvider
final userEmailProvider = Provider<String?>(
  (ref) {
    final userId = ref.watch(userIdProvider);
    return userId != null ? 'john@example.com' : null;
  },
  name: 'userEmailProvider',
);

// Depends on userName and userEmail
final userProfileProvider = Provider<Map<String, String?>>(
  (ref) {
    final name = ref.watch(userNameProvider);
    final email = ref.watch(userEmailProvider);
    return {
      'name': name,
      'email': email,
    };
  },
  name: 'userProfileProvider',
);

// Counter provider - independent
final counterProvider = NotifierProvider<CounterNotifier, int>(
  CounterNotifier.new,
  name: 'counterProvider',
);

class CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
  void decrement() => state--;
}

// Depends on counter
final doubleCounterProvider = Provider<int>(
  (ref) {
    final count = ref.watch(counterProvider);
    return count * 2;
  },
  name: 'doubleCounterProvider',
);

// Depends on doubleCounter
final tripleCounterProvider = Provider<int>(
  (ref) {
    final doubleCount = ref.watch(doubleCounterProvider);
    return doubleCount + ref.watch(counterProvider);
  },
  name: 'tripleCounterProvider',
);

class DependenciesPage extends ConsumerWidget {
  const DependenciesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authToken = ref.watch(authTokenProvider);
    final userId = ref.watch(userIdProvider);
    final userName = ref.watch(userNameProvider);
    final userEmail = ref.watch(userEmailProvider);
    final userProfile = ref.watch(userProfileProvider);
    final counter = ref.watch(counterProvider);
    final doubleCounter = ref.watch(doubleCounterProvider);
    final tripleCounter = ref.watch(tripleCounterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dependencies Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Authentication Chain',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'authToken → userId → userName/userEmail → userProfile',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              _buildCard(
                'Auth Token',
                authToken ?? 'Not authenticated',
                ElevatedButton(
                  onPressed: () {
                    if (authToken == null) {
                      ref.read(authTokenProvider.notifier).login('token_abc123');
                    } else {
                      ref.read(authTokenProvider.notifier).logout();
                    }
                  },
                  child: Text(authToken == null ? 'Login' : 'Logout'),
                ),
              ),
              const SizedBox(height: 8),
              _buildCard('User ID', userId ?? 'No user', null),
              const SizedBox(height: 8),
              _buildCard('User Name', userName ?? 'No name', null),
              const SizedBox(height: 8),
              _buildCard('User Email', userEmail ?? 'No email', null),
              const SizedBox(height: 8),
              _buildCard(
                'User Profile',
                'Name: ${userProfile['name']}, Email: ${userProfile['email']}',
                null,
              ),
              const SizedBox(height: 32),
              const Text(
                'Counter Chain',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'counter → doubleCounter → tripleCounter',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              _buildCard(
                'Counter',
                counter.toString(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        ref.read(counterProvider.notifier).decrement();
                      },
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: () {
                        ref.read(counterProvider.notifier).increment();
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildCard('Double Counter', doubleCounter.toString(), null),
              const SizedBox(height: 8),
              _buildCard('Triple Counter', tripleCounter.toString(), null),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to Test:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Open DevTools and select a provider',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      '2. Check "Depends On" to see which providers it watches',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      '3. Check "Used By" to see which providers watch it',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      '4. Click on any provider name to navigate to it',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(String label, String value, Widget? action) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (action != null) action,
          ],
        ),
      ),
    );
  }
}
