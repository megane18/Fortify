#!/usr/bin/env bash
set -euo pipefail

# Build a portable tarball:
#  - bundles scripts/{fortify.sh,bin/fortify,checks,lib,profiles,gamified_reports.sh}
#  - adds install.sh
#  - writes VERSION.txt into the root of the archive for reference

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REL_DIR="$ROOT_DIR/scripts/release"

# Version resolution
VERSION_FILE="$REL_DIR/VERSION"
if [[ -f "$VERSION_FILE" ]]; then
  VERSION="$(tr -d ' \t\r\n' < "$VERSION_FILE")"
else
  # fallback to latest Git tag (like v0.3.0) or "0.0.0"
  VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"
  VERSION="${VERSION#v}"
fi

APPNAME="fortify"
PKGROOT="$ROOT_DIR/dist"
STAGE="$PKGROOT/${APPNAME}-${VERSION}"

# Clean stage
rm -rf "$STAGE" "$PKGROOT"/*.tar.gz
mkdir -p "$STAGE/scripts/bin"
mkdir -p "$STAGE/scripts/checks"
mkdir -p "$STAGE/scripts/lib"
mkdir -p "$STAGE/scripts/profiles"

# Copy core files
cp -a "$ROOT_DIR/scripts/fortify.sh"            "$STAGE/scripts/fortify.sh"
cp -a "$ROOT_DIR/scripts/bin/fortify"           "$STAGE/scripts/bin/fortify"
cp -a "$ROOT_DIR/scripts/gamified_reports.sh"   "$STAGE/scripts/gamified_reports.sh"

# Copy checks/lib/profiles (these are REQUIRED at runtime)
cp -a "$ROOT_DIR/scripts/checks/"*.sh           "$STAGE/scripts/checks/"  2>/dev/null || true
cp -a "$ROOT_DIR/scripts/lib/"*.sh              "$STAGE/scripts/lib/"     2>/dev/null || true
cp -a "$ROOT_DIR/scripts/profiles/"*.profile    "$STAGE/scripts/profiles/"

# Copy installer
cp -a "$REL_DIR/install.sh"                     "$STAGE/install.sh"

# Optional: include README and LICENSE if present
[[ -f "$ROOT_DIR/README.md" ]]  && cp -a "$ROOT_DIR/README.md"  "$STAGE/README.md"
[[ -f "$ROOT_DIR/LICENSE" ]]    && cp -a "$ROOT_DIR/LICENSE"    "$STAGE/LICENSE"

# Add a version marker inside tarball
echo "$VERSION" > "$STAGE/VERSION.txt"

# Normalize permissions
chmod 755 "$STAGE/install.sh" "$STAGE/scripts/fortify.sh" "$STAGE/scripts/bin/fortify" 2>/dev/null || true
chmod 644 "$STAGE/scripts/checks/"*.sh 2>/dev/null || true
chmod 644 "$STAGE/scripts/lib/"*.sh    2>/dev/null || true
chmod 644 "$STAGE/scripts/profiles/"*.profile
chmod 644 "$STAGE/scripts/gamified_reports.sh"

# Build tar.gz
(
  cd "$PKGROOT"
  tar -czf "${APPNAME}-${VERSION}.tar.gz" "${APPNAME}-${VERSION}"
)

echo "✓ Built: $PKGROOT/${APPNAME}-${VERSION}.tar.gz"
