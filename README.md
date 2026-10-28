# Keep

Nix tooling to enable declarative management of non-volatile system state.

Inspired and heavily influenced by [impermanence](https://github.com/nix-community/impermanence) but not
meant to be a drop-in replacement.

## Documentation

The full option reference and more examples are available in the
[documentation](https://src-06.github.io/keep/).

## Prerequisites

Requires at least nixos-24.11 and a systemd-based initrd.

## Why?

This aims to provide a declarative state management solution for NixOS systems without resorting to
interpreters to do the heavy lifting. This should enable impermanence-like state management on
an "interpreter-less" NixOS system.

## Usage

State is preserved via `keepTo`, an attribute set whose attribute names are the persistent
storage locations. An entry is active as soon as it has something to preserve, i.e. its
`dirs` or `files` are non-empty — there is no `enable` switch. To disable an entry whose
lists are populated by other modules, override them with empty lists:

```nix
keepTo."/state" = {
  dirs = lib.mkForce [];
  files = lib.mkForce [];
};
```

Multiple locations — and multiple users — can be configured side by side:

```nix
keepTo."/state" = {
  # system-level data, paths are absolute
  dirs = [ "/var/log" ];
  files = [ { file = "/etc/machine-id"; inInitrd = true; } ];
};

keepTo."/state/userdata" = {
  # user data of alice, paths are relative to alice's home dir
  username = "alice";

  # hide bind-mounts from desktop environments and file managers
  hideMount = true;

  dirs = [
    "Documents"
    "Projects"
    ".local/share/fish"
  ];
  files = [
    { file = ".config/foo"; method = "symlink"; }
  ];
};
```

### Storage location options

Each `keepTo."<path>"` entry supports:

- `username`: the user whose state is preserved. Defaults to `root`, i.e. system-level
  preservation with absolute paths. Any other user interprets `dirs` and `files` relative
  to that user's home dir and defaults ownership to that user.
- `hideMount`: adds the mount options `x-gvfs-hide` and `x-gdu.hide` to every
  bind-mounted entry of this location.
- `dirs` / `files`: the paths to preserve. Plain strings are accepted and coerced.

### Per-path options

Every entry in `dirs` and `files` additionally accepts:

- `method`: how the path is preserved, either `bindmount` (the default) or `symlink`.
- `user`, `group`, `mode`: ownership and permissions on both volumes.
- `parent`: ownership and permissions of the path's parent dir (`enable`, `user`,
  `group`, `mode`).
- `mkTarget`: with `method = "symlink"`, create an empty dir/file as the symlink's target
  on the persistent volume.
- `inInitrd`: prepare the preservation already in the initrd.
- `mountOptions`: additional mount options, only used for bindmounts.

### Persisting the machine ID

`/etc/machine-id` needs special treatment to be preserved across reboots. The recommended
setup uses a symlink and adapts `systemd-machine-id-commit.service`:

```nix
keepTo."/state" = {
  files = [
    { file = "/etc/machine-id"; inInitrd = true; method = "symlink"; mkTarget = true; }
  ];
};

systemd.services.systemd-machine-id-commit = {
  unitConfig.ConditionPathIsMountPoint = ["" "/state/etc/machine-id"];
  serviceConfig.ExecStart = ["" "systemd-machine-id-setup --commit --root /state"];
};
```

See the [examples](https://src-06.github.io/keep/examples.html) for details and
alternatives.

## Related

- <https://github.com/NixOS/nixpkgs/issues/265640>
- <https://github.com/nix-community/projects/blob/main/proposals/nixpkgs-security-phase2.md#boot-chain-security>

## License

This project is released under the terms of the MIT License. See [LICENSE](./LICENSE).
