# Examples

See [Configuration Options](./configuration-options.md) for all available options.

Entries under `keepTo."<path>"` are active as soon as their `dirs` or `files` are
non-empty; there is no `enable` switch.

## Simple

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  keepTo."/persistent" = {
    files = [
      # auto-generated machine ID
      { file = "/etc/machine-id"; inInitrd = true; }
    ];
    dirs = [
      "/var/lib/systemd/timers"
      # NixOS user state
      "/var/lib/nixos"
      "/var/log"
    ];
  };

  # systemd-machine-id-commit.service would fail, but it is not relevant
  # in this specific setup for a persistent machine-id so we disable it
  #
  # see the firstboot example below for an alternative approach
  systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

}
```

## Compatibility with systemd's `ConditionFirstBoot`

In this example the machine-id is preserved on the persistent volume via symlink
instead of a bind-mount. The option `parent.enable` causes the parent dir
of the symlink's target, i.e. `/persistent/etc/` to be created, and `mkTarget`
creates an empty machine-id file at the target itself, enabling systemd's
first boot semantics. Additionally, `systemd-machine-id-commit.service` is
adapted to persist the tmpfs mount created by system to the persistent volume.

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  keepTo."/persistent" = {
    files = [
      # auto-generated machine ID
      { file = "/etc/machine-id"; inInitrd = true; method = "symlink"; mkTarget = true; parent.enable = true; }
      # ...
    ];
    dirs = [
      # ...
    ];
  };

  # let the service commit the transient ID to the persistent volume
  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [
      ""
      "/persistent/etc/machine-id"
    ];
    serviceConfig.ExecStart = [
      ""
      "systemd-machine-id-setup --commit --root /persistent"
    ];
  };
}
```



## Complex

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  keepTo."/persistent" = {
    # hide bind-mounts from desktop environments and file managers
    hideMount = true;

    # preserve system dirs
    dirs = [
      "/etc/secureboot"
      "/var/lib/bluetooth"
      "/var/lib/fprint"
      "/var/lib/fwupd"
      "/var/lib/libvirt"
      "/var/lib/power-profiles-daemon"
      "/var/lib/systemd/coredump"
      "/var/lib/systemd/rfkill"
      "/var/lib/systemd/timers"
      "/var/log"
      { dir = "/var/lib/nixos"; inInitrd = true; }
    ];

    # preserve system files
    files = [
      { file = "/etc/machine-id"; inInitrd = true; }
      { file = "/etc/ssh/ssh_host_rsa_key"; method = "symlink"; parent.enable = true; }
      { file = "/etc/ssh/ssh_host_ed25519_key"; method = "symlink"; parent.enable = true; }
      "/var/lib/usbguard/rules.conf"

      # creates a symlink on the volatile root
      # creates an empty dir on the persistent volume, i.e. /persistent/var/lib/systemd
      # does not create an empty file at the symlink's target (would require `mkTarget = true`)
      { file = "/var/lib/systemd/random-seed"; method = "symlink"; inInitrd = true; parent.enable = true; }
    ];
  };

  # User-specific state gets its own storage location. Paths are interpreted
  # relative to butz's home dir; ownership and scaffold path components
  # default to butz.
  keepTo."/persistent/users/butz" = {
    username = "butz";

    files = [".histfile"];
    dirs = [
      # custom mode for a preserved dir
      { dir = ".ssh"; mode = "0700"; }
      ".config/syncthing"
      ".config/Element"
      ".local/state/nvim"
      ".local/state/wireplumber"
      ".local/share/direnv"
      ".local/state/nix"
      ".mozilla"
    ];
  };
}
```
