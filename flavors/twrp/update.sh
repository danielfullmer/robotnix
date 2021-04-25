#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# Note: To ensure this script grabs the latest revisions associated with the
# TWRP branch, use the --force option (passed through to mk-repo-file).
# Otherwise, it will just use the cached revisions in the .repo file

set -eu

if [[ "$USER" = "danielrf" ]]; then
    mirror_args=(
        --mirror "https://android.googlesource.com=/mnt/cache/mirror"
        --mirror "https://github.com/LineageOS=/mnt/cache/lineageos/LineageOS"
        --mirror "https://github.com/TheMuppets=/mnt/cache/muppets/TheMuppets"
        --mirror "https://github.com/TeamWin=/mnt/cache/twrp/TeamWin"
        --mirror "https://github.com/omnirom=/mnt/cache/omnirom/omnirom"
    )
else
    mirror_args=()
fi

# FIXME: we probably want to deal with different branch names

args=(
    --ref-type branch
    "https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni"
    "twrp-9.0"
    ../*/repo-*.json
)

export TMPDIR=/tmp

#./update-device-metadata.py
../../mk-repo-file.py "${mirror_args[@]}" "${args[@]}"
#./update-device-dirs.py "${mirror_args[@]}"
