# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

let
  inherit (lib) mkIf mkOption mkMerge mkEnableOption types;

  cfg = config.services.attestation-server;
  supportedDevices = import ../../apks/auditor/supported-devices.nix;
  attestation-server = pkgs.callPackage ./default.nix {};
in
{
  options.services.attestation-server = {
    enable = mkEnableOption "Hardware-based remote attestation service for monitoring the security of Android devices using the Auditor app";

    domain = mkOption {
      type = types.str;
    };

    listenHost = mkOption {
      default = "127.0.0.1";
      type = types.str;
    };

    port = mkOption {
      default = 8085;
      type = types.int;
    };

    signatureFingerprint = mkOption {
      type = types.str;
    };

    device = mkOption {
      default = "";
      type = types.str;
    };

    avbFingerprint = mkOption {
      default = "";
      type = types.str;
    };

    package = mkOption {
      default = attestation-server.override {
        inherit (cfg) listenHost port domain signatureFingerprint device avbFingerprint;
      };
      type = types.path;
    };

    disableAccountCreation = mkOption {
      default = false;
      type = types.bool;
    };

    email = {
      username = mkOption {
        default = "";
        type = types.str;
      };

      passwordFile = mkOption {
        default = null;
        type = types.nullOr types.str;
      };

      host = mkOption {
        default = "";
        type = types.str;
      };

      port = mkOption {
        default = 465;
        type = types.int;
        description = ''
          Port to connect to for sending email. Must support "implicit TLS" / SMTPS, which defaults to port 465.
          STARTTLS is deliberately not supported: https://github.com/GrapheneOS/AttestationServer#email-alert-configuration
        '';
      };

      local = mkOption {
        default = false;
        type = types.bool;
      };
    };

    nginx.enable = mkOption {
      default = true;
      type = types.bool;
    };

    nginx.enableACME = mkOption {
      default = false;
      type = types.bool;
    };
  };

  config = mkIf cfg.enable {
    assertions = [ {
      assertion = builtins.elem cfg.device supportedDevices;
      message = "Device ${cfg.device} is currently unsupported for use with attestation server.";
    } ];

    systemd.services.attestation-server = {
      description = "Attestation Server";
      wantedBy = [ "multi-user.target" ];
      requires = [ "network-online.target" ];

      serviceConfig = (lib.optionalAttrs (cfg.email.passwordFile != null) {
        LoadCredential = "AttestationServerEmailPassword:${cfg.email.passwordFile}";
      }) // {
        ExecStart = "${cfg.package}/bin/AttestationServer";
        ExecStartPre = let
          inherit (cfg.email) username passwordFile host port local;
          # In SQLite readfile reads a file as a BLOB which is not very useful.
          # However, we can use TRIM to convert it to a string and we have to
          # truncate the trailing newline (\n = char(10)) anyway.
          values = lib.concatStringsSep ", " [
            "('emailUsername', '${username}')"
            "('emailPassword', TRIM(readfile('$CREDENTIALS_DIRECTORY/AttestationServerEmailPassword'), char(10)))"
            "('emailHost', '${host}')"
            "('emailPort', '${toString port}')"
            "('emailLocal', '${if local then "1" else "0"}')"
          ];
        in lib.optionals (passwordFile != null) [
          # Note the leading + on the first command. The passwordFile could be
          # anywhere in the file system, so it has to be copied as root and
          # permissions fixed to be accessible by the service.
          ''${pkgs.sqlite}/bin/sqlite3 %S/attestation/attestation.db "CREATE TABLE IF NOT EXISTS Configuration (key TEXT PRIMARY KEY NOT NULL, value NOT NULL)"''
          ''${pkgs.sqlite}/bin/sqlite3 %S/attestation/attestation.db "INSERT OR REPLACE INTO Configuration VALUES ${values}"''
        ];

        # When sending TERM, e.g. for restart, AttestationServer fails with
        # this exit code.
        SuccessExitStatus = [ 143 ];

        DynamicUser = true;
        StateDirectory = "attestation";
        WorkingDirectory = "%S/attestation";

        # See attestation.service in upstream repository
        CapabilityBoundingSet = "";
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateIPC = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = "AF_INET AF_INET6";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged @resources"
        ];
      };
    };

    services.nginx = mkIf cfg.nginx.enable {
      enable = true;
      virtualHosts."${config.services.attestation-server.domain}" = lib.recursiveUpdate {
        locations."/".root = cfg.package.static;
        locations."/api/".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/api/";
        locations."/challenge".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/challenge";
        locations."/verify".proxyPass = "http://${cfg.listenHost}:${toString cfg.port}/verify";
        forceSSL = true;
        enableACME = cfg.nginx.enableACME;
      } (lib.optionalAttrs cfg.disableAccountCreation {
        locations."/api/create_account".return = "403";
      });
    };
  };
}
