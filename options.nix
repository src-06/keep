{
  config,
  lib,
  ...
}: let
  inherit
    (import ./lib.nix {inherit lib;})
    mkScaffoldDirs
    concatTwoPaths
    ;

  nixosConfig = config;

  mountOption = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = ''
          Specify the name of the mount option.
        '';
        example = "bind";
      };
      value = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          Optionally specify a value for the mount option.
        '';
      };
    };
  };

  dirPath = attrs @ {
    defaultOwner,
    account,
    ...
  }: {
    options = {
      dir = lib.mkOption {
        type = lib.types.str;
        description = ''
          Specify the path to the dir that should be preserved.
        '';
      };
      method = lib.mkOption {
        type = lib.types.enum [
          "bindmount"
          "symlink"
        ];
        default = "bindmount";
        description = ''
          Specify how this dir should be preserved.

          1. Either a dir is created both on the volatile and on the
          persistent volume, with a bind mount from the former to the
          latter.

          2. Or a symlink is created on the volatile volume, pointing
          to the corresponding location on the persistent volume.
        '';
      };
      scaffold = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
        description = ''
          Internal marker for generated scaffold entries: dirs that
          are created on both volumes so that preserved paths around them
          exist, but without being preserved themselves.
        '';
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = defaultOwner;
        description = ''
          Specify the user that owns the dir.
        '';
      };
      group = lib.mkOption {
        type = lib.types.str;
        default = account.group;
        defaultText = lib.literalExpression "config.users.users.\${defaultOwner}.group";
        description = ''
          Specify the group that owns the dir.
        '';
      };
      mode = lib.mkOption {
        type = lib.types.str;
        default = "0755";
        description = ''
          Specify the access mode of the dir.
          See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
        '';
      };
      parent = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = let
            isUserMode = defaultOwner != "root";
            notOnTopLevel = !isNull (builtins.match ".+/.*" attrs.config.dir);
          in
            isUserMode && notOnTopLevel;
          description = ''
            Specify whether the parent dir of this dir shall be configured with
            custom ownership and permissions.

            By default, missing parent dirs are always created with ownership
            `root:root` and mode `0755`, as described in {manpage}`tmpfiles.d(5)`.

            Ownership and mode may be configured through the options
            {option}`parent.user`,
            {option}`parent.group`,
            {option}`parent.mode`.

            Defaults to `true` when {option}`username` is not `root` and the path
            has a parent dir (is not a top-level path).
          '';
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = attrs.config.user;
          defaultText = lib.literalExpression "config.user";
          description = ''
            Specify the user that owns the parent dir of this dir.
            Defaults to {option}`user` of this entry.
          '';
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = attrs.config.group;
          defaultText = lib.literalExpression "config.group";
          description = ''
            Specify the group that owns the parent dir of this dir.
            Defaults to {option}`group` of this entry.
          '';
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = attrs.config.mode;
          defaultText = lib.literalExpression "config.mode";
          description = ''
            Specify the access mode of the parent dir of this dir.
            Defaults to {option}`mode` of this entry.
            See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
          '';
        };
      };
      mountOptions = lib.mkOption {
        type = with lib.types; listOf (coercedTo str (n: {name = n;}) mountOption);
        description = ''
          Specify a list of mount options that should be used for this dir.
          These options are only used when {option}`method` is set to `bindmount`.
          By default, `bind` and `X-fstrim.notrim` are added,
          use `mkForce` to override these if needed.
          See also {manpage}`fstrim(8)`.
        '';
      };
      mkTarget = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Only used when {option}`method` is set to `symlink`.

          Specify whether to create an empty dir with the specified ownership
          and permissions as target of the symlink.
        '';
      };
      inInitrd = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to prepare preservation of this dir in initrd.

          ::: {.note}
          For most dirs there is no need to enable this option.
          :::

          ::: {.important}
          Note that both owner and group for this dir need to be
          available in the initrd for permissions to be set correctly.
          :::
        '';
      };
    };

    config = {
      mountOptions = [
        "bind"
        "X-fstrim.notrim"
      ];
    };
  };

  filePath = attrs @ {
    defaultOwner,
    account,
    ...
  }: {
    options = {
      file = lib.mkOption {
        type = lib.types.str;
        description = ''
          Specify the path to the file that should be preserved.
        '';
      };
      method = lib.mkOption {
        type = lib.types.enum [
          "bindmount"
          "symlink"
        ];
        default = "bindmount";
        description = ''
          Specify how this file should be preserved:

          1. Either a file is placed both on the volatile and on the
          persistent volume, with a bind mount from the former to the
          latter.

          2. Or a symlink is created on the volatile volume, pointing
          to the corresponding location on the persistent volume.
        '';
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = defaultOwner;
        description = ''
          Specify the user that owns the file.
        '';
      };
      group = lib.mkOption {
        type = lib.types.str;
        default = account.group;
        defaultText = lib.literalExpression "config.users.users.\${defaultOwner}.group";
        description = ''
          Specify the group that owns the file.
        '';
      };
      mode = lib.mkOption {
        type = lib.types.str;
        default = "0644";
        description = ''
          Specify the access mode of the file.
          See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
        '';
      };
      parent = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = let
            isUserMode = defaultOwner != "root";
            notOnTopLevel = !isNull (builtins.match ".+/.*" attrs.config.file);
          in
            isUserMode && notOnTopLevel;
          description = ''
            Specify whether the parent dir of this file shall be configured with
            custom ownership and permissions.

            By default, missing parent dirs are always created with ownership
            `root:root` and mode `0755`, as described in {manpage}`tmpfiles.d(5)`.

            Ownership and mode may be configured through the options
            {option}`parent.user`,
            {option}`parent.group`,
            {option}`parent.mode`.

            Defaults to `true` when {option}`username` is not `root` and the path
            has a parent dir (is not a top-level path).
          '';
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = attrs.config.user;
          defaultText = lib.literalExpression "config.user";
          description = ''
            Specify the user that owns the parent dir of this file.
            Defaults to {option}`user` of this entry.
          '';
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = attrs.config.group;
          defaultText = lib.literalExpression "config.group";
          description = ''
            Specify the group that owns the parent dir of this file.
            Defaults to {option}`group` of this entry.
          '';
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0755";
          description = ''
            Specify the access mode of the parent dir of this file.
            Unlike dir parents, this does not default to {option}`mode`
            of this entry: a file's mode (e.g. `0644`) would make its parent
            dir untraversable.
            See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
          '';
        };
      };
      mountOptions = lib.mkOption {
        type = with lib.types; listOf (coercedTo str (o: {name = o;}) mountOption);
        description = ''
          Specify a list of mount options that should be used for this file.
          These options are only used when {option}`method` is set to `bindmount`.
          By default, `bind` is added,
          use `mkForce` to override this if needed.
        '';
      };
      mkTarget = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Only used when {option}`method` is set to `symlink`.

          Specify whether to create an empty file with the specified ownership
          and permissions as target of the symlink.
        '';
      };
      inInitrd = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to prepare preservation of this file in the initrd.

          ::: {.note}
          For most files there is no need to enable this option.

          {file}`/etc/machine-id` is an exception because it needs to
          be populated/read very early.
          :::

          ::: {.important}
          Note that both owner and group for this file need to be
          available in the initrd for permissions to be set correctly.
          :::
        '';
      };
    };

    config = {
      mountOptions = [
        "bind"
      ];
    };
  };
in {
  options.keepTo = lib.mkOption {
    type = with lib.types;
      attrsOf (submodule (
        {
          name,
          config,
          ...
        }: let
          account = nixosConfig.users.users.${config.username};
        in {
          options = {
            path = lib.mkOption {
              type = lib.types.path;
              default = name;
              defaultText = lib.literalExpression "<attribute name>";
              internal = true;
              readOnly = true;
              description = ''
                The persistent storage root for this config. Always identical
                to the attribute name under which the entry is configured.
              '';
            };

            username = lib.mkOption {
              type = with lib.types; passwdEntry str;
              default = "root";
              description = ''
                Specify the user for which {option}`dirs` and {option}`files` are preserved.

                The default `root` configures system-level preservation: paths are
                interpreted as absolute paths and ownership defaults to `root`.

                When set to any other user, paths are interpreted relative to that
                user's home dir ({option}`home`), and parent dirs on
                persistent storage are configured with the user's ownership and
                permissions.

                Multiple entries with different users may be configured side by
                side, each under its own attribute name (path).
              '';
              example = "alice";
            };

            hideMount = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether to hide the bind-mounts of the preserved dirs and files
                from desktop environments and file managers, by adding the mount
                options `x-gvfs-hide` and `x-gdu.hide` to every bind-mounted entry.
              '';
            };

            home = lib.mkOption {
              type = with lib.types; passwdEntry path;
              default = account.home;
              defaultText = "config.users.users.\${username}.home";
              internal = true;
              readOnly = true;
            };

            dirs = lib.mkOption {
              type = with lib.types;
                listOf (
                  coercedTo str (d: {dir = d;}) (submodule [
                    {
                      _module.args.defaultOwner = config.username;
                      _module.args.account = account;
                      mountOptions = lib.optionals config.hideMount [
                        "x-gvfs-hide"
                        "x-gdu.hide"
                      ];
                    }
                    dirPath
                  ])
                );
              default = [];
              apply = definedDirs: let
                scaffoldDirSettings = {
                  scaffold = true;
                  parent.enable = false;
                  user = config.username;
                  group = account.group;
                  mode = "0755";
                };
                allWithScaffolds =
                  mkScaffoldDirs scaffoldDirSettings config.files config.home
                  definedDirs;
              in
                if config.username == "root"
                then
                  # system-level: user-defined dirs stay absolute, but the generated
                  # scaffold dirs have relative paths (e.g. "var/lib"), so make
                  # them absolute to match
                  map (
                    d:
                      if d.scaffold
                      then d // {dir = concatTwoPaths "/" d.dir;}
                      else d
                  )
                  allWithScaffolds
                else let
                  # Split into original dirs and generated scaffolds
                  originalDirs = map (d: d // {dir = concatTwoPaths config.home d.dir;}) (
                    builtins.filter (d: !d.scaffold) allWithScaffolds
                  );
                  scaffolds = map (d: d // {dir = concatTwoPaths config.home d.dir;}) (
                    builtins.filter (d: d.scaffold) allWithScaffolds
                  );
                in
                  originalDirs ++ scaffolds;
              description = ''
                Specify a list of dirs that should be preserved.
                The paths are interpreted as absolute paths for system entries
                (when {option}`username` is `root`), or relative to the user's
                home dir when {option}`username` is set to another user.
              '';
              example = ["/var/lib/someservice"];
            };

            files = lib.mkOption {
              type = with lib.types;
                listOf (
                  coercedTo str (f: {file = f;}) (submodule [
                    {
                      _module.args.defaultOwner = config.username;
                      _module.args.account = account;
                      mountOptions = lib.optionals config.hideMount [
                        "x-gvfs-hide"
                        "x-gdu.hide"
                      ];
                    }
                    filePath
                  ])
                );
              default = [];
              apply =
                if config.username == "root"
                then lib.id
                else map (f: f // {file = concatTwoPaths config.home f.file;});
              description = ''
                Specify a list of files that should be preserved.
                The paths are interpreted as absolute paths for system entries
                (when {option}`username` is `root`), or relative to the user's
                home dir when {option}`username` is set to another user.
              '';
              example = lib.literalMD ''
                ```nix
                [
                  {
                    file = "/etc/wpa_supplicant.conf";
                    method = "symlink";
                  }
                  {
                    file = "/etc/machine-id";
                    inInitrd = true;
                  }
                ]
                ```
              '';
            };
          };
        }
      ));
    default = {};
    description = ''
      Specify multiple persistent storage locations to preserve state at.

      Each attribute name is the path of a persistent storage root; the
      entry's {option}`dirs` and {option}`files` are stored beneath it.
      Entries are independent: they may serve different users and apply
      different settings.
    '';
    example = lib.literalExpression ''
      {
        keepTo."/keep/host_systems" = {
          # system-level, paths are absolute (username defaults to "root")
          enable = true;
          dirs = ["/var/lib/service"];
        };
        keepTo."/keep/user_data" = {
          # paths are relative to the user's home dir
          enable = true;
          username = "alice";
          dirs = ["Documents"];
        };
      }
    '';
  };
}
