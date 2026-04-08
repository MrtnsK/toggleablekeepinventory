#!/usr/bin/env bash
set -euo pipefail

# ─── Usage ────────────────────────────────────────────────────────────────────
# ./release.sh           → bumps patch  (1.0.0 → 1.0.1)
# ./release.sh minor     → bumps minor  (1.0.0 → 1.1.0)
# ./release.sh major     → bumps major  (1.0.0 → 2.0.0)
#
# Requires: gh CLI (brew install gh) authenticated via `gh auth login`
# ──────────────────────────────────────────────────────────────────────────────

BUMP="${1:-patch}"

# ─── Helpers ──────────────────────────────────────────────────────────────────
red()   { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
blue()  { echo -e "\033[34m$*\033[0m"; }

require() {
  command -v "$1" &>/dev/null || { red "Error: '$1' is required but not found."; exit 1; }
}

# ─── Checks ───────────────────────────────────────────────────────────────────
require git
require mvn
require gh

if ! gh auth status &>/dev/null; then
  red "Error: not authenticated with gh. Run: gh auth login"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  red "Error: working directory is not clean. Commit or stash your changes first."
  exit 1
fi

# ─── Read current version from pom.xml ────────────────────────────────────────
CURRENT=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
blue "Current version: $CURRENT"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *)
    red "Error: invalid bump type '$BUMP'. Use major, minor, or patch."
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${NEW_VERSION}"
blue "New version:     $NEW_VERSION"

read -rp "Proceed with release $TAG ? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ─── Update version ───────────────────────────────────────────────────────────
blue "Updating pom.xml..."
mvn versions:set -DnewVersion="$NEW_VERSION" -DgenerateBackupPoms=false -q

# ─── Build ────────────────────────────────────────────────────────────────────
blue "Building JAR..."
mvn package -q

JAR="target/toggleablekeepinventory-${NEW_VERSION}.jar"
if [[ ! -f "$JAR" ]]; then
  red "Error: expected JAR not found at $JAR"
  exit 1
fi
green "JAR built: $JAR"

# ─── Commit & tag ─────────────────────────────────────────────────────────────
blue "Committing version bump..."
git add pom.xml
git commit -m "chore: release ${TAG}"

blue "Creating tag $TAG..."
git tag -a "$TAG" -m "Release ${TAG}"

blue "Pushing commit and tag..."
git push origin main
git push origin "$TAG"

# ─── GitHub Release ───────────────────────────────────────────────────────────
blue "Creating GitHub release..."
gh release create "$TAG" "$JAR" \
  --title "$TAG" \
  --notes "Release ${TAG}"

green "Done! Release $TAG published."
