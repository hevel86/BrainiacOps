#!/bin/bash
set -e

# Get current date in YYYY.MM.DD format
TAG_NAME=$(date +%Y.%m.%d)

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  echo "Tag $TAG_NAME already exists"
  exit 0
fi

echo "Creating tag $TAG_NAME"
git tag "$TAG_NAME"
git push origin "$TAG_NAME"
