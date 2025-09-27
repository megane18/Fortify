#!/usr/bin/env bash
set -euo pipefail

# Resolve version
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERSION="${VERSION:-}"
if [[ -z "${VERSION}" ]]; then
  if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
    VERSION="$(tr -d '\n\r ' < "$SCRIPT_DIR/VERSION")"
  else
    echo "ERROR: VERSION not set and scripts/release/VERSION not found" >&2
    exit 1
  fi
fi

echo "Packaging Fortify ${VERSION}"

# Staging dirs
DIST_DIR="$REPO_ROOT/dist"
STAGE_DIR="$DIST_DIR/fortify-${VERSION}"
rm -rf "$STAGE_DIR" "$DIST_DIR/fortify-${VERSION}.tar.gz"
mkdir -p "$STAGE_DIR"

# Ensure executables in repo (so tar preserves +x)
chmod +x "$REPO_ROOT/scripts/fortify.sh" || true
chmod +x "$REPO_ROOT/scripts/gamified_reports.sh" || true
chmod +x "$REPO_ROOT/scripts/release/install.sh" || true
# checks can be empty; make any present executable
if compgen -G "$REPO_ROOT/scripts/checks/*.sh" > /dev/null; then
  chmod +x "$REPO_ROOT/scripts/checks/"*.sh || true
fi

# Copy files into stage
install -d "$STAGE_DIR/scripts"
cp -R "$REPO_ROOT/scripts/"* "$STAGE_DIR/scripts/"

# Include top-level helpful files if present
for f in README.md LICENSE; do
  [[ -f "$REPO_ROOT/$f" ]] && cp "$REPO_ROOT/$f" "$STAGE_DIR/"
done

# (Do NOT copy a bin/fortify here; install.sh will create /usr/local/bin/fortify)

# Tar it up
(
  cd "$DIST_DIR"
  tar -czf "fortify-${VERSION}.tar.gz" "fortify-${VERSION}"
)

echo "Artifacts:"
ls -la "$DIST_DIR"
