import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../common/copy_button.dart';

/// Collapsible dropdown widget for static analysis setup instructions
class StaticAnalysisRequiredDropdown extends StatefulWidget {
  final ThemeData theme;
  final Widget Function({
    required ThemeData theme,
    required String number,
    required String title,
    required String description,
    required String code,
  }) buildSetupStep;

  const StaticAnalysisRequiredDropdown({
    super.key,
    required this.theme,
    required this.buildSetupStep,
  });

  @override
  State<StaticAnalysisRequiredDropdown> createState() =>
      _StaticAnalysisRequiredDropdownState();
}

class _StaticAnalysisRequiredDropdownState
    extends State<StaticAnalysisRequiredDropdown> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _isExpanded
            ? widget.theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: _isExpanded
            ? Border.all(
                color: widget.theme.colorScheme.outline.withValues(alpha: 0.15),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with warning icon and title
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 9,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Static Analysis Required',
                      style: TextStyle(
                        fontSize: 7.5,
                        color: widget.theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 12,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_isExpanded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        widget.theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To view provider dependencies, run the analyzer and configure your app:',
                    style: TextStyle(
                      fontSize: 8,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  widget.buildSetupStep(
                    theme: widget.theme,
                    number: '1',
                    title: 'Run the analyzer to detect dependencies',
                    description:
                        'Analyzes your code to find all ref.watch/read calls',
                    code: 'dart run riverpod_devtools:analyze',
                  ),
                  const SizedBox(height: 6),
                  widget.buildSetupStep(
                    theme: widget.theme,
                    number: '2',
                    title: 'Register the generated JSON as an asset',
                    description:
                        'Makes the dependency data available to your app',
                    code:
                        'flutter:\n  assets:\n    - lib/riverpod_dependencies.json',
                  ),
                  const SizedBox(height: 6),
                  // Step 3 with highlighted code
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '3. ',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: widget.theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Load dependency data in main()',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: widget
                                        .theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Add this code before runApp() to load the JSON file',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: widget
                                        .theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        margin: const EdgeInsets.only(left: 14),
                        decoration: BoxDecoration(
                          color: widget
                              .theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: widget.theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontFamily: 'monospace',
                                    color: widget
                                        .theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                    height: 1.4,
                                  ),
                                  children: [
                                    const TextSpan(
                                        text: 'void main() async {\n'),
                                    const TextSpan(
                                        text:
                                            '  WidgetsFlutterBinding.ensureInitialized();\n\n'),
                                    const TextSpan(
                                        text:
                                            '  // Load static dependencies\n'),
                                    const TextSpan(text: '  try {\n'),
                                    const TextSpan(text: '    final json = '),
                                    TextSpan(
                                      text: 'await rootBundle.loadString',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: '(\n'),
                                    TextSpan(
                                      text:
                                          '      \'lib/riverpod_dependencies.json\'',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ',\n'),
                                    const TextSpan(text: '    );\n'),
                                    TextSpan(
                                      text:
                                          '    RiverpodDevToolsRegistry.instance\n        .loadFromJson(json)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ';\n'),
                                    const TextSpan(text: '  } catch (_) {\n'),
                                    const TextSpan(
                                        text:
                                            '    // DevTools shows setup instructions\n'),
                                    const TextSpan(text: '  }\n\n'),
                                    const TextSpan(
                                        text: '  runApp(ProviderScope(\n'),
                                    TextSpan(
                                      text:
                                          '    observers: [RiverpodDevToolsObserver()]',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ',\n'),
                                    const TextSpan(
                                        text: '    child: MyApp(),\n'),
                                    const TextSpan(text: '  ));\n'),
                                    const TextSpan(text: '}'),
                                  ],
                                ),
                              ),
                            ),
                            const CopyButton(
                              textToCopy:
                                  'void main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n\n  // Load static dependencies\n  try {\n    final json = await rootBundle.loadString(\n      \'lib/riverpod_dependencies.json\',\n    );\n    RiverpodDevToolsRegistry.instance\n        .loadFromJson(json);\n  } catch (_) {\n    // DevTools shows setup instructions\n  }\n\n  runApp(ProviderScope(\n    observers: [RiverpodDevToolsObserver()],\n    child: MyApp(),\n  ));\n}',
                              size: 12,
                              tooltipMessage: 'Copy code',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '4. ',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: widget.theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Restart your app after completing these steps.',
                          style: TextStyle(
                            fontSize: 8,
                            color: widget.theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Link to pub.dev documentation
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse(
                          'https://pub.dev/packages/riverpod_devtools#getting-started');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 10,
                            color: widget.theme.colorScheme.primary
                                .withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'See full documentation on pub.dev',
                            style: TextStyle(
                              fontSize: 8,
                              color: widget.theme.colorScheme.primary
                                  .withValues(alpha: 0.7),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
