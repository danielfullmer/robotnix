self: super: {
  android-emulator = super.callPackage ./android-emulator {};

  android-prepare-vendor = super.callPackage ./android-prepare-vendor {};

  bundletool = super.callPackage ./bundletool {};

  diffoscope = (super.diffoscope.overrideAttrs (attrs: rec {
    patches = attrs.patches ++ [
      ./diffoscope/0001-comparators-android-Support-sparse-android-images.patch
    ];
    pythonPath = attrs.pythonPath ++ [ super.simg2img super.zip ];
    doCheck = false;
    doInstallCheck = false;
  })).override {
    python3Packages = super.python3Packages.override {
      overrides = pythonSelf: pythonSuper: {
        guestfs = pythonSuper.guestfs.override { libguestfs = super.libguestfs-with-appliance; };
      };
    };
    binutils-unwrapped = super.pkgsCross.aarch64-multiplatform.buildPackages.binutils-unwrapped;
    enableBloat = true;
  };

  cipd = super.callPackage ./cipd {};
  fetchcipd = super.callPackage ./cipd/fetchcipd.nix {};

  fetchgerritpatchset = super.callPackage ./fetchgerritpatchset {};

  fetchgit = super.callPackage ./fetchgit {};
  nix-prefetch-git = super.callPackage ./fetchgit/nix-prefetch-git.nix {};

  ###

  # Robotnix helper derivations
  robotnix = super.callPackage ./robotnix {};
}
