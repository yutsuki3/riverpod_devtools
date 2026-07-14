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

echo "==> Syncing version to $new_version in 4 files"
sed_inplace "s/^version: .*/version: $new_version/" "$pkg_dir/pubspec.yaml"
sed_inplace "s/^version: .*/version: $new_version/" "$config_file"
sed_inplace "s/^version: .*/version: $new_version/" "$ext_dir/pubspec.yaml"
# The MCP server reports this constant in its initialize handshake.
sed_inplace "s/^const String riverpodDevToolsVersion = .*/const String riverpodDevToolsVersion = '$new_version';/" \
  "$pkg_dir/lib/src/mcp_constants.dart"

echo "==> Building riverpod_devtools_extension (Flutter web, release mode)"
(cd "$ext_dir" && flutter build web --release)

echo "==> Copying build output into ${build_dest#"$root_dir"/}"
rm -rf "$build_dest"
mkdir -p "$build_dest"
cp -r "$ext_dir/build/web/." "$build_dest/"

echo "==> Done. Remaining manual steps:"
echo "  1. Add a $new_version entry to packages/riverpod_devtools/CHANGELOG.md"
echo "  2. Review the diff (especially extension/devtools/build/)"
echo "  3. git add -A && git commit -m \"chore: release $new_version\""
echo "  4. cd packages/riverpod_devtools && flutter pub publish --dry-run"
echo "  5. flutter pub publish"
