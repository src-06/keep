{
  config,
  lib,
  ...
}: let
  inherit
    (import ./lib.nix {inherit lib;})
    mkRegularMountUnits
    mkInitrdMountUnits
    mkRegularTmpfilesRules
    mkInitrdTmpfilesRules
    ;

  # entries that contain something to preserve; the module is active only if there is at least one
  enabled = lib.filterAttrs (_: entry: entry.dirs != [] || entry.files != []) config.keepTo;
  # concatenate the results (lists of rules / units) of applying `f` to every enabled entry
  perEntry = f: lib.concatLists (lib.mapAttrsToList (_: entry: f entry) enabled);
  # merge the concatenated tmpfiles rule sets of every enabled entry
  mergedPerEntry = f: lib.mkMerge (perEntry f);
in {
  imports = [
    ./options.nix
  ];

  config = lib.mkIf (enabled != {}) {
    boot.initrd.systemd = {
      targets.initrd-keep = {
        description = "Initrd Keep Mounts";
        before = ["initrd.target"];
        wantedBy = ["initrd.target"];
      };
      tmpfiles.settings.keep = mergedPerEntry mkInitrdTmpfilesRules;
      mounts = perEntry mkInitrdMountUnits;
    };

    systemd = {
      targets.keep = {
        description = "Keep Mounts";
        before = ["sysinit.target"];
        wantedBy = ["sysinit.target"];
      };
      tmpfiles.settings.keep = mergedPerEntry mkRegularTmpfilesRules;
      mounts = perEntry mkRegularMountUnits;
    };
  };
}
