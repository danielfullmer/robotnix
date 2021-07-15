{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";
  };

  outputs = { self, nixpkgs, androidPkgs, ... }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux.appendOverlays [
        (self: super: {
          androidPkgs.sdk = androidPkgs.sdk.x86_64-linux;
        })
        (import ./pkgs/overlay.nix)
      ];
  in {
    # robotnixSystem evaluates a robotnix configuration
    lib.robotnixSystem = configuration: import ./default.nix {
      inherit configuration pkgs;
    };

    defaultTemplate = {
      path = ./template;
      description = "A basic robotnix configuration";
    };

    nixosModule = import ./nixos; # Contains all robotnix nixos modules
    nixosModules.attestation-server = import ./nixos/attestation-server/module.nix;

    checks.x86_64-linux = {};

    packages.x86_64-linux = {
      manual = (import ./docs { inherit pkgs; }).manual;
    };

    devShell.x86_64-linux = import ./shell.nix { inherit pkgs; };
  };
}
