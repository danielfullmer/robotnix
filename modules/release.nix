# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkDefault mkOption types optionalString;

  otaTools = config.build.otaTools;

  wrapScript = { commands, keysDir }: ''
    export PATH=${otaTools}/bin:$PATH
    export EXT2FS_NO_MTAB_OK=yes

    # build-tools releasetools/common.py hilariously tries to modify the
    # permissions of the source file in ZipWrite. Since signing uses this
    # function with a key, we need to make a temporary copy of our keys so the
    # sandbox doesn't complain if it doesn't have permissions to do so.
    export KEYSDIR=${keysDir}
    if [[ "$KEYSDIR" ]]; then
      if [[ ! -d "$KEYSDIR" ]]; then
        echo 'Missing KEYSDIR directory, did you use "--option extra-sandbox-paths /keys=..." ?'
        exit 1
      fi
      ${lib.optionalString config.signing.enable "${config.build.verifyKeysScript} \"$KEYSDIR\" || exit 1"}
      NEW_KEYSDIR=$(mktemp -d /dev/shm/robotnix_keys.XXXXXXXXXX)
      trap "rm -rf \"$NEW_KEYSDIR\"" EXIT
      cp -r "$KEYSDIR"/* "$NEW_KEYSDIR"
      chmod u+w -R "$NEW_KEYSDIR"
      KEYSDIR=$NEW_KEYSDIR
    fi

    ${commands}
  '';

  runWrappedCommand = name: script: args: pkgs.runCommand "${config.device}-${name}-${config.buildNumber}.zip" {} (wrapScript {
    commands = script (args // {out="$out";});
    keysDir = config.signing.buildTimeKeyStorePath;
  });

  signedTargetFilesScript = { targetFiles, out }: ''
  ( OUT=$(realpath ${out})
    cd ${otaTools}; # Enter otaTools dir so relative paths are correct for finding original keys
    ${otaTools}/releasetools/sign_target_files_apks.py \
      -o ${toString config.signing.signTargetFilesArgs} \
      ${targetFiles} $OUT
  )
  '';
  otaScript = { targetFiles, prevTargetFiles ? null, out }: ''
    ${otaTools}/releasetools/ota_from_target_files.py  \
      ${toString config.otaArgs} \
      ${lib.optionalString (prevTargetFiles != null) "-i ${prevTargetFiles}"} \
      ${targetFiles} ${out}
  '';
  imgScript = { targetFiles, out }: ''${otaTools}/releasetools/img_from_target_files.py ${targetFiles} ${out}'';
  factoryImgScript = { targetFiles, img, out }: ''
      ln -s ${targetFiles} ${config.device}-target_files-${config.buildNumber}.zip || true
      ln -s ${img} ${config.device}-img-${config.buildNumber}.zip || true

      export DEVICE=${config.device}
      export PRODUCT=${config.device}
      export BUILD=${config.buildNumber}
      export VERSION=${lib.toLower config.buildNumber}

      get_radio_image() {
        ${lib.getBin pkgs.unzip}/bin/unzip -p ${targetFiles} OTA/android-info.txt  \
          |  grep -Po "require version-$1=\K.+" | tr '[:upper:]' '[:lower:]'
      }
      export BOOTLOADER=$(get_radio_image bootloader google_devices/$DEVICE)
      export RADIO=$(get_radio_image baseband google_devices/$DEVICE)

      export PATH=${lib.getBin pkgs.zip}/bin:${lib.getBin pkgs.unzip}/bin:$PATH
      ${pkgs.runtimeShell} ${config.source.dirs."device/common".src}/generate-factory-images-common.sh
      mv *-factory-*.zip ${out}
  '';
in
{
  options = {
    channel = mkOption {
      default = "stable";
      type = types.enum [ "stable" "beta" ];
      description = "Default channel to use for updates (can be modified in app)";
    };

    incremental = mkOption {
      default = false;
      type = types.bool;
      description = "Whether to include an incremental build in `otaDir` output";
    };

    retrofit = mkOption {
      default = false;
      type = types.bool;
      description = ''
        Generate a retrofit OTA for upgrading a device without dynamic partitions.
        See also https://source.android.com/devices/tech/ota/dynamic_partitions/ab_legacy#generating-update-packages
      '';
    };

    otaArgs = mkOption {
      default = [];
      type = types.listOf types.str;
      internal = true;
    };

    # Build products. Put here for convenience--but it's not a great interface
    prevBuildDir = mkOption { type = types.str; internal = true; };
    prevBuildNumber = mkOption { type = types.str; internal = true; };
    prevTargetFiles = mkOption { type = types.path; internal = true; };
  };

  config = {
    prevBuildNumber = let
        metadata = builtins.readFile (config.prevBuildDir + "/${config.device}-${config.channel}");
      in mkDefault (lib.head (lib.splitString " " metadata));
    prevTargetFiles = mkDefault (config.prevBuildDir + "/${config.device}-target_files-${config.prevBuildNumber}.zip");

    otaArgs =
      [ "--block" ]
      ++ lib.optional config.retrofit "--retrofit_dynamic_partitions";
  };

  config.build = rec {
    # These can be used to build these products inside nix. Requires putting the secret keys under /keys in the sandbox
    unsignedTargetFiles = config.build.android + "/${config.productName}-target_files-${config.buildNumber}.zip";
    signedTargetFiles = runWrappedCommand "signed_target_files" signedTargetFilesScript { targetFiles=unsignedTargetFiles;};
    targetFiles = if config.signing.enable then signedTargetFiles else unsignedTargetFiles;
    ota = runWrappedCommand "ota_update" otaScript { inherit targetFiles; };
    incrementalOta = runWrappedCommand "incremental-${config.prevBuildNumber}" otaScript { inherit targetFiles; inherit (config) prevTargetFiles; };
    img = runWrappedCommand "img" imgScript { inherit targetFiles; };
    factoryImg = runWrappedCommand "factory" factoryImgScript { inherit targetFiles img; };

    # Pull this out of target files, because (at least) verity key gets put into boot ramdisk
    bootImg = pkgs.runCommand "boot.img" {} "${pkgs.unzip}/bin/unzip -p ${targetFiles} IMAGES/boot.img > $out";

    # BUILDID_PLACEHOLDER below was originally config.apv.buildID, but we don't want to have to depend on setting a buildID generally.
    otaMetadata = (rec {
      grapheneos = pkgs.writeText "${config.device}-${config.channel}" ''
        ${config.buildNumber} ${toString config.buildDateTime} BUILDID_PLACEHOLDER ${config.channel}
      '';
      lineageos = pkgs.writeText "${config.device}.json" (
        # https://github.com/LineageOS/android_packages_apps_Updater#server-requirements
        builtins.toJSON {
          response = [
            {
              "datetime" = config.buildDateTime;
              "filename" = ota.name;
              "id" = config.buildNumber;
              "romtype" = config.envVars.RELEASE_TYPE;
              "size" = "ROM_SIZE";
              "url" = "${config.apps.updater.url}${ota.name}";
              "version" = config.flavorVersion;
            }
          ];
        }
      );
    }).${config.apps.updater.flavor};

    writeOtaMetadata = path: {
      grapheneos = ''
        cat ${otaMetadata} > ${path}/${config.device}-${config.channel}
      '';
      lineageos = ''
        sed -e "s:\"ROM_SIZE\":$(du -b ${ota} | cut -f1):" ${otaMetadata} > ${path}/${config.device}.json
      '';
    }.${config.apps.updater.flavor};

    # TODO: target-files aren't necessary to publish--but are useful to include if prevBuildDir is set to otaDir output
    otaDir = pkgs.runCommand "${config.device}-otaDir" {} ''
      mkdir -p $out
      ln -s "${ota}" "$out/${ota.name}"
      ln -s "${targetFiles}" "$out/${config.device}-target_files-${config.buildNumber}.zip"
      ${lib.optionalString config.incremental ''ln -s ${incrementalOta} "$out/${incrementalOta.name}"''}

      ${writeOtaMetadata (placeholder "out")}
    '';

    # TODO: Do this in a temporary directory. It's ugly to make build dir and ./tmp/* dir gets cleared in these scripts too.
    releaseScript =
      (if (!config.signing.enable) then lib.warn "releaseScript should be used only if signing.enable = true; Otherwise, the build might be using incorrect keys / certificate metadata" else lib.id)
      pkgs.writeShellScript "release.sh" (''
      set -euo pipefail

      if [[ $# -ge 2 ]]; then
        PREV_BUILDNUMBER="$2"
      else
        PREV_BUILDNUMBER=""
      fi
      '' + (wrapScript { keysDir="$1"; commands=''
      echo Signing target files
      ${signedTargetFilesScript { targetFiles=unsignedTargetFiles; out=signedTargetFiles.name; }}
      echo Building OTA zip
      ${otaScript { targetFiles=signedTargetFiles.name; out=ota.name; }}
      if [[ ! -z "$PREV_BUILDNUMBER" ]]; then
        echo Building incremental OTA zip
        ${otaScript {
          targetFiles=signedTargetFiles.name;
          prevTargetFiles="${config.device}-target_files-$PREV_BUILDNUMBER.zip";
          out="${config.device}-incremental-$PREV_BUILDNUMBER-${config.buildNumber}.zip";
        }}
      fi
      echo Building .img file
      ${imgScript { targetFiles=signedTargetFiles.name; out=img.name; }}
      echo Building factory image
      ${factoryImgScript { targetFiles=signedTargetFiles.name; img=img.name; out=factoryImg.name; }}
      echo Writing updater metadata
      ${writeOtaMetadata "."}
    ''; }));
  };
}
