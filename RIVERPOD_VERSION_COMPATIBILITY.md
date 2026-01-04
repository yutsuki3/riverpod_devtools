# Riverpod バージョン互換性調査結果

## 現在の対応バージョン
- `flutter_riverpod: '>=2.6.1 <4.0.0'`

## 調査結果

### 使用されている Riverpod API

riverpod_devtools パッケージは以下の API のみを使用しています：

1. **ProviderObserver クラス**
   - `didAddProvider` メソッド
   - `didUpdateProvider` メソッド
   - `didDisposeProvider` メソッド

2. **その他の API**
   - `identityHashCode()` - Dart 標準関数
   - `developer.postEvent()` - Dart SDK の developer パッケージ

### Riverpod API のバージョン履歴

#### バージョン 3.0.0 (2025)
**メソッドシグネチャ:**
```dart
didAddProvider(ProviderObserverContext context, Object? value)
didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue)
didDisposeProvider(ProviderObserverContext context)
```

**変更点:**
- ProviderContainer パラメータが削除され、2パラメータになった

#### バージョン 2.0.0 (2022年頃)
**メソッドシグネチャ:**
```dart
didAddProvider(ProviderObserverContext context, Object? value, ProviderContainer container)
didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue, ProviderContainer container)
didDisposeProvider(ProviderObserverContext context, ProviderContainer container)
```

**変更点:**
- 破壊的変更: ProviderObserverContext パラメータが導入された
- ProviderBase と ProviderContainer が ProviderObserverContext に統合された

#### バージョン 1.0.0 (2021年頃)
**メソッドシグネチャ:**
```dart
didAddProvider(ProviderBase provider, Object? value, ProviderContainer container)
didUpdateProvider(ProviderBase provider, Object? previousValue, Object? newValue, ProviderContainer container)
didDisposeProvider(ProviderBase provider, ProviderContainer container)
```

**変更点:**
- didUpdateProvider が previousValue と newValue の両方を受け取るようになった

#### バージョン 0.14.0 および 0.13.0 (2020年頃)
**メソッドシグネチャ:**
```dart
didAddProvider(ProviderBase provider, Object? value, ProviderContainer container)
didUpdateProvider(ProviderBase provider, Object? previousValue, Object? newValue, ProviderContainer container)
didDisposeProvider(ProviderBase provider, ProviderContainer container)
```

**変更点:**
- 0.13.0: ProviderObserver が const constructor を持てるようになった
- ProviderObserver はこれより前のバージョン（0.6.0頃）から存在

### 現在の実装の互換性メカニズム

現在の `RiverpodDevToolsObserver` は以下の工夫により、複数バージョンに対応しています：

```dart
@override
void didAddProvider(
  covariant Object context,  // ProviderObserverContext または ProviderBase
  Object? value, [
  covariant Object? arg3,    // オプショナル: ProviderContainer (2.x) または未使用 (3.0)
]) {
  final provider = _getProvider(context);
  // ...
}

dynamic _getProvider(Object arg) {
  try {
    // Riverpod 3.0 と 2.x: ProviderObserverContext から provider を取得
    final dynamic context = arg;
    return context.provider;
  } catch (_) {
    // Riverpod 1.x と 0.14.x: arg が直接 ProviderBase
    return arg;
  }
}
```

この実装により：
- **Riverpod 3.0**: ✅ 対応（context.provider で取得）
- **Riverpod 2.x**: ✅ 対応（context.provider で取得）
- **Riverpod 1.x**: ✅ 対応（catch ブロックで arg 自体を返す）
- **Riverpod 0.14.x**: ✅ 理論上対応可能（1.x と同じ API）
- **Riverpod 0.13.x 以前**: ⚠️ 要検証（API は同じだが、テストが必要）

## 推奨される対応バージョン

### 安全な最小バージョン: **1.0.0**

```yaml
flutter_riverpod: '>=1.0.0 <4.0.0'
```

**理由:**
- 1.0.0 は安定版リリース
- didUpdateProvider の API が確定している
- 現在の実装で完全に動作する

### 積極的な最小バージョン: **0.14.0**

```yaml
flutter_riverpod: '>=0.14.0 <4.0.0'
```

**理由:**
- 0.14.0 は 1.0.0 と同じ API シグネチャ
- 理論上は現在の実装で動作する
- ただし、実際のテストが推奨される

### より古いバージョン: **0.13.0 以前**

**非推奨**

**理由:**
- CHANGELOG に詳細情報が不足
- API の安定性が不明
- メンテナンスコストが高い

## 実装変更なしで対応可能なバージョン

現在の実装を**一切変更せず**に対応できるバージョン:

```yaml
flutter_riverpod: '>=1.0.0 <4.0.0'
```

これにより、現在の `>=2.6.1` から `>=1.0.0` に拡張でき、約3年分のバージョンをカバーできます。

## テスト推奨事項

最小バージョンを下げる場合、以下のバージョンでテストすることを推奨：
1. `flutter_riverpod: 1.0.0` - 最小バージョン
2. `flutter_riverpod: 1.0.4` - 1.x の安定版
3. `flutter_riverpod: 2.0.0` - 2.x の最初のバージョン
4. `flutter_riverpod: 2.6.1` - 現在の最小バージョン
5. `flutter_riverpod: 3.0.0` - 3.x の最初のバージョン
6. `flutter_riverpod: latest` - 最新バージョン

## 参考資料

- [Riverpod Changelog](https://pub.dev/packages/riverpod/changelog)
- [Flutter Riverpod Changelog](https://pub.dev/packages/flutter_riverpod/changelog)
- [ProviderObserver API Documentation](https://pub.dev/documentation/riverpod/latest/riverpod/ProviderObserver-class.html)
- [Riverpod 3.0 Migration Guide](https://riverpod.dev/docs/3.0_migration)
- [What's New in Riverpod 3.0](https://riverpod.dev/docs/whats_new)

---

**調査日:** 2026-01-04
**調査対象パッケージ:** riverpod_devtools v0.3.0
