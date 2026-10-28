{lib, ...}: let
  # converts a list of `mountOption` to a comma-separated string that is passed to the mount unit
  toOptionsString = mountOptions:
    builtins.concatStringsSep "," (
      map (
        option:
          if option.value == null
          then option.name
          else "${option.name}=${option.value}"
      )
      mountOptions
    );

  # concatenates two paths
  # inserts a "/" in between if there is none, removes one if there are two
  concatTwoPaths = parent: child:
    with lib.strings;
      if hasSuffix "/" parent
      then
        if hasPrefix "/" child
        # "/parent/" "/child"
        then parent + (removePrefix "/" child)
        # "/parent/" "child"
        else parent + child
      else if hasPrefix "/" child
      # "/parent" "/child"
      then parent + child
      # "/parent" "child"
      else parent + "/" + child;

  # concatenates a list of paths using `concatTwoPaths`
  concatPaths = builtins.foldl' concatTwoPaths "";

  # get the parent dir of an absolute path
  parentDir = path:
    with lib.strings;
    assert "/" == (builtins.substring 0 1 path); let
      parts = splitString "/" (removeSuffix "/" path);
      len = builtins.length parts;
    in
      if len < 1
      then "/"
      else concatPaths (["/"] ++ (lib.lists.sublist 0 (len - 1) parts));

  # splits a path on "/", returning a list of non-empty path components
  parts = path:
    builtins.foldl' (acc: p:
      if builtins.isString p && p != ""
      then acc ++ [p]
      else acc) [] (
      builtins.split "/" path
    );

  # generates a list of path segments that are parents of the given path
  # e.g.: for "/foo/bar/baz" this yields [ "foo" "foo/bar" ]
  parentSegments = path: let
    # collect all path segments, including the given path itself
    includingPath = builtins.foldl' (
      acc: part:
        if acc == []
        then [part]
        else ([(concatTwoPaths (builtins.head acc) part)] ++ acc)
    ) [] (parts path);
    # return all path segments except for the given path
  in
    builtins.tail includingPath;

  # generates a list of unique path segments that are parents of a given list of paths
  missingScaffoldPaths = paths: let
    segments = builtins.foldl' (acc: path: acc ++ (parentSegments path)) [] paths;
  in
    lib.lists.unique (builtins.filter (path: !(builtins.elem path paths)) segments);

  # filters a list of files or dirs by method and initrd placement
  onlyMethod = method: forInitrd: builtins.filter (conf: conf.method == method && conf.inInitrd == forInitrd);
  # filters a list of files or dirs, returns only bindmounts
  onlyBindMounts = onlyMethod "bindmount";
  # filters a list of files or dirs, returns only symlinks
  onlySymLinks = onlyMethod "symlink";
  # filters a list of dirs, returns only generated scaffolds
  onlyScaffolds = forInitrd: builtins.filter (d: d.scaffold && d.inInitrd == forInitrd);
  # filters a list of dirs, returns only the ones preserved themselves
  onlyPreserved = builtins.filter (d: !d.scaffold);

  # in user mode, strips the home dir prefix so the path is relative to keepConfig.path
  adjustPersistentPath = keepConfig: path:
    if keepConfig.username == "root"
    then path
    else lib.removePrefix keepConfig.home path;

  # resolves a preserved path to its storage locations, prefixed for the current
  # context ("/sysroot" in the initrd, "/" otherwise):
  # - persistent: where the state lives on persistent storage
  # - volatile: where the state lives in the running system
  # - link: target of a symlink pointing at the state (without the context prefix)
  resolvePaths = prefix: keepConfig: path: let
    adjusted = adjustPersistentPath keepConfig path;
  in {
    persistent = concatPaths [
      prefix
      keepConfig.path
      adjusted
    ];
    volatile = concatPaths [
      prefix
      path
    ];
    link = concatPaths [
      keepConfig.path
      adjusted
    ];
  };

  # generates a list of attributes to be used in the `dirs` option
  #
  # essentially this takes the given lists of configurations for `dirs` and `files`,
  # generates a list of all their unique parent paths and returns a single list of the
  # given configurations extended by scaffold entries for their parents, using `defaults`
  mkScaffoldDirs = defaults: files: prefix: dirs: let
    # partition returns { right, wrong } with `right` holding the entries
    # matching the predicate, i.e. all entries prepared for the initrd
    partitions = builtins.partition (d: d.inInitrd) (files ++ dirs);
    toPaths = map (d:
      if builtins.hasAttr "file" d
      then lib.removePrefix prefix d.file
      else d.dir);
    mkScaffolds = inInitrd:
      map (
        p:
          defaults
          // {
            inherit inInitrd;
            dir = p;
          }
      ) (missingScaffoldPaths (toPaths (
        if inInitrd
        then partitions.right
        else partitions.wrong
      )));
  in
    dirs ++ mkScaffolds true ++ mkScaffolds false;

  # creates tmpfiles.d rules for the `settings` option of the tmpfiles module from a `keepTo` entry
  mkTmpfilesRules = forInitrd: keepConfig: let
    prefix =
      if forInitrd
      then "/sysroot"
      else "/";
    paths = resolvePaths prefix keepConfig;
    # dirs preserved by this module, and the generated scaffolds
    dirs = onlyPreserved keepConfig.dirs;
    scaffolds = onlyScaffolds forInitrd keepConfig.dirs;

    # rules for a dir that is preserved itself, or created as a
    # scaffold (scaffold entries never have parent.enable set)
    mkDirRules = dirConfig: let
      storage = paths dirConfig.dir;
    in
      {
        # dir on persistent storage
        "${storage.persistent}".d = {
          inherit (dirConfig) user group mode;
        };
        # dir on volatile storage
        "${storage.volatile}".d = {
          inherit (dirConfig) user group mode;
        };
      }
      // lib.optionalAttrs dirConfig.parent.enable {
        # parent dir on persistent storage
        "${parentDir storage.persistent}".d = {
          inherit (dirConfig.parent) user group mode;
        };
        # parent dir on volatile storage
        "${parentDir storage.volatile}".d = {
          inherit (dirConfig.parent) user group mode;
        };
      };

    # rules for a file that is preserved itself
    mkFileRules = fileConfig: let
      storage = paths fileConfig.file;
    in
      {
        # file on persistent storage
        "${storage.persistent}".f = {
          inherit (fileConfig) user group mode;
        };
        # file on volatile storage
        "${storage.volatile}".f = {
          inherit (fileConfig) user group mode;
        };
      }
      // lib.optionalAttrs fileConfig.parent.enable {
        # parent dir on persistent storage
        "${parentDir storage.persistent}".d = {
          inherit (fileConfig.parent) user group mode;
        };
        # parent dir on volatile storage
        "${parentDir storage.volatile}".d = {
          inherit (fileConfig.parent) user group mode;
        };
      };

    # rules for a symlink on the volatile side pointing at the preserved dir
    mkSymlinkDirRules = dirConfig: let
      storage = paths dirConfig.dir;
    in
      {
        # symlink on volatile storage
        "${storage.volatile}".L = {
          inherit (dirConfig) user group mode;
          argument = storage.link;
        };
      }
      // lib.optionalAttrs dirConfig.mkTarget {
        # dir on persistent storage
        "${storage.persistent}".d = {
          inherit (dirConfig) user group mode;
        };
      }
      // lib.optionalAttrs dirConfig.parent.enable {
        # parent dir on persistent storage
        "${parentDir storage.persistent}".d = {
          inherit (dirConfig.parent) user group mode;
        };
        # parent dir on volatile storage
        "${parentDir storage.volatile}".d = {
          inherit (dirConfig.parent) user group mode;
        };
      };

    # rules for a symlink on the volatile side pointing at the preserved file
    mkSymlinkFileRules = fileConfig: let
      storage = paths fileConfig.file;
    in
      {
        # symlink on volatile storage
        "${storage.volatile}".L = {
          inherit (fileConfig) user group mode;
          argument = storage.link;
        };
      }
      // lib.optionalAttrs fileConfig.mkTarget {
        # file on persistent storage
        "${storage.persistent}".f = {
          inherit (fileConfig) user group mode;
        };
      }
      // lib.optionalAttrs fileConfig.parent.enable {
        # parent dir on persistent storage
        "${parentDir storage.persistent}".d = {
          inherit (fileConfig.parent) user group mode;
        };
        # parent dir on volatile storage
        "${parentDir storage.volatile}".d = {
          inherit (fileConfig.parent) user group mode;
        };
      };
  in
    map mkDirRules (onlyBindMounts forInitrd dirs ++ scaffolds)
    ++ map mkSymlinkDirRules (onlySymLinks forInitrd dirs)
    ++ map mkFileRules (onlyBindMounts forInitrd keepConfig.files)
    ++ map mkSymlinkFileRules (onlySymLinks forInitrd keepConfig.files);

  # creates systemd mount unit configurations from a `keepTo` entry
  mkMountUnits = forInitrd: keepConfig: let
    prefix =
      if forInitrd
      then "/sysroot"
      else "/";
    paths = resolvePaths prefix keepConfig;
    # dirs preserved by this module, excluding the generated scaffolds
    dirs = onlyPreserved keepConfig.dirs;

    # the mount options of an entry as a comma-separated string
    optionsOf = mountOptions:
      toOptionsString (
        mountOptions
        ++ (lib.optional forInitrd {
          name = "x-initrd.mount";
          value = null;
        })
      );

    wantedBy =
      if forInitrd
      then ["initrd-keep.target"]
      else ["keep.target"];
    tmpfilesSetup =
      if forInitrd
      then "systemd-tmpfiles-setup-sysroot.service"
      else "systemd-tmpfiles-setup.service";

    mkDirMount = dirConfig: let
      storage = paths dirConfig.dir;
    in {
      options = optionsOf dirConfig.mountOptions;
      where = storage.volatile;
      what = storage.persistent;
      unitConfig.DefaultDependencies = "no";
      conflicts = ["umount.target"];
      inherit wantedBy;
      before =
        [
          # dir mounts are set up before tmpfiles
          tmpfilesSetup
        ]
        ++ wantedBy;
    };

    mkFileMount = fileConfig: let
      storage = paths fileConfig.file;
    in {
      options = optionsOf fileConfig.mountOptions;
      where = storage.volatile;
      what = storage.persistent;
      unitConfig = {
        DefaultDependencies = "no";
        ConditionPathExists = storage.persistent;
      };
      conflicts = ["umount.target"];
      after = [tmpfilesSetup];
      inherit wantedBy;
      before = wantedBy;
    };
  in
    map mkDirMount (onlyBindMounts forInitrd dirs)
    ++ map mkFileMount (onlyBindMounts forInitrd keepConfig.files);
in {
  inherit concatTwoPaths mkScaffoldDirs;

  # aliases to avoid the use of a nameless bool outside this lib
  mkRegularMountUnits = mkMountUnits false;
  mkInitrdMountUnits = mkMountUnits true;
  mkRegularTmpfilesRules = mkTmpfilesRules false;
  mkInitrdTmpfilesRules = mkTmpfilesRules true;
}
