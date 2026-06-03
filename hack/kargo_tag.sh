#!/bin/bash

# Extract current tag from .gitmodules file
TAG_BASE=$(grep 'branch =' '.gitmodules' | cut -d '=' -f 2 | tr -d ' ')

# Retrieve latest release from GitHub
LAST_TAG=$(gh release list \
  -O desc \
  -L 1 \
  --json tagName,isDraft,isPrerelease \
  --jq '.[] | select(.isDraft==false and .isPrerelease==false and (.tagName | startswith("'"${TAG_BASE}-"'"))) | .tagName')

# Calculate Next Tag
NEXT_TAG="${TAG_BASE}-1"
if [[ -n "${LAST_TAG}" ]]; then
  LAST_SUFFIX=${LAST_TAG##*-}
  NEXT_SUFFIX=$((LAST_SUFFIX+1))
  NEXT_TAG="${TAG_BASE}-${NEXT_SUFFIX}"
fi

# Print result
printf "%s" "${NEXT_TAG}"
