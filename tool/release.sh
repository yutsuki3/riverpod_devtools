#!/usr/bin/env bash
set -euo pipefail

# Syncs the version across riverpod_devtools, its DevTools extension config,
# and the riverpod_devtools_extension source package, then builds the
# extension web app and copies the output into the published package.
#
# This does NOT commit, tag, or publish anything — those steps are left
# manual since they need a human-written CHANGELOG entry and a final review.
#
# Usage: tool/release.sh <new-version>
# Example: tool/release.sh 0.6.0

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <new-version>" >&2
  echo "Example: $0 0.6.0" >&2
  exit 1
fi

new_version="$1"

if [[ ! "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in X.Y.Z format (got: $new_version)" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg_dir="$root_dir/packages/riverpod_devtools"
ext_dir="$root_dir/packages/riverpod_devtools_extension"
config_file="$pkg_dir/extension/devtools/config.yaml"
build_dest="$pkg_dir/extension/devtools/build"

sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

echo "==> Syncing version to $new_version in 5 files"
sed_inplace "s/^version: .*/version: $new_version/" "$pkg_dir/pubspec.yaml"
sed_inplace "s/^version: .*/version: $new_version/" "$config_file"
sed_inplace "s/^version: .*/version: $new_version/" "$ext_dir/pubspec.yaml"
# The MCP server reports this constant in its initialize handshake.
sed_inplace "s/^const String riverpodDevToolsVersion = .*/const String riverpodDevToolsVersion = '$new_version';/" \
  "$pkg_dir/lib/src/mcp_constants.dart"
# The install snippet shown on pub.dev (package README).
sed_inplace "s/riverpod_devtools: \^[0-9][0-9.]*/riverpod_devtools: ^$new_version/" \
  "$pkg_dir/README.md"

# Guard against forgotten spots: any other X.Y.Z-looking package-version
# reference should be either synced above or on the manual checklist below.
# (The "version" fields inside riverpod_dependencies.json / analyzer.dart are
# the dependency-JSON FORMAT version, not the package version — never bump
# those here.)

echo "==> Building riverpod_devtools_extension (Flutter web, release mode)"
(cd "$ext_dir" && flutter build web --release)

echo "==> Copying build output into ${build_dest#"$root_dir"/}"
rm -rf "$build_dest"
mkdir -p "$build_dest"
cp -r "$ext_dir/build/web/." "$build_dest/"

echo "==> Done. Remaining manual steps (full checklist in CLAUDE.md > Releasing):"
echo "  1. Add a $new_version entry to packages/riverpod_devtools/CHANGELOG.md"
echo "     (fold any 'Unreleased' section into it)"
echo "  2. Root README.md: add a ${new_version%.*}.x row to the Version"
echo "     Compatibility table if the Flutter/riverpod constraints changed"
echo "  3. Review the diff (especially extension/devtools/build/)"
echo "  4. Verify: flutter analyze && flutter test in BOTH packages"
echo "     (extension tests need: flutter test --platform chrome)"
echo "  5. git add -A && git commit -m \"chore: release $new_version\""
echo "  6. cd packages/riverpod_devtools && flutter pub publish --dry-run"
echo "  7. flutter pub publish"
echo "  8. git tag v$new_version && git push origin v$new_version"
