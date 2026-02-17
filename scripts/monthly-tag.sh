#!/bin/bash
set -e

# Get current date in YYYY.MM.DD format
TAG_NAME=$(date +%Y.%m.%d)

# Auto-commit changes if any exist
if [[ -n $(git status --porcelain) ]]; then
  echo "Changes detected. Committing..."
  git add .
  git commit -m "Monthly release: $TAG_NAME"
  git push origin HEAD
else
  echo "No changes detected."
fi

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  echo "Tag $TAG_NAME already exists"
  exit 0
fi

echo "Creating tag $TAG_NAME"
git tag "$TAG_NAME"
git push origin "$TAG_NAME"
