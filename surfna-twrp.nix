# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:

{
  device = "surfna";
  flavor = "twrp";
  source.dirs = {
    "device/motorola/surfna" = {
      src = builtins.fetchGit ~/tmp/TWRP/android_device_motorola_surfna;
    };
  };
}
