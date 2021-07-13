# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkOption mkEnableOption mkIf mkMerge types;

  cfg = config.apps.updater;

  src = pkgs.fetchFromGitHub {
    owner = "GrapheneOS";
    repo = "platform_packages_apps_Updater";
    rev = "f4fea23153407b7448e9440c31dc0398befc00c8"; # 2021-01-04
    sha256 = "1my5kxia201sikxr2bjk5v4icw5av9c1q5v56g03zw0mmvddyv6a";
  };
in
{
  options = {
    apps.updater = {
      enable = mkEnableOption "OTA Updater";

      url = mkOption {
        type = types.str;
        description = "URL for OTA updates";
        apply = x: if lib.hasSuffix "/" x then x else x + "/";
      };

      flavor = mkOption {
        type = types.enum [ "grapheneos" "lineageos" ];
        default = "grapheneos";
        description = ''
          Which updater package to use, and which kind of metadata to generate for it.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      source.dirs."robotnix/apps/Updater".src = mkIf (cfg.flavor == "grapheneos") src;

      # It's currently a system package in upstream
      system.additionalProductPackages = [ "Updater" ];

      resources."robotnix/apps/Updater" = mkIf (cfg.flavor == "grapheneos") {
        inherit (cfg) url;
        channel_default = config.channel;
      };

      resources."packages/apps/Updater" = mkIf (cfg.flavor == "lineageos") {
        updater_server_url = cfg.url;
      };
    }

    # Add selinux policies
    (mkIf (config.flavor == "grapheneos" && config.androidVersion >= 11) {
      source.dirs."robotnix/updater-sepolicy".src = ./updater-sepolicy;
      source.dirs."build/make".postPatch = ''
        # Originally from https://github.com/RattlesnakeOS/core-config-repo/blob/0d2cb86007c3b4df98d4f99af3dedf1ccf52b6b1/hooks/aosp_build_pre.sh
        sed -i '/product-graph dump-products/a #add selinux policies last\n$(eval include robotnix/updater-sepolicy/sepolicy.mk)' "core/config.mk"
      '';
    })
  ]);
}
