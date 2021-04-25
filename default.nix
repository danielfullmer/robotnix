# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ configuration,
  pkgs ? (import ./pkgs {}),
  lib ? pkgs.stdenv.lib
}:

with lib;
let
  eval = (evalModules {
    modules = [
      ({ config, ... }: {
        options.nixpkgs.overlays = mkOption {
          default = [];
          type = types.listOf types.unspecified;
          description = "Nixpkgs overlays to override the default packages used while building robotnix.";
        };

        config = {
          _module.args = let
            finalPkgs = pkgs.appendOverlays config.nixpkgs.overlays;
            apks = import ./apks { pkgs = finalPkgs; };
            robotnixlib = import ./lib lib;
          in {
            inherit apks lib robotnixlib;
            pkgs = finalPkgs;
          };
        };
      })
      configuration
      ./flavors/grapheneos
      ./flavors/lineageos
      ./flavors/twrp
      ./flavors/vanilla
      ./modules/10
      ./modules/11
      ./modules/12
      ./modules/9
      ./modules/apps/auditor.nix
      ./modules/apps/chromium.nix
      ./modules/apps/fdroid.nix
      ./modules/apps/prebuilt.nix
      ./modules/apps/seedvault.nix
      ./modules/apps/updater.nix
      ./modules/apv.nix
      ./modules/assertions.nix
      ./modules/base.nix
      ./modules/emulator.nix
      ./modules/envpackages.nix
      ./modules/etc.nix
      ./modules/framework.nix
      ./modules/google.nix
      ./modules/hosts.nix
      ./modules/kernel.nix
      ./modules/microg.nix
      ./modules/pixel
      ./modules/release.nix
      ./modules/resources.nix
      ./modules/signing.nix
      ./modules/source.nix
      ./modules/webview.nix
    ];
  });

  # From nixpkgs/nixos/modules/system/activation/top-level.nix
  failedAssertions = map (x: x.message) (lib.filter (x: !x.assertion) eval.config.assertions);

  config = if failedAssertions != []
    then throw "\nFailed assertions:\n${lib.concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
    else lib.showWarnings eval.config.warnings eval.config;

in {
  inherit (eval) pkgs config options;

  # Things that are nice to have at the top-level, since they might get moved
  # in the future:
  inherit (eval.config.build)
    targetFiles unsignedTargetFiles signedTargetFiles
    ota incrementalOta img factoryImg bootImg otaDir
    releaseScript generateKeysScript verifyKeysScript
    emulator;
}
