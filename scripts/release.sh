#!/bin/bash
#
#  release.sh
#  SwiftCheck
#
#  Created by Mihran on 21.11.26.
#
#  Builds the release assets for one version (Apple Silicon only):
#    dist/swiftcheck-<version>-macos-arm64.zip     the CLI, for manual installs and CI
#    dist/SwiftCheckBinary.artifactbundle.zip      the CLI as an SPM binary target, used by SwiftCheckPlugins
#  and prints their checksums. With --plugins <dir>, it also writes <dir>/Package.swift for that version.
#
#  Usage: scripts/release.sh <version> [--plugins <path to SwiftCheckPlugins>] [--allow-dirty]

set -euo pipefail

version="${1:-}"
shift || true
plugins_dir=""
allow_dirty=0
while [ $# -gt 0 ]; do
    case "$1" in
        --plugins) plugins_dir="$2"; shift 2 ;;
        --allow-dirty) allow_dirty=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$version" ]; then
    echo "Usage: scripts/release.sh <version> [--plugins <dir>] [--allow-dirty]" >&2
    exit 2
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

source_version="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/SwiftCheckCore/SwiftCheck.swift)"
if [ "$source_version" != "$version" ]; then
    echo "SwiftCheck.version is $source_version, not $version. Update Sources/SwiftCheckCore/SwiftCheck.swift first." >&2
    exit 1
fi
if [ "$allow_dirty" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
    echo "The working tree has uncommitted changes. Commit them (or pass --allow-dirty for a trial build)." >&2
    exit 1
fi

echo "Testing…"
swift test 2>&1 | tail -1

echo "Building swiftcheck $version for arm64…"
swift build -c release --arch arm64 --product swiftcheck >/dev/null
binary="$(swift build -c release --arch arm64 --show-bin-path)/swiftcheck"
[ "$("$binary" --version)" = "$version" ] || { echo "Built binary reports a different version" >&2; exit 1; }

dist="$root/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
rm -rf "$dist"
mkdir -p "$dist"

# Plain CLI archive.
mkdir -p "$stage/cli"
cp "$binary" "$stage/cli/swiftcheck"
strip -rSTx "$stage/cli/swiftcheck"
codesign --force --sign - "$stage/cli/swiftcheck" 2>/dev/null
cli_zip="$dist/swiftcheck-$version-macos-arm64.zip"
(cd "$stage/cli" && ditto -c -k --keepParent swiftcheck "$cli_zip")

# Artifact bundle for the SPM binary target.
bundle="$stage/SwiftCheckBinary.artifactbundle"
mkdir -p "$bundle/swiftcheck-$version-macos/bin"
cp "$stage/cli/swiftcheck" "$bundle/swiftcheck-$version-macos/bin/swiftcheck"
cat > "$bundle/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "swiftcheck": {
      "version": "$version",
      "type": "executable",
      "variants": [
        {
          "path": "swiftcheck-$version-macos/bin/swiftcheck",
          "supportedTriples": ["arm64-apple-macosx"]
        }
      ]
    }
  }
}
JSON
bundle_zip="$dist/SwiftCheckBinary.artifactbundle.zip"
(cd "$stage" && ditto -c -k --keepParent SwiftCheckBinary.artifactbundle "$bundle_zip")

bundle_checksum="$(swift package compute-checksum "$bundle_zip")"
cli_sha="$(shasum -a 256 "$cli_zip" | cut -d' ' -f1)"
echo "$cli_sha  $(basename "$cli_zip")" > "$cli_zip.sha256"
echo "$bundle_checksum  $(basename "$bundle_zip")" > "$bundle_zip.sha256"

if [ -n "$plugins_dir" ]; then
    template="$plugins_dir/Package.swift.template"
    [ -f "$template" ] || { echo "No $template" >&2; exit 1; }
    sed -e "s/{{VERSION}}/$version/g" -e "s/{{CHECKSUM}}/$bundle_checksum/g" "$template" > "$plugins_dir/Package.swift"
    echo "Wrote $plugins_dir/Package.swift for $version"
fi

cat <<INFO

Release $version
  $(basename "$cli_zip")                sha256 $cli_sha
  $(basename "$bundle_zip")     checksum $bundle_checksum

Next:
  1. Tag and push SwiftCheck:            git tag $version && git push origin main $version
  2. Create the GitHub release $version and upload both zips (and the .sha256 files) from dist/.
  3. Commit SwiftCheckPlugins/Package.swift, tag it $version and push.
INFO
