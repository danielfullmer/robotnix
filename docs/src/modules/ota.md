# Over-the-Air (OTA) Updater

The following robotnix configuration enables the [OTA updater app](https://github.com/GrapheneOS/platform_packages_apps_Updater).
```nix
{
    apps.updater.enable = true;
    apps.updater.url = "...";
}
```
The `apps.updater.url` setting needs to point to a URL hosting the OTA files described below.

Additionally, the `buildDateTime` option is set by default by the flavor, and is updated when those flavors have new releases.
If you make new changes to your build that you want to be pushed by the OTA updater, you should set `buildDateTime` yourself, using `date "+%s"` to get the current time.

## Building OTA updates

The OTA file and metadata can be generated as part of the `releaseScript`
output.  If you are signing builds inside Nix using the sandbox exception,
robotnix additionally includes a convenient target which will build a directory
containing OTA files ready to be sideloaded or served over the web.  To
generate the OTA directory, build the `otaDir` attribute (here for sunfish):
```console
$ nix-build --arg configuration ./sunfish.nix -A otaDir -o ota-dir
```
The directory structure will look similar to this (arrows indicate symbolic
links) with possibly different timestamps and hashes of course:
```console
$ tree -l ota-dir
├── sunfish-ota_update-2021.02.06.16.zip -> /nix/store/wwr49all6x868f0mdl11369ybfwyir0f-sunfish-ota_update-2021.02.06.16.zip
├── sunfish-stable -> /nix/store/c1rp46m9spncanacglqs5mxk6znfs44s-sunfish-stable
└── sunfish-target_files-2021.02.06.16.zip -> /nix/store/8ys21rzjqhi2055d7bd4iwa15fv1m446-sunfish-signed_target_files-2021.02.06.16.zip
```
The file `sunfish-ota_update-2021.02.06.16.zip` can be sideloaded with adb as
described in the next section.

## Actually serving OTA updates over the air

> *Note:* The Vanilla and GrapheneOS flavors use a different updater than the LineageOS flavor,
> therefore they might behave slightly different from one another.
> The instructions below should however work for both.

Essentially this boils down to just serving the `otaDir` build output on the
web, e.g. with nginx.  To receive OTA updates on the device, enable the updater
and point it to the domain and possibly subdirectory that you will be serving
OTA updates from:
```nix
# Device configuration
{
  apps = {
    updater.enable = true;
    updater.url = "https://example.com/android/";
  };
}
```
On a NixOS server, it is as easy as serving a directory at the required
endpoint:
```nix
# NixOS server configuration
{
  services.nginx.enable = true;
  systemd.services.nginx.serviceConfig.ReadOnlyPaths = [ "/var/www" ];
  services.nginx.virtualHosts."example.com" = {
    forceSSL = true;
    enableACME = true;
    locations."/android/" = {
      root = "/var/www";
      tryFiles = "$uri $uri/ =404";
    };
  };
}
```
The directory simply contains symlinks to the store paths that were contained in
the `otaDir` output that was built earlier.  I choose to just copy the result
symlink to `/var/www/android`.  It is recommended to use a symlink or `mv`
operation to expose the `otaDir` to the web server, since (if you are
copying/uploading slowly) the OTA updater app on your phone might start
updating before the copy/upload is complete.
```console
$ cp --no-dereference ota-dir /var/www/android
$ tree -l /var/www
/var/www
└── android -> /nix/store/dbjcl9lwn6xif9c0fy8d2wwpn9zi4hw4-sunfish-otaDir
    ├── sunfish-ota_update-2021.02.06.16.zip -> /nix/store/wwr49all6x868f0mdl11369ybfwyir0f-sunfish-ota_update-2021.02.06.16.zip
    ├── sunfish-stable -> /nix/store/c1rp46m9spncanacglqs5mxk6znfs44s-sunfish-stable
    └── sunfish-target_files-2021.02.06.16.zip -> /nix/store/8ys21rzjqhi2055d7bd4iwa15fv1m446-sunfish-signed_target_files-2021.02.06.16.zip
```
Of course, this doesn't have to be located at `/var/www` and it's totally
possible to integrate updating of the OTA directory into your other robotnix
build automation.  In this case it is as easy as updating the `/var/www/android`
symlink with the new build output.

Here it was assumed that robotnix was built on the same machine that you will
serve the OTA from.  If that is not the case you can conveniently copy the
closure to a remote host using `nix copy` as in
``` console
$ nix copy --to ssh://user@example.com ./ota-dir
```
Don't forget to add the store path of the `ota-dir` as a garbage collector root
on the remote machine or it might be collected in the next sweep.
