import 'package:flutter/material.dart';
import 'package:riverpod_devtools_extension/src/utils/color_utils.dart';

/// A widget that displays JSON data in a tree structure with expand/collapse
class JsonTreeView extends StatefulWidget {
  final Map<String, dynamic> data;
  final double indent;
  final bool initiallyExpanded;

  const JsonTreeView({
    super.key,
    required this.data,
    this.indent = 0,
    this.initiallyExpanded = false,
  });

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonTreeViewState extends State<JsonTreeView> {
  final Set<String> _expandedKeys = {};

  /// Number of items to show by default for large collections
  static const int _loadLimit = 50;

  /// Keys that are currently showing more items
  final Set<String> _showingMoreKeys = {};

  /// Keys for strings that are currently expanded (for long strings)
  final Set<String> _expandedStrings = {};

  /// Maximum string length before truncation
  static const int _stringTruncateLength = 150;

  /// Minimum string length to enable truncation
  static const int _stringMinLengthForTruncation = 200;

  @override
  void initState() {
    super.initState();
    // If initiallyExpanded is true, expand all top-level keys
    if (widget.initiallyExpanded) {
      for (final entry in widget.data.entries) {
        if (entry.value is Map || entry.value is List) {
          _expandedKeys.add(entry.key);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter out 'string' from root data if 'items' or 'entries' is present
    // to avoid duplication, similar to how _buildExpandedValue handles nested maps.
    Map<String, dynamic> displayData = widget.data;
    if (widget.data.containsKey('items') ||
        widget.data.containsKey('entries')) {
      if (widget.data.containsKey('string')) {
        displayData = Map<String, dynamic>.from(widget.data)..remove('string');
      }
    }

    final allEntries = displayData.entries.toList();
    final bool isLarge = allEntries.length > _loadLimit;
    final bool showingMore = _showingMoreKeys.contains('__root__');

    final entries = (isLarge && !showingMore)
        ? allEntries.take(_loadLimit).toList()
        : allEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...entries.map((entry) {
          final key = entry.key;
          final dynamic rawValue = entry.value;

          // Check if the value is a \"wrapped\" metadata Map
          final bool isWrapped = rawValue is Map<String, dynamic> &&
              (rawValue.containsKey('type') ||
                  rawValue.containsKey('value') ||
                  rawValue.containsKey('entity') ||
                  rawValue.containsKey('items') ||
                  rawValue.containsKey('entries') ||
                  rawValue.containsKey('string'));

          dynamic displayValue = rawValue;
          String? displayType;
          String? asyncState;

          if (isWrapped) {
            final map = rawValue;
            displayType = map['type'] as String?;
            asyncState = map['asyncState'] as String?;

            if (map.containsKey('value')) {
              displayValue = map['value'];
            } else if (map.containsKey('entity')) {
              displayValue = map['entity'];
            } else if (map.containsKey('items')) {
              displayValue = map['items'];
            } else if (map.containsKey('entries')) {
              // Convert entries list back to a Map for tree view
              final entries = map['entries'] as List;
              final newMap = <String, dynamic>{};
              for (final e in entries) {
                if (e is Map) {
                  newMap[e['key'].toString()] = e['value'];
                }
              }
              displayValue = newMap;
            } else if (map.containsKey('string')) {
              displayValue = map['string'];
            }
          }

          final isExpanded = _expandedKeys.contains(key);
          final isExpandable = displayValue is Map || displayValue is List;

          return Padding(
            padding: EdgeInsets.only(left: widget.indent * 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: isExpandable
                      ? () {
                          setState(() {
                            if (isExpanded) {
                              _expandedKeys.remove(key);
                            } else {
                              _expandedKeys.add(key);
                            }
                          });
                        }
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isExpandable)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: Icon(
                            isExpanded
                                ? Icons.arrow_drop_down
                                : Icons.arrow_right,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        const SizedBox(width: 14),
                      const SizedBox(width: 2),
                      Expanded(
                        child: _buildValueDisplay(
                          key: key,
                          displayValue: displayValue,
                          displayType: displayType,
                          asyncState: asyncState,
                          isExpandable: isExpandable,
                          isExpanded: isExpanded,
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isExpandable && isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0, top: 2),
                    child: _buildExpandedValue(displayValue, key),
                  ),
              ],
            ),
          );
        }),
        if (isLarge && !showingMore)
          Padding(
            padding: EdgeInsets.only(left: (widget.indent * 8.0) + 16),
            child: TextButton(
              onPressed: () => setState(() => _showingMoreKeys.add('__root__')),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Show ${allEntries.length - _loadLimit} more items...',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExpandedValue(dynamic value, String parentKey) {
    if (value is Map) {
      final map = value as Map<String, dynamic>;
      final bool isWrapped = map.containsKey('type') ||
          map.containsKey('value') ||
          map.containsKey('entity') ||
          map.containsKey('items') ||
          map.containsKey('entries') ||
          map.containsKey('string');

      dynamic unwrappedValue = map; // Start with the original map

      if (isWrapped) {
        if (map.containsKey('value')) {
          unwrappedValue = map['value'];
        } else if (map.containsKey('entity')) {
          unwrappedValue = map['entity'];
        } else if (map.containsKey('items')) {
          unwrappedValue = map['items'];
        } else if (map.containsKey('entries')) {
          final entries = map['entries'] as List;
          final newMap = <String, dynamic>{};
          for (final e in entries) {
            if (e is Map) {
              newMap[e['key'].toString()] = e['value'];
            }
          }
          unwrappedValue = newMap;
        } else if (map.containsKey('string')) {
          unwrappedValue = map['string'];
        }
      }

      // If after unwrapping, it's still a Map, then display it as a tree.
      // Otherwise, it's a primitive or list that should have been handled by the parent.
      if (unwrappedValue is Map) {
        // Filter out metadata keys if the unwrapped value is still a wrapped object
        // (e.g., if the 'value' key itself contained a wrapped object)
        final unwrappedMap = unwrappedValue as Map<String, dynamic>;
        final bool isUnwrappedValueStillWrapped =
            unwrappedMap.containsKey('type') ||
                unwrappedMap.containsKey('string') ||
                unwrappedMap.containsKey('value') ||
                unwrappedMap.containsKey('entity') ||
                unwrappedMap.containsKey('items') ||
                unwrappedMap.containsKey('entries');

        Map<String, dynamic> displayMap;

        if (isUnwrappedValueStillWrapped) {
          displayMap = Map<String, dynamic>.from(unwrappedMap);
          displayMap.remove('type');
          displayMap.remove('string');
          displayMap.remove('asyncState');
          // If there's no actual data left, return empty
          if (displayMap.isEmpty) {
            return const SizedBox.shrink();
          }
        } else {
          displayMap = Map<String, dynamic>.from(unwrappedMap);
        }

        return JsonTreeView(
          data: displayMap,
          indent: widget.indent + 1,
        );
      } else if (unwrappedValue is List) {
        // If unwrapped value is a list, display it as a list
        return _buildListView(unwrappedValue, parentKey);
      }
      // If unwrappedValue is a primitive, it shouldn't be expanded further here.
      return const SizedBox.shrink();
    } else if (value is List) {
      return _buildListView(value, parentKey);
    }
    return const SizedBox.shrink();
  }

  Widget _buildListView(List list, String parentKey) {
    final theme = Theme.of(context);
    final bool isLarge = list.length > _loadLimit;
    final bool showingMore = _showingMoreKeys.contains(parentKey);

    final displayList =
        (isLarge && !showingMore) ? list.take(_loadLimit).toList() : list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(displayList.length, (index) {
          final dynamic rawItem = displayList[index];

          // Check if the item is a \"wrapped\" metadata Map
          final bool isWrapped = rawItem is Map<String, dynamic> &&
              (rawItem.containsKey('type') ||
                  rawItem.containsKey('value') ||
                  rawItem.containsKey('entity') ||
                  rawItem.containsKey('items') ||
                  rawItem.containsKey('entries') ||
                  rawItem.containsKey('string'));

          dynamic displayItem = rawItem;
          String? displayType;

          if (isWrapped) {
            final map = rawItem;
            displayType = map['type'] as String?;
            if (map.containsKey('value')) {
              displayItem = map['value'];
            } else if (map.containsKey('entity')) {
              displayItem = map['entity'];
            } else if (map.containsKey('items')) {
              displayItem = map['items'];
            } else if (map.containsKey('entries')) {
              // Convert entries list back to a Map for tree view
              final entries = map['entries'] as List;
              final newMap = <String, dynamic>{};
              for (final e in entries) {
                if (e is Map) {
                  newMap[e['key'].toString()] = e['value'];
                }
              }
              displayItem = newMap;
            } else if (map.containsKey('string')) {
              displayItem = map['string'];
            }
          }

          final isExpandable = displayItem is Map || displayItem is List;
          final itemKey = '$parentKey[$index]';
          final isExpanded = _expandedKeys.contains(itemKey);

          return Padding(
            padding: EdgeInsets.only(left: (widget.indent + 1) * 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: isExpandable
                      ? () {
                          setState(() {
                            if (isExpanded) {
                              _expandedKeys.remove(itemKey);
                            } else {
                              _expandedKeys.add(itemKey);
                            }
                          });
                        }
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isExpandable)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: Icon(
                            isExpanded
                                ? Icons.arrow_drop_down
                                : Icons.arrow_right,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        const SizedBox(width: 14),
                      const SizedBox(width: 2),
                      Expanded(
                        child: _buildListItemDisplay(
                          index: index,
                          itemKey: itemKey,
                          displayItem: displayItem,
                          displayType: displayType,
                          isExpandable: isExpandable,
                          isExpanded: isExpanded,
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isExpandable && isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildExpandedValue(displayItem, itemKey),
                  ),
              ],
            ),
          );
        }),
        if (isLarge && !showingMore)
          Padding(
            padding: EdgeInsets.only(left: ((widget.indent + 1) * 8.0) + 16),
            child: TextButton(
              onPressed: () => setState(() => _showingMoreKeys.add(parentKey)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Show ${list.length - _loadLimit} more items...',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }

  /// Builds the list item display widget with support for long string truncation
  Widget _buildListItemDisplay({
    required int index,
    required String itemKey,
    required dynamic displayItem,
    required String? displayType,
    required bool isExpandable,
    required bool isExpanded,
    required ThemeData theme,
  }) {
    // Check if this is a long string that needs truncation
    final isLongString = displayItem is String &&
        displayItem.length >= _stringMinLengthForTruncation;
    final stringKey = '${widget.indent}_$itemKey';
    final isStringExpanded = _expandedStrings.contains(stringKey);

    if (isLongString && !isExpandable) {
      // Long string handling for list items
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: '[$index]: ',
                  style: TextStyle(
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
                TextSpan(
                  text: isStringExpanded
                      ? '"$displayItem"'
                      : '"${displayItem.substring(0, _stringTruncateLength)}..."',
                  style: TextStyle(
                    color: getValueColor(displayItem, theme),
                  ),
                ),
                if (displayType != null &&
                    displayType != 'null' &&
                    displayType != 'String' &&
                    displayType != 'int' &&
                    displayType != 'double' &&
                    displayType != 'bool')
                  TextSpan(
                    text: ' ($displayType)',
                    style: TextStyle(
                      fontSize: 8,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () {
              setState(() {
                if (isStringExpanded) {
                  _expandedStrings.remove(stringKey);
                } else {
                  _expandedStrings.add(stringKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                isStringExpanded
                    ? 'Show less'
                    : 'Show more (${displayItem.length} chars)',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Normal list item display
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurface,
          height: 1.4,
        ),
        children: [
          TextSpan(
            text: '[$index]: ',
            style: TextStyle(
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
          if (!isExpandable || !isExpanded)
            TextSpan(
              text: _formatValue(displayItem),
              style: TextStyle(
                color: getValueColor(displayItem, theme),
              ),
            ),
          if (displayType != null &&
              displayType != 'null' &&
              displayType != 'String' &&
              displayType != 'int' &&
              displayType != 'double' &&
              displayType != 'bool')
            TextSpan(
              text: ' ($displayType)',
              style: TextStyle(
                fontSize: 8,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the value display widget with support for long string truncation
  Widget _buildValueDisplay({
    required String key,
    required dynamic displayValue,
    required String? displayType,
    required String? asyncState,
    required bool isExpandable,
    required bool isExpanded,
    required ThemeData theme,
  }) {
    // Check if this is a long string that needs truncation
    final isLongString = displayValue is String &&
        displayValue.length >= _stringMinLengthForTruncation;
    final stringKey = '${widget.indent}_$key';
    final isStringExpanded = _expandedStrings.contains(stringKey);

    if (isLongString && !isExpandable) {
      // Long string handling
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: '$key: ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (asyncState != null)
                  TextSpan(
                    text: '[$asyncState] ',
                    style: TextStyle(
                      color: asyncState == 'data'
                          ? const Color(0xFF4CAF50)
                          : asyncState == 'loading'
                              ? Colors.grey
                              : const Color(0xFFE57373),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                TextSpan(
                  text: isStringExpanded
                      ? '"$displayValue"'
                      : '"${displayValue.substring(0, _stringTruncateLength)}..."',
                  style: TextStyle(
                    color: getValueColor(displayValue, theme),
                  ),
                ),
                if (displayType != null &&
                    displayType != 'null' &&
                    displayType != 'String' &&
                    displayType != 'int' &&
                    displayType != 'double' &&
                    displayType != 'bool')
                  TextSpan(
                    text: ' ($displayType)',
                    style: TextStyle(
                      fontSize: 8,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: () {
              setState(() {
                if (isStringExpanded) {
                  _expandedStrings.remove(stringKey);
                } else {
                  _expandedStrings.add(stringKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                isStringExpanded
                    ? 'Show less'
                    : 'Show more (${displayValue.length} chars)',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Normal value display
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurface,
          height: 1.4,
        ),
        children: [
          TextSpan(
            text: '$key: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          if (asyncState != null)
            TextSpan(
              text: '[$asyncState] ',
              style: TextStyle(
                color: asyncState == 'data'
                    ? const Color(0xFF4CAF50)
                    : asyncState == 'loading'
                        ? Colors.grey
                        : const Color(0xFFE57373),
                fontWeight: FontWeight.bold,
              ),
            ),
          if (!isExpandable || !isExpanded)
            TextSpan(
              text: _formatValue(displayValue),
              style: TextStyle(
                color: getValueColor(displayValue, theme),
              ),
            ),
          if (displayType != null &&
              displayType != 'null' &&
              displayType != 'String' &&
              displayType != 'int' &&
              displayType != 'double' &&
              displayType != 'bool')
            TextSpan(
              text: ' ($displayType)',
              style: TextStyle(
                fontSize: 8,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';

    // If it's a wrapped metadata map, try to get the original string or a summary
    if (value is Map<String, dynamic>) {
      if (value.containsKey('string')) {
        return value['string'] as String;
      }
      if (value.containsKey('value')) {
        final val = value['value'];
        if (val is Map) return '{${val.length} fields}';
        return _formatValue(val);
      }
      if (value.containsKey('entity')) {
        final val = value['entity'];
        if (val is Map) return '{${val.length} fields}';
        return _formatValue(val);
      }
      return '{${value.length} keys}';
    }

    if (value is String) return '"$value"';
    if (value is num || value is bool) return value.toString();
    if (value is List) return '[${value.length} items]';
    if (value is Map) return '{${value.length} keys}';
    return value.toString();
  }
}
