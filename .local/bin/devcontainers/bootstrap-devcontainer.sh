#!/usr/bin/env bash
set -euo pipefail

git fetch --depth 1 origin devcontainer-linux
git checkout --detach FETCH_HEAD

exec ./bootstrap-devcontainer.sh