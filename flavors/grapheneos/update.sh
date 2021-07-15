#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -eu

args=(
    --ref-type tag
    "https://github.com/GrapheneOS/platform_manifest"
    --project-fetch-submodules "kernel/google/crosshatch"
    --project-fetch-submodules "kernel/google/coral"
    --project-fetch-submodules "kernel/google/sunfish"
    --project-fetch-submodules "kernel/google/redbull"
    "$@"
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
