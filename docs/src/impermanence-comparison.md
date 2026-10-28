# How does Keep compare to [impermanence](https://github.com/nix-community/impermanence)

### Keep does not attempt to be a very generic solution

Keep tries to fill a specific niche.
For instance, Keep does not support non-NixOS systems via home-manager, which is supported
by impermanence. See [Migration](./impermanence-migration.md) for more technical details.

### Keep only generates static configuration

That is configuration for [systemd-tmpfiles](https://www.freedesktop.org/software/systemd/man/latest/systemd-tmpfiles.html)
and systemd [mount units](https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html).
This makes Keep a potential candidate for state management on interpreter-less NixOS systems.

Impermanence makes use of NixOS activation scripts and custom systemd services with bash (at the point
of writing this), to create files and dirs, setup mounts and configure ownership and permissions (see next point).

### Keep must be precisely configured
There is no [special runtime logic](https://github.com/nix-community/impermanence/blob/23c1f06316b67cb5dabdfe2973da3785cfe9c34a/mount-file.bash#L31-L42)
  in place. This means that the user must define:
  * when the preservation should be set up: either in the initrd, or after (the default)
  * how the preservation should be set up: either by symlink, or bindmount (the default)
  * whether or not parent dirs of the persisted files require special permissions

See [Migration](./impermanence-migration.md) for specifics that need to be considered when coming from an impermanence setup.

### Similar configuration

Keep's configuration is based on, and very similar to that of impermanence. See [Migration](./impermanence-migration.md) for technical details.

### No `enable` option

The keep module does not use an `enable` switch: an entry is active as soon as it has
something to preserve, i.e. its `dirs` or `files` are non-empty. This differs from both
impermanence and upstream preservation.

To disable an entry whose lists are populated by other modules, override them with
empty lists (`lib.mkForce []`).

For thoughts on the `enable` option, see the discussion at <https://github.com/nix-community/impermanence/pull/171> and for available configuration options see [Configuration Options](./configuration-options.md).

### Generic `hideMount` option

Impermanence provides a `hideMounts` option, which sets the mount option `x-gvfs-hide` for bind-mounts.
The keep module provides a similar `hideMount` option, which adds `x-gvfs-hide` and `x-gdu.hide` to
the mount options of every bind-mounted entry.

Additionally, keep allows for the configuration of arbitrary mount options per file and dir
via `mountOptions`.
