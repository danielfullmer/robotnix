#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# Downloads and extracts the BUILD_DATETIME from a factory image
# As of 2021-05-08, all upstream device builds share the same BUILD_DATETIME,
# so just using redfin here.

set -euo pipefail

DEVICE=crosshatch
CHANNEL=beta

METADATA=$(curl https://releases.grapheneos.org/${DEVICE}-${CHANNEL})
BUILD_NUMBER=$(echo $METADATA | cut -d" " -f1)
BUILD_DATETIME=$(echo $METADATA | cut -d" " -f2)

echo "{ buildNumber = \"${BUILD_NUMBER}\"; buildDateTime = ${BUILD_DATETIME}; }" > upstream-params.nix
