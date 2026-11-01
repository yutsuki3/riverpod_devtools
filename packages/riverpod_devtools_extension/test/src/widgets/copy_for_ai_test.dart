import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';
import 'package:riverpod_devtools_extension/src/widgets/detail_panel/detail_panel.dart';

void main() {
  testWidgets('Copy for AI puts the selected provider brief on the clipboard',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final notifier = InspectorNotifier();
    addTearDown(notifier.dispose);
    notifier.debugSeed(
      providers: {
        'counterProvider': ProviderInfo(
          id: '1',
          name: 'counterProvider',
          value: const {'type': 'int', 'value': 42},
          status: ProviderStatus.active,
        ),
      },
      events: const [],
    );
    notifier.selectOnly('counterProvider');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 420, child: DetailPanel(notifier: notifier)),
      ),
    ));

    await tester.tap(find.text('Copy for AI'));
    await tester.pump();

    expect(copied, contains('## Riverpod provider: counterProvider'));
    expect(copied, contains('42'));
    expect(find.text('Copied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // revert label timer
    expect(find.text('Copy for AI'), findsOneWidget);
  });
}
