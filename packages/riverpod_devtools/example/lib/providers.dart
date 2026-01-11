import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'main.dart' show counterProvider, nameProvider;

// Provider with dependencies
final doubleCounterProvider = Provider<int>((ref) {
  final count = ref.watch(counterProvider);
  return count * 2;
});

// Provider with multiple dependencies
final displayTextProvider = Provider<String>((ref) {
  final count = ref.watch(counterProvider);
  final name = ref.watch(nameProvider);
  return '$name: $count';
});

// Provider using ref.read
final manualCounterProvider = Provider<int>((ref) {
  final count = ref.read(counterProvider);
  return count + 10;
});

// Async provider with dependency
final asyncDataProvider = FutureProvider<String>((ref) async {
  final name = ref.watch(nameProvider);
  await Future.delayed(const Duration(milliseconds: 100));
  return 'Async: $name';
});

// Family provider
final userProvider = Provider.family<String, int>((ref, id) {
  return 'User $id';
});
