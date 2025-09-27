#!/usr/bin/env bash
set -euo pipefail

# repo root
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION)"
NAME="fortify-${VERSION}"
DIST="$ROOT/dist"

# clean
rm -rf "$DIST"
mkdir -p "$DIST/$NAME"

# payload
cp -R scripts "$DIST/$NAME/scripts"
cp -R tests   "$DIST/$NAME/tests"
cp README.md LICENSE VERSION "$DIST/$NAME/"

# lightweight installer (keeps structure under /usr/local/fortify)
cat > "$DIST/$NAME/install.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DEST="${DEST:-/usr/local/fortify}"

echo "[*] Installing Fortify into: $DEST"
mkdir -p "$DEST"
cp -R scripts tests README.md LICENSE VERSION "$DEST/"

# permissions
chmod +x "$DEST/scripts/fortify.sh" || true
chmod +x "$DEST/scripts/gamified_reports.sh" || true
find "$DEST/scripts/checks" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$DEST/tests" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# link entrypoint
mkdir -p "$PREFIX/bin"
ln -sf "$DEST/scripts/fortify.sh" "$PREFIX/bin/fortify"

echo "[✓] Installed."
echo
echo "Run:"
echo "  sudo -E fortify -v --open"
echo "  # or with the server profile"
echo "  sudo -E fortify -v --open -p $DEST/scripts/profiles/server.profile"
EOS
chmod +x "$DIST/$NAME/install.sh"

# archives
(
  cd "$DIST"
  tar czf "${NAME}.tar.gz" "$NAME"
  zip -qr "${NAME}.zip" "$NAME"
)

# checksums
(
  cd "$DIST"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${NAME}.tar.gz" "${NAME}.zip" > "SHA256SUMS.txt"
  else
    shasum -a 256 "${NAME}.tar.gz" "${NAME}.zip" > "SHA256SUMS.txt"
  fi
)

echo
echo "[✓] Built artifacts:"
ls -lh "$DIST"
