pkgs: {
  name = "keep-basic";

  nodes.machine = {pkgs, ...}: {
    # import the keep module
    imports = [../module.nix];

    # module configuration
    keepTo."/state" = {
      dirs = [
        "/var/lib/someservice"
        "/var/log"
      ];
      files = [
        {
          file = "/etc/wpa_supplicant.conf";
          method = "symlink";
        }
        # some files need to be prepared very early, machine-id is one such case
        {
          file = "/etc/machine-id";
          inInitrd = true;
        }
        # persist SSH host keys
        {
          file = "/etc/ssh/ssh_host_rsa_key";
          method = "symlink";
          parent.enable = true;
        }
        {
          file = "/etc/ssh/ssh_host_ed25519_key";
          method = "symlink";
          parent.enable = true;
        }
        # this file should be mounted and with the combination of all
        # configured `x-foo` and `x-baz`.
        {
          file = "/etc/yay_userspace_mount_options";
          mountOptions = ["x-foo" "x-baz"];
        }
      ];
    };

    # systemd-machine-id-commit.service would fail, but it is not relevant
    # in this specific setup for a persistent machine-id so we disable it
    systemd.suppressedSystemUnits = ["systemd-machine-id-commit.service"];

    # to test sshd with preserved host keys
    services.openssh.enable = true;

    # test-specific configuration below

    testing.initrdBackdoor = true;
    boot.initrd.systemd = {
      enable = true;
      extraBin = {
        mountpoint = "${pkgs.util-linux}/bin/mountpoint";
      };
    };
    networking.useNetworkd = true;

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
    allFiles = nodes.machine.keepTo."/state".files;
    allDirs = nodes.machine.keepTo."/state".dirs;
    initrdFiles = builtins.filter (conf: conf.inInitrd) allFiles;
    initrdDirs = builtins.filter (conf: conf.inInitrd) allDirs;
    initrdJSON = builtins.toJSON (initrdDirs ++ initrdFiles);
    allJSON = builtins.toJSON (allDirs ++ allFiles);
  in
    # (for syntax highlighting)
    /*
    python
    */
    ''
      import json

      initrd_files = json.loads('${initrdJSON}')
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

      with subtest("Empty machine ID files and bindmount prepared in initrd"):
        machine.succeed("test -f /sysroot/etc/machine-id")
        machine.succeed("test -f /sysroot/state/etc/machine-id")

        # files are expected to be empty at this point
        machine.fail("test -s /sysroot/etc/machine-id")
        machine.fail("test -s /sysroot/state/etc/machine-id")

        mounts = machine.succeed("mount")
        t.assertIn("/sysroot/etc/machine-id", mounts, "/sysroot/etc/machine-id not in mounts")

      with subtest("Type, permissions and ownership in first boot initrd"):
        for file in initrd_files:
          check_file(file, in_initrd=True)

      machine.switch_root()
      machine.wait_for_unit("default.target")

      with subtest("Machine ID file still mounted and now populated"):
        machine.succeed("mountpoint /etc/machine-id")
        machine.succeed("test -s /etc/machine-id")

      with subtest("Type, permissions and ownership after first boot completed"):
        for file in all_files:
          check_file(file)

      with subtest("SSH host keys created at the persistent prefix"):
        machine.succeed("test -s /state/etc/ssh/ssh_host_rsa_key")
        machine.succeed("test -s /state/etc/ssh/ssh_host_ed25519_key")

      with subtest("sshd service running"):
        machine.wait_for_unit("sshd.service")

      with subtest("Files preserved across reboots"):
        # write something in one of the preserved dirs
        teststring = "foobarbaz"
        machine.succeed(f"echo -n '{teststring}' > /var/log/keep-test-content")

        # get current machine id
        machine_id = machine.succeed("cat /etc/machine-id")

        # reboot to initrd
        machine.reboot()
        machine.wait_for_unit("default.target")

        # preserved machine-id resides on /state
        machine.succeed("test -s /sysroot/state/etc/machine-id")
        initrd_machine_id = machine.succeed("cat /sysroot/state/etc/machine-id")
        t.assertEqual(initrd_machine_id, machine_id, "machine id changed")

        # check that machine-id is already mounted in initrd
        mounts = machine.succeed("mount")
        t.assertIn("/sysroot/etc/machine-id", mounts, "/sysroot/etc/machine-id not in mounts")

        # check type, permissions and ownership before switch root
        for file in initrd_files:
          check_file(file, in_initrd=True)

        # proceed with boot
        machine.switch_root()
        machine.wait_for_unit("default.target")

        # check that machine-id remains unchanged in stage-2 after reboot
        machine.succeed("test -s /etc/machine-id")
        new_machine_id = machine.succeed("cat /etc/machine-id")
        t.assertEqual(new_machine_id, machine_id, "machine id changed")

        # check that state in file was also preserved
        machine.succeed("test -s /var/log/keep-test-content")
        content = machine.succeed("cat /var/log/keep-test-content")
        t.assertEqual(content, teststring, "unexpected file content")

      with subtest("Type, permissions and ownership after reboot"):
        for file in all_files:
          check_file(file)

      with subtest("Custom (userspace) mount options are applied"):
        utab_entry = machine.succeed("grep TARGET=/etc/yay_userspace_mount_options /run/mount/utab")
        for opt in [ "x-foo", "x-baz"]:
          t.assertIn(opt, utab_entry, "expected mount option not found")

      machine.shutdown()
    '';
}
