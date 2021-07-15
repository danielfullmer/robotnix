#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

import argparse
import json
import os
import subprocess
import urllib.request

# A full run took approximately 12 minutes total. Needed to set TMPDIR=/tmp
#
# TODO: Output a timestamp somewhere
# TODO: Extract code shared with mk-repo-file.py into a common location
# TODO: Optionally parallelize fetching

LINEAGE_REPO_BASE = "https://github.com/LineageOS"
VENDOR_REPO_BASE = "https://github.com/TheMuppets"
MIRRORS = dict(mirror.split("=") for mirror in os.environ.get('ROBOTNIX_GIT_MIRRORS', '').split('|'))
REMOTE_REFS = {} # url: { ref: rev }

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def get_mirrored_url(url):
    for mirror_url, mirror_path in MIRRORS.items():
        if url.startswith(mirror_url):
            url = url.replace(mirror_url, mirror_path)
    return url

def ls_remote(url):
    if url in REMOTE_REFS:
        return REMOTE_REFS[url]

    orig_url = url
    url = get_mirrored_url(url)

    remote_info = subprocess.check_output([ "git", "ls-remote", url ]).decode()
    REMOTE_REFS[orig_url] = dict(reversed(line.split('\t')) for line in remote_info.split('\n') if line)
    return REMOTE_REFS[orig_url]

def checkout_git(url, rev):
    print("Checking out %s %s" % (url, rev))
    json_text = subprocess.check_output([ "nix-prefetch-git", "--url", url, "--rev", rev]).decode()
    return json.loads(json_text)

def fetch_relpath(dirs, relpath, url, branch):
    orig_url = url
    url = get_mirrored_url(url)

    current_rev = dirs.get(relpath, {}).get('rev', None)
    refs = ls_remote(url)
    ref = f'refs/heads/{branch}'
    if ref not in refs:
        raise Exception(f'{url} is missing {ref}')
    newest_rev = refs[ref]
    if (current_rev != newest_rev
            or ('path' not in dirs[relpath])
            or (not os.path.exists(dirs[relpath]['path']))):
        dirs[relpath] = checkout_git(url, ref)
        dirs[relpath]['url'] = orig_url
    else:
        print(relpath + ' is up to date.')

    return dirs[relpath]


# Fetch device source trees for devices in metadata and save their information into filename
def fetch_device_dirs(metadata, filename, branch):
    if os.path.exists(filename):
        dirs = json.load(open(filename))
    else:
        dirs = {}

    dirs_to_fetch = set() # Pairs of (relpath, url)
    dirs_fetched = set() # Just strings of relpath
    for device, data in metadata.items():
        vendor = data['vendor']
        url = f'{LINEAGE_REPO_BASE}/android_device_{vendor}_{device}'

        refs = ls_remote(url)
        if f'refs/heads/{branch}' in refs:
            dirs_to_fetch.add((f'device/{vendor}/{device}', url))
        else:
            print(f'SKIP: {branch} branch does not exist for {device}')

    dir_dependencies = {} # key -> [ values ]. 
    while len(dirs_to_fetch) > 0:
        relpath, url = dirs_to_fetch.pop()
        try:
            dir_info = fetch_relpath(dirs, relpath, url, branch)
        except:
            continue

        # Also grab any dirs that this one depends on
        lineage_dependencies_filename = os.path.join(dir_info['path'], 'lineage.dependencies')
        if os.path.exists(lineage_dependencies_filename):
            lineage_dependencies = json.load(open(lineage_dependencies_filename))

            for dep in lineage_dependencies:
                if dep['target_path'] not in dirs_fetched:
                    dirs_to_fetch.add((dep['target_path'], f"{LINEAGE_REPO_BASE}/{dep['repository']}"))

            dir_info['deps'] = [ dep['target_path'] for dep in lineage_dependencies ]
        else:
            dir_info['deps'] = []

        save(filename, dirs) # Save after every step, for resuming
        dirs_fetched.add(relpath)

    return dirs, dir_dependencies

def fetch_vendor_dirs(metadata, filename, branch):
    required_vendor = set()
    for device, data in metadata.items():
        if 'vendor' in data:
            required_vendor.add(data['vendor'].lower())
        # Bacon needs vendor/oppo
        # https://github.com/danielfullmer/robotnix/issues/26
        if device == 'bacon':
            required_vendor.add('oppo')
        # shamu needs a workaround as well
        if device == 'shamu':
            required_vendor.add('motorola')
            required_vendor.remove('moto')

    if os.path.exists(filename):
        dirs = json.load(open(filename))
    else:
        dirs = {}

    for vendor in required_vendor:
        relpath = f'vendor/{vendor}'

        # XXX: HACK
        if vendor == "xiaomi":
            url = "https://gitlab.com/the-muppets/proprietary_vendor_xiaomi.git/"
        else:
            url = f"{VENDOR_REPO_BASE}/proprietary_{relpath.replace('/', '_')}"

        refs = ls_remote(url)
        if f'refs/heads/{branch}' in refs:
            fetch_relpath(dirs, relpath, url, branch)
            save(filename, dirs)
        else:
            print(f'SKIP: {branch} branch does not exist for {url}')

    return dirs

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--branch', help="lineageos version")
    parser.add_argument('product', nargs='*',
                        help='product to fetch directory metadata for, specified by <vendor>_<device> (example: google_crosshatch) '
                        'If no products are specified, all products in device-metadata.json will be updated')
    args = parser.parse_args()

    if len(args.product) == 0:
        metadata = json.load(open('device-metadata.json'))
    else:
        metadata = {}
        for product in args.product:
            vendor, device = product.split('_', 1)
            metadata[device] = { 'vendor': vendor }

    device_dirs, dir_dependencies = fetch_device_dirs(metadata, os.path.join(args.branch, 'device-dirs.json'), args.branch)
    vendor_dirs = fetch_vendor_dirs(metadata, os.path.join(args.branch, 'vendor-dirs.json'), args.branch)

if __name__ == '__main__':
    main()
