#!/usr/bin/env bash
# Pack each package as <name>-<version>.tar.gz with framework.toml at the
# archive root, and write dist/pins.toml with the homonto digest of each.
# Usage: scripts/pack.sh [out-dir]   (default: dist)
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-dist}"
mkdir -p "$out"
: > "$out/pins.toml"
for pkg in ticket-engine ticket-workflow ticket-service; do
  version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$pkg/framework.toml" | head -1)"
  archive="$out/$pkg-$version.tar.gz"
  tar -C "$pkg" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf - . | gzip -n > "$archive"
  printf '%s = "%s"  # %s\n' "$pkg" "$(python3 -I scripts/digest.py "$pkg")" "$(basename "$archive")" >> "$out/pins.toml"
done
cat "$out/pins.toml"
