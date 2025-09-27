#!/usr/bin/env bash
set -euo pipefail

# Install Fortify into /usr/local/fortify and create /usr/local/bin/fortify wrapper.

PREFIX="/usr/local"
APPDIR="$PREFIX/fortify"
BINDIR="$PREFIX/bin"

# Where are we running from? (the extracted tarball root)
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Fortify to: $APPDIR"
sudo mkdir -p "$APPDIR/scripts"/{checks,lib,profiles}
sudo mkdir -p "$BINDIR"

# Copy everything we need
sudo install -m 755 "$SRC_DIR/scripts/fortify.sh"         "$APPDIR/scripts/fortify.sh"
sudo install -m 644 "$SRC_DIR/scripts/gamified_reports.sh" "$APPDIR/scripts/gamified_reports.sh"

if compgen -G "$SRC_DIR/scripts/checks/*.sh" > /dev/null; then
  sudo cp -a "$SRC_DIR/scripts/checks/"*.sh               "$APPDIR/scripts/checks/"
  sudo chmod 644 "$APPDIR/scripts/checks/"*.sh
fi

if compgen -G "$SRC_DIR/scripts/lib/*.sh" > /dev/null; then
  sudo cp -a "$SRC_DIR/scripts/lib/"*.sh                  "$APPDIR/scripts/lib/"
  sudo chmod 644 "$APPDIR/scripts/lib/"*.sh
fi

sudo cp -a "$SRC_DIR/scripts/profiles/"*.profile          "$APPDIR/scripts/profiles/"
sudo chmod 644 "$APPDIR/scripts/profiles/"*.profile

# Wrapper: always call the installed fortify.sh, and set DEFAULT_PROFILE to installed path
sudo tee "$BINDIR/fortify" >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail

# Installed locations
FORTIFY_HOME="/usr/local/fortify"
FORTIFY_SCRIPT="$FORTIFY_HOME/scripts/fortify.sh"
export DEFAULT_PROFILE="$FORTIFY_HOME/scripts/profiles/default.profile"

# Let the script know where it's installed
export FORTIFY_PREFIX="$FORTIFY_HOME"

exec sudo -E bash "$FORTIFY_SCRIPT" "$@"
WRAP
sudo chmod 755 "$BINDIR/fortify"

echo "✓ Installed fortify wrapper at: $BINDIR/fortify"
echo "✓ Scripts at: $APPDIR/scripts"
echo
echo "Run:"
echo "  sudo -E fortify -v --open"
echo "  # or with the server profile"
echo "  sudo -E fortify -v --open -p $APPDIR/scripts/profiles/server.profile"
