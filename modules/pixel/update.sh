#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

curl --fail -s --cookie "devsite_wall_acks=nexus-image-tos" https://developers.google.com/android/images \
    | pup "div table tbody tr json{}" \
    | jq '.[].children
        | if (length>3)
          then {
             device: (.[2].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[2].children|.[0].href),
             sha256: .[3].text,
          } else {
             device: (.[1].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[1].children|.[0].href),
             sha256: .[2].text,
          }
          end' | jq -s > pixel-imgs.json

curl --fail -s --cookie "devsite_wall_acks=nexus-ota-tos" https://developers.google.com/android/ota \
    | pup "div table tbody tr json{}" \
    | jq '.[].children
          | {
             device: (.[1].children|.[0].href|capture("https://dl.google.com/dl/android/aosp/(?<device>[a-z]*)-ota-.*\\.zip")|.device),
             version: .[0].text,
             url: (.[1].children|.[0].href),
             sha256: .[2].text,
            }' | jq -s > pixel-otas.json
