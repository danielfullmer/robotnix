#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2021 Samuel Dionne-Riel
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -eu

args=(
	"https://github.com/pmanbox/platform_manifests"
    --ref-type branch
    "pmanbox" # static branch name
    ../*/repo-*.json
)

export TMPDIR=/tmp

../../mk-repo-file.py "${args[@]}"
