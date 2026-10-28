pkgs: {
  name = "keep-user";

  nodes.machine = {pkgs, ...}: {
    # import the keep module
    imports = [../module.nix];

    # module configuration
    keepTo."/state" = {
      # paths are interpreted relative to the user's home dir
      username = "butz";
      # bind-mounts are hidden from desktop environments and file managers
      hideMount = true;
      dirs = [
        "unshaved_yaks"
        "foo/bar/baz"
        {
          dir = "symlinked_user_dir";
          method = "symlink";
        }
      ];
      files = [
        {
          file = ".config/foo";
          mode = "0600";
        }
        "bar"
        # an empty file with may be created at the symlink's
        # target, i.e. on the persistent volume
        {
          file = ".symlinks/baz";
          method = "symlink";
          mkTarget = true;
        }
        # this file should be mounted and with the combination of all
        # configured `x-gvfs-hide`, `x-gdu.hide` and `x-baz`.
        {
          file = "yay_userspace_mount_options";
          mountOptions = ["x-baz"];
        }
        # a symlinked file in the user's home dir
        {
          file = ".toplevel_symlink";
          method = "symlink";
        }
      ];
    };

    # test-specific configuration below

    boot.initrd.systemd.enable = true;
    networking.useNetworkd = true;

    users.users.butz = {
      isNormalUser = true;
      # custom home dir
      home = "/home/custom-but";
    };

    virtualisation = {
      memorySize = 2048;
      # separate block device for preserved state
      emptyDiskImages = [23];
      fileSystems."/state" = {
        device = "/dev/vdb";
        fsType = "ext4";
        neededForBoot = true;
        autoFormat = true;
      };
    };
  };

  testScript = {nodes, ...}: let
    butzHome = nodes.machine.users.users.butz.home;

    allFiles = nodes.machine.keepTo."/state".files;
    allDirs = nodes.machine.keepTo."/state".dirs;
    allJSON = builtins.toJSON (allDirs ++ allFiles);
  in
    # (for syntax highlighting)
    /*
    python
    */
    ''
      import json

      all_files = json.loads('${allJSON}')

      def check_file(config, in_initrd=False):
        prefix = "/sysroot" if in_initrd else ""
        file_path = config.get("dir", config.get("file"))
        path = f"{prefix}{file_path}"

        if config.get("scaffold"):
          # scaffold entries only ever refer to dirs
          machine.succeed(f"test -d {path}")

          # scaffolds are never mounted
          machine.fail(f"mountpoint {path}")

          # check permissions and ownership
          actual = machine.succeed(f"stat -c '0%a %U %G' {path} | tee /dev/stderr").strip()
          expected = "{} {} {}".format("0755",config["user"],config["group"])
          t.assertEqual(actual, expected, "unexpected file attributes")

        else:
          match config["method"]:
            case "bindmount":
              # check that file is mounted
              machine.succeed(f"mountpoint {path}")

              # check permissions and ownership
              actual = machine.succeed(f"stat -c '0%a %U %G' {path} | tee /dev/stderr").strip()
              expected = "{} {} {}".format(config["mode"],config["user"],config["group"])
              t.assertEqual(actual, expected, "unexpected file attributes")

            case "symlink":
              # check that file is _not_ mounted
              machine.fail(f"mountpoint {path}")

            case x:
              raise Exception(f"Unknown case: {x}")

        if config.get("parent", {}).get("enable") == True:
          parent = os.path.dirname(path)
          config = config["parent"]
          # check permissions and ownership of parent dir
          actual = machine.succeed(f"stat -c '0%a %U %G' {parent} | tee /dev/stderr").strip()
          expected = "{} {} {}".format(config["mode"],config["user"],config["group"])
          t.assertEqual(actual, expected, "unexpected file attributes")


      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")

      with subtest("Type, permissions and ownership after first boot"):
        for file in all_files:
          check_file(file)

      with subtest("Unpreserved scaffold user dirs have correct permissions and ownership"):
        for path_segment in [ "foo", "foo/bar" ]:
          actual = machine.succeed(f"stat -c '0%a %U %G' ${butzHome}/{path_segment} | tee /dev/stderr").strip()
          expected = "0755 butz users"
          t.assertEqual(actual, expected, "unexpected file attributes")

      with subtest("Custom (userspace) mount options are applied"):
        utab_entry = machine.succeed("grep TARGET=${butzHome}/yay_userspace_mount_options /run/mount/utab")
        for opt in [ "x-gvfs-hide", "x-gdu.hide", "x-baz"]:
          t.assertIn(opt, utab_entry, "expected mount option not found")

      with subtest("Files preserved across reboots"):
        # write something in one of the preserved files
        teststring = "foobarbaz"
        machine.succeed(f"echo -n '{teststring}' > ${butzHome}/bar")

        machine.reboot()
        machine.wait_for_unit("default.target")

        # check that state in file was also preserved
        machine.succeed(f"test -s ${butzHome}/bar")
        content = machine.succeed(f"cat ${butzHome}/bar")
        t.assertEqual(content, teststring, "unexpected file content")

      with subtest("Type, permissions and ownership after reboot"):
        for file in all_files:
          check_file(file)

      machine.shutdown()
    '';
}
