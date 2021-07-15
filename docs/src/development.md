<!--
SPDX-FileCopyrightText: 2021 Daniel Fullmer and robotnix contributors
SPDX-License-Identifier: MIT
-->

# Development

Robotnix modules use the same Nix-based module system used in NixOS.
To understand the NixOS module system, please [read this](https://nixos.org/manual/nixos/stable/index.html#sec-writing-modules).

Robotnix does not primarily aim to significantly decrease the complexity of Android development,
but rather (once a developer has a working build) makes it easier to share that work with others.

As such, robotnix does not replace the existing Android build system, but provides a convenient Nix-based wrapper around the build system.
(See [blueprint2nix](https://github.com/danielfullmer/blueprint2nix) and [soongnix](https://github.com/danielfullmer/soongnix) for an experimental attempt at reimplementing part of the Android build system natively in Nix.)

Feel free to ask robotnix development questions in `#robotnix` on Freenode.

## Git mirrors
Robotnix can be configured to use local git mirrors of Android source code.
The AOSP documentation includes instructions to [create a local mirror of the Android source code](https://source.android.com/setup/build/downloading#using-a-local-mirror).
Maintaining a local mirror can save bandwidth in the long-run when repeatedly updating a flavor over time which contains incremental updates.

This functionality is enabled by setting the `ROBOTNIX_GIT_MIRRORS` environment variable.
The value of `ROBOTNIX_GIT_MIRRORS` contains a number of mappings, each separated by a `|` character.
Each mapping is of the format `<remote_url>=<local_url>`.
For example:
```
ROBOTNIX_GIT_MIRRORS=https://android.googlesource.com=/mnt/cache/mirror|https://github.com/LineageOS=/mnt/cache/lineageos/LineageOS
```

Both the robotnix update scripts as well as robotnix's overridden `fetchgit` derivation use `ROBOTNIX_GIT_MIRRORS`.
This environment variable is passed to `fetchgit` via `impureEnvVars` (search for `impureEnvVars` in the [Nix manual](https://nixos.org/manual/nix/stable/)).
If the Nix daemon is being used, it needs to have this `ROBOTNIX_GIT_MIRRORS` in its environment, not just in the user's environment when running `nix-build` or `nix build`.
The following NixOS configuration can be used to easily set this environment variable for the Nix daemon:
```nix
let
  mirrors = {
    "https://android.googlesource.com" = "/mnt/cache/mirror";
    "https://github.com/LineageOS" = "/mnt/cache/lineageos/LineageOS";
  };
in
{
  systemd.services.nix-daemon.serviceConfig.Environment = [
    ("ROBOTNIX_GIT_MIRRORS=" + lib.concatStringsSep "|" (lib.mapAttrsToList (local: remote: "${local}=${remote}") mirrors))
  ];

  # Also add local mirrors to nix sandbox exceptions
  nix.sandboxPaths = lib.attrValues mirrors;
}
```

## Helper scripts
Robotnix can produce a few helper scripts that can make Android development easier in some circumstances.

Running `nix-build --arg configuration <cfg> -A <output>` for the outputs below will produce the corresponding helper script, using the provided robotnix configuration.

- `config.build.debugEnterEnv` produces a script which enters an FHS environment with the required dependencies, as well as the Android source files bind-mounted under the current directory.  Useful in conjunction with `cd $(mktemp -d)` to enter a temporary directory.  Files are bind-mounted readonly, so files cannot be edited ad-hoc using this script.

The following outputs can be useful with an existing Android source checkout made using `repo`.
- `config.build.env` produces a `robotnix-build` script under `bin/` which enters an FHS environment that contains all required dependencies to build Android.
- `config.build.debugUnpackScript` produces a script which will copy the robotnix-specific source directories into `./robotnix/`.
- `config.build.debugPatchScript` produces a script which will patch all Android source directories under the current directory in a similar way they would be patched during a normal robotnix build.

## External modules
Robotnix is welcome to contributions of well-written modules that can be maintained in an ongoing fashion.
Modules can provide support for new flavors, additional devices with an existing flavor, included system/privileged applications, and others.

If the proposed module is not suitable for inclusion as an upstream robotnix module,
it can still be developed and maintained externally and easily included by a user.
This can be done in a similar way as is done with NixOS modules.
For instance, if the module is provided by `default.nix` in the `owner/repo` repository on GitHub:
```nix
{
    imports = [ (builtins.fetchTarball {
        url = "https://github.com/owner/repo/archive/9b034054166e1f01b3bdb6a1948daa3bdafe039a.tar.gz";
        sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    }) ];
}
```
The above `imports` statement will include the provided module in the robotnix build, pinned by the provided revision and `sha256`.
Any options or configuration set by the specified module will be included in the build.

## Developing a new flavor
To create a new flavor, the developer should create a robotnix module that conditions on `config.flavor`.
The flavor configuration defaults should be set conditionally using (for example) `mkIf (config.flavor = "...") { ... }`.
Those configuration defaults should include:
 - Setting `source.dirs` using a repo JSON file produced by `mk-repo-file.py`.
 - Setting the default `androidVersion`.
 - Setting the default `buildDateTime` based on (for example) the time that the flavor was last updated.
 - Providing a warning if the user has not selected a valid device for this flavor.

Additionally, flavors should provide update scripts that can (at least) automatically produce an updated repo JSON file.
It is recommended to take a look at the Nix expressions implementing the current flavors under `flavors/`.

## Emulator
Robotnix can also build a script which will start the Android emulator using an attached robotnix-built system image.
This can be accomplished with the `emulator` Nix output
To build and run an emulator with an attached vanilla system image, use (for example):
```console
$ nix-build ./default.nix --arg configuration '{device="x86_64"; flavor="vanilla";}' -A emulator
$ ./result
```
This currently only works well when using the generic `x86_64` device.


## Testing / CI / Reproducibility
All devices (Pixel 3-5(a) (XL)) have very basic checks to ensure that the android build process will at least start properly.
See `release.nix` for the set of configurations with this minimal build testing.
This check is run using `nix-build ./release.nix -A check`.
As each build takes approximately 4 hours--I only build marlin and crosshatch builds for myself.
At some point, I would love to set up a build farm and publish build products on s3 or [cachix](https://cachix.org).
This would allow an end-user to simply sign releases using their own keys without building the entire AOSP themselves.

As of 2020-05-17, `target_files`, `signed_target_files`, `img`, and `ota` files have all been verified to be bit-for-bit reproducible for `crosshatch` and `marlin` using the `vanilla` flavor.
Automated periodic testing of this is still desired.

One option being investigated is to have multiple independent remote builders produce unsigned target files for a number of device and flavor combinations.
An end-user could then verify that the builders produced the same unsigned target files, and finish the process by signing the target files and producing their own `img` and `ota` files.
This eliminates the requirement for an end-user to spend hours building android.

There are, however, a few places where user-specific public keys are included in the build for key pinning.
This unfortunately decreases the possibility of sharing build products between users.
The F-Droid privileged extension and Trichrome (disabled for now) are two components which have this issue.
Fixes for this are still under investigation.

## Additional Notes
Robotnix bind mounts the source directories from `/nix/store`.
These files/directories have their "user write" (`u-w`) permission removed.
Sometimes, Android Makefiles which copy files from the source directories may assume the files have the write permission enabled, which can then break later steps.
To work around these issues, it is usually sufficient to add a `chmod` command or add `--no-preserve=owner,mode` to the `cp` command in the Makefile.
