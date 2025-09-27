#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/usr/local/fortify}"
BIN_LINK="/usr/local/bin/fortify"

# If run from inside extracted folder fortify-<version>
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "Installing to: ${PREFIX}"
sudo mkdir -p "$PREFIX"
sudo rsync -a --delete "${SRC_DIR}/" "$PREFIX/"

# Create/replace the launcher
sudo bash -c "cat > '${BIN_LINK}'" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/fortify/scripts/fortify.sh "$@"
WRAP
sudo chmod +x "${BIN_LINK}"

echo "Installed:"
echo "  Core: ${PREFIX}"
echo "  CLI : ${BIN_LINK}"
echo
echo "Try:"
echo "  sudo -E fortify -v --open"
echo "  sudo -E fortify -v --open -p /usr/local/fortify/scripts/profiles/server.profile"
