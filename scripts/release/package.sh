#!/usr/bin/env bash
set -euo pipefail

# where we are
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
DIST="$ROOT/dist"
NAME="fortify-${VERSION}"

rm -rf "$DIST"
mkdir -p "$DIST/$NAME"

# copy payload
cp -R "$ROOT/scripts" "$DIST/$NAME/"
cp -R "$ROOT/tests" "$DIST/$NAME/"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$ROOT/VERSION" "$DIST/$NAME/"

# add a simple installer that drops files and makes a symlink
cat > "$DIST/$NAME/install.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
PREFIX="${PREFIX:-/usr/local}"
DEST="${DEST:-/usr/local/fortify}"

mkdir -p "$DEST"
cp -R scripts tests README.md LICENSE VERSION "$DEST"/
chmod +x "$DEST/scripts/fortify.sh" "$DEST/scripts/gamified_reports.sh" || true

# link entrypoint
ln -sf "$DEST/scripts/fortify.sh" "$PREFIX/bin/fortify"

echo "Installed to $DEST"
echo "Run: sudo -E fortify -v --open"
EOS
chmod +x "$DIST/$NAME/install.sh"

# make archives
(
  cd "$DIST"
  tar czf "${NAME}.tar.gz" "$NAME"
  zip -qr "${NAME}.zip" "$NAME"
)

# checksums
(
  cd "$DIST"
  sha256sum "${NAME}.tar.gz" "${NAME}.zip" > "SHA256SUMS.txt" 2>/dev/null \
  || shasum -a 256 "${NAME}.tar.gz" "${NAME}.zip" > "SHA256SUMS.txt"
)

echo "Artifacts in: $DIST"
ls -lh "$DIST"
