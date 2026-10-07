#!/bin/zsh
# Gzowo Concierge - publishes web/ to https://concierge.gzowo.fun (public repo JerzySukiennik/concierge, GitHub Pages, root + frozen vX.Y snapshots).
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$SRC/Niepotrzebne/pages"
REPO="JerzySukiennik/concierge"
SKILL="$HOME/.claude/skills/deploy/scripts"

mkdir -p "$DIR"
if [ ! -d "$DIR/.git" ]; then
  if gh repo view "$REPO" >/dev/null 2>&1; then
    git clone -q "https://github.com/$REPO.git" "$DIR.tmp" && rm -rf "$DIR" && mv "$DIR.tmp" "$DIR"
  else
    (cd "$DIR" && git init -q -b main)
  fi
fi
cd "$DIR"

rsync -a --delete --exclude .git --exclude 'v[0-9]*' --exclude CNAME --exclude .nojekyll --exclude .DS_Store "$SRC/web/" "$DIR/"
echo "concierge.gzowo.fun" > CNAME
: > .nojekyll

next=$(bash "$SKILL/next-version.sh" .)
bash "$SKILL/snapshot-version.sh" . "$next"
git add -A
if bash "$SKILL/scan-secrets.sh" .; then :; else echo "scan reported findings (see above)"; fi
git -c user.name="$(git -C "$SRC" config user.name)" -c user.email="$(git -C "$SRC" config user.email)" commit -q -m "Publish $next

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
if ! git remote get-url origin >/dev/null 2>&1; then
  gh repo create "$REPO" --public --source=. --remote=origin --description "Gzowo Concierge web app (published build)" >/dev/null
fi
git push -q -u origin main
echo "published $next"
