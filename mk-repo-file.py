#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

from typing import Optional, Dict, List, Tuple
from enum import Enum

import argparse
import json
import os
import re
import subprocess
import tempfile

REPO_FLAGS = [
    "--quiet",
    "--repo-url=https://github.com/danielfullmer/tools_repo",
    "--repo-rev=9ecb9713ee5adba95120acbc0bfef1c77b02637f",
    "--no-repo-verify",
    "--depth=1",
]

# The kind of remote a "commitish" refers to.
# These are used for the --ref-type CLI arg.
class ManifestRefType(Enum):
    BRANCH = "heads"
    TAG = "tags"

revHashes: Dict[Tuple[str, bool], str] = {}  # (rev, fetch_submodules) -> sha256hash
revTrees: Dict[str, str] = {}           # rev -> treeHash
treeHashes: Dict[Tuple[str, bool], str] = {} # (treeHash, fetch_submodules) -> sha256hash

def save(filename, data):
    open(filename, 'w').write(json.dumps(data, sort_keys=True, indent=2, separators=(',', ': ')))

def checkout_git(url, rev, fetch_submodules=False):
    print("Checking out %s %s" % (url, rev))
    args = [ "nix-prefetch-git", "--url", url, "--rev", rev ]
    if fetch_submodules:
        args.append("--fetch-submodules")
    json_text = subprocess.check_output(args).decode()
    return json.loads(json_text)

def ls_remote(url, rev):
    remote_info = subprocess.check_output([ "git", "ls-remote", url, rev ]).decode()
    remote_rev = remote_info.split('\t')[0]
    assert remote_rev != ""
    return remote_rev

def make_repo_file(url: str, ref: str, filename: str, ref_type: ManifestRefType,
                   override_project_revs: Dict[str, str], resume: bool,
                   mirrors: Dict[str, str], project_fetch_submodules: List[str],
                   override_tag: Optional[str], include_prefix: List[str],
                   exclude_path: List[str]):
    if resume and os.path.exists(filename):
        data = json.load(open(filename))
    else:
        print("Fetching information for %s %s" % (url, ref))
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.check_call(['repo', 'init', f'--manifest-url={url}', f'--manifest-branch=refs/{ref_type.value}/{ref}', *REPO_FLAGS], cwd=tmpdir)
            json_text = subprocess.check_output(['repo', 'dumpjson'] + (["--local-only"] if override_project_revs else []), cwd=tmpdir).decode()
            data = json.loads(json_text)

            save(filename, data)

    for relpath, p in data.items():
        if len(include_prefix) > 0 and (not any(relpath.startswith(p) for p in include_prefix)):
            continue

        if relpath in exclude_path:
            continue

        for project, rev in override_project_revs.items():
            # We have to iterate over the whole output since we don't save
            # the project name anymore, just the relpath, which isn't
            # exactly the project name
            if p['url'].endswith(project):
                p['rev'] = rev

        if override_tag is not None:
            p['revisionExpr'] = override_tag

        if 'rev' not in p:
            if re.match("[0-9a-f]{40}", p['revisionExpr']):
                # Fill out rev if we already have the information available
                # Use revisionExpr if it is already a SHA1 hash
                p['rev'] = p['revisionExpr']
            else:
                # Otherwise, fetch this information from the git remote
                p['rev'] = ls_remote(p['url'], p['revisionExpr'])

        # TODO: Incorporate "sync-s" setting from upstream manifest if it exists
        fetch_submodules = relpath in project_fetch_submodules

        if fetch_submodules:
            p['fetchSubmodules'] = True

        if 'sha256' not in p:
            print("Fetching information for %s %s" % (p['url'], p['rev']))
            # Used cached copies if available
            if (p['rev'], fetch_submodules) in revHashes:
                p['sha256'] = revHashes[p['rev'], fetch_submodules]
                if p['rev'] in revTrees:
                    p['tree'] = revTrees[p['rev']]
                continue

            p_url = p['url']
            found_treehash = False
            for mirror_url, mirror_path in mirrors.items():
                if p['url'].startswith(mirror_url):
                    p_url = p['url'].replace(mirror_url, mirror_path)
                    p['tree'] = subprocess.check_output(['git', 'log','-1', '--pretty=%T', p['rev']], cwd=p_url+'.git').decode().strip()
                    if (p['tree'], fetch_submodules) in treeHashes:
                        p['sha256'] = treeHashes[p['tree'], fetch_submodules]
                        found_treehash = True
            if found_treehash:
                continue

            # Fetch information. Use revisionExpr if it is a tag so we use the
            # tag in the name of the nix derivation instead of the revision
            if p['revisionExpr'].startswith('refs/tags/'):
                git_info = checkout_git(p_url, p['revisionExpr'], fetch_submodules)
            else:
                git_info = checkout_git(p_url, p['rev'], fetch_submodules)
            p['sha256'] = git_info['sha256']

            # Add to cache
            revHashes[p['rev'], fetch_submodules] = p['sha256']
            if 'tree' in p:
                treeHashes[p['tree']] = p['sha256']

            # Save after every new piece of information just in case we crash
            save(filename, data)

    # Save at the end as well!
    save(filename, data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default=None, help="path to output file, defaults to repo-{rev}.json")
    parser.add_argument('--ref-type', help="the kind of ref that is to be fetched",
                        choices=[t.name.lower() for t in ManifestRefType], default=ManifestRefType.TAG.name.lower())
    parser.add_argument('--resume', help="resume a previous download", action='store_true')
    parser.add_argument('--repo-prop', help="repo.prop file to use as source for project git revisions")
    parser.add_argument('--override-tag', help="tag to fetch for subrepos, ignoring revisions from manifest")
    parser.add_argument('--project-fetch-submodules', action="append", default=[], help="fetch submodules for the specified project path")
    parser.add_argument('--include-prefix', action="append", default=[], help="only include paths if they start with the specified prefix")
    parser.add_argument('--exclude-path', action="append", default=[], help="paths to exclude from fetching")
    parser.add_argument('url', help="manifest URL")
    parser.add_argument('ref', help="manifest ref")
    parser.add_argument('oldrepojson', nargs='*', help="any older repo json files to use for cached sha256s")
    args = parser.parse_args()

    mirrors = dict(mirror.split("=") for mirror in os.environ.get('ROBOTNIX_GIT_MIRRORS', '').split('|'))

    ref_type = ManifestRefType[args.ref_type.upper()]

    # Extract project revisions from repo.prop
    override_project_revs = {}
    if args.repo_prop:
        lines = open(args.repo_prop, 'r').read().split('\n')
        for line in lines:
            if line:
                project, rev = line.split()
                override_project_revs[project] = rev

    # Read all oldrepojson files to populate hashtables
    for filename in args.oldrepojson:
        data = json.load(open(filename))
        for name, p in data.items():
            if 'sha256' in p:
                revHashes[p['rev'], p.get('fetchSubmodules', False)] = p['sha256']
                if 'tree' in p:
                    treeHashes[p['tree'], p.get('fetchSubmodules', False)] = p['sha256']
                    revTrees[p['rev']] = p['tree']

    if args.out is not None:
        filename = args.out
    else:
        filename = f'repo-{args.ref}.json'

    make_repo_file(args.url, args.ref, filename, ref_type,
                   override_project_revs, resume=args.resume,
                   mirrors=mirrors,
                   project_fetch_submodules=args.project_fetch_submodules,
                   override_tag=args.override_tag,
                   include_prefix=args.include_prefix,
                   exclude_path=args.exclude_path,
                   )

if __name__ == "__main__":
    main()
