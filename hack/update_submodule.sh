#!/bin/bash

set -e

TAG_BASE=$(grep 'branch =' '.gitmodules' | cut -d '=' -f 2 | tr -d ' ')

pushd kargo
git fetch && git checkout "${TAG_BASE}"
popd
