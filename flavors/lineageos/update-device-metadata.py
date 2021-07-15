#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

import json
import os
import urllib.request

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def fetch_metadata():
    metadata = {}

    lineage_build_targets_str = urllib.request.urlopen("https://github.com/LineageOS/hudson/raw/master/lineage-build-targets").read().decode()
    for line in lineage_build_targets_str.split("\n"):
        line = line.strip()
        if line == "":
            continue
        if line.startswith("#"):
            continue

        device, variant, branch, updatePeriod = line.split()
        metadata[device] = {
            'variant': variant,
            'branch': branch,
        }

    ###

    devices = json.load(urllib.request.urlopen("https://github.com/LineageOS/hudson/raw/master/updater/devices.json"))
    for data in devices:
        if data['model'] not in metadata:
            continue

        vendor = data['oem']
        vendor = vendor.lower()

        # Workaround name inconsistency with LG
        if vendor == 'lg':
            vendor = 'lge'

        # Workaround google device names source tree inconsistency
        if data['model'] == 'shamu':
            vendor = 'moto'
        if data['model'] == 'flox':
            vendor = 'asus'

        metadata[data['model']].update({
            'vendor': vendor,
            'name': data['name'],
            'lineage_recovery': data.get('lineage_recovery', False)
        })

    return metadata

if __name__ == '__main__':
    metadata = fetch_metadata()
    save('device-metadata.json', metadata)
