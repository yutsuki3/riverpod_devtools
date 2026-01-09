# Stack Trace Feature Implementation Plan

## Ethical Considerations

This feature is inspired by [riverpod_devtools_tracker](https://github.com/weitsai/riverpod_devtools_tracker) by [@weitsai](https://github.com/weitsai), which is licensed under MIT License.

We will:
1. ✅ Implement the concept from scratch, adapted to our architecture
2. ✅ Clearly credit the original inspiration in code comments and documentation
3. ✅ Maintain our own independent implementation optimized for our dependency tracking system
4. ✅ Add acknowledgment in README and CHANGELOG

This approach follows open-source best practices and MIT License requirements.

## Implementation Phases

### Phase 1: Stack Trace Parser (Week 1)

**Files to create:**
- `lib/src/stack_trace_parser.dart`
- `lib/src/stack_trace_config.dart`

**Features:**
- Parse Dart stack traces using regex
- Filter framework code (Flutter, Riverpod)
- Extract file path, line number, function name
- Configurable filtering (package prefixes, ignored patterns)

**Credit header example:**
```dart
// Stack trace parsing for Riverpod DevTools
//
// Concept inspired by riverpod_devtools_tracker by weitsai
// https://github.com/weitsai/riverpod_devtools_tracker (MIT License)
//
// This implementation is independently developed and adapted
// to integrate with our dependency tracking system.
```

### Phase 2: Observer Extension (Week 2)

**Files to modify:**
- `lib/riverpod_devtools.dart` (RiverpodDevToolsObserver)

**Features:**
- Capture stack traces in didAddProvider/didUpdateProvider
- Cache stacks for async provider support (max 100 entries, 60s expiration)
- Add `triggerLocation` and `callChain` to event data

### Phase 3: DevTools UI (Week 3)

**Files to modify:**
- `packages/riverpod_devtools_extension/lib/main.dart`

**Features:**
- Display trigger location in event details
- Show expandable call chain
- Add "Jump to code" button (if possible)

### Phase 4: Documentation (Week 4)

**Files to update:**
- `README.md` - Add Acknowledgments section
- `CHANGELOG.md` - Document new feature with attribution
- `example/` - Add usage examples

## Acknowledgment Text

### README.md
```markdown
## Acknowledgments

The stack trace tracking feature is inspired by
[riverpod_devtools_tracker](https://github.com/weitsai/riverpod_devtools_tracker)
by [@weitsai](https://github.com/weitsai). We've independently implemented
and adapted this concept to integrate seamlessly with our dependency tracking system.

Both projects serve complementary purposes:
- **riverpod_devtools_tracker**: Focused on detailed stack trace analysis
- **riverpod_devtools**: Combines dependency tracking with call origin tracing
```

### CHANGELOG.md
```markdown
## [0.5.0] - 2026-01-XX

### Added
- Stack trace tracking for provider updates, showing where state changes originated
  (inspired by riverpod_devtools_tracker by @weitsai)
- Call chain visualization with file paths and line numbers
- Configurable stack trace filtering
```

## License Compliance

✅ **MIT License Requirements:**
- Include original license text if using code
- Maintain copyright notices
- We're implementing independently, so we'll add attribution in comments and docs

✅ **Our Approach:**
- Independent implementation (not copying code)
- Clear attribution to inspiration source
- Proper credit in documentation
- Maintains community spirit

## Community Engagement

**Actions:**
1. Star weitsai's repository
2. Consider opening an issue to notify about our implementation
3. Cross-reference in documentation
4. Contribute back if we find improvements

## Differences from Original

Our implementation will differ in:
1. **Integration**: Seamlessly works with existing dependency tracking
2. **UI**: Integrated into our three-panel DevTools UI
3. **Optimization**: Shared event system with dependency tracker
4. **Configuration**: Unified config with our existing settings

This ensures we're building a complementary tool, not a duplicate.
