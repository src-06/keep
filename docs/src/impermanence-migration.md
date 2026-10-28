# Migration from impermanence to Keep

This section lists individual differences between impermanence and
Keep, to better understand them in context of a complete configuration
[Examples](./examples.md) may be helpful.

The following points need to be considered when migrating an existing
impermanence configuration to Keep:

### No global `enable` switch

An entry under `keepTo."<path>"` is active as soon as its `dirs` or `files` lists
are non-empty. There is no separate `enable` option.

To disable an entry whose lists are populated by other modules, override them with
empty lists:

```nix
keepTo."/state" = {
  dirs = lib.mkForce [];
  files = lib.mkForce [];
};
```

### Handling of existing state

Coming from a setup with impermanence it is important to make sure existing persistent state is preserved
correctly, meaning the ownership and mode of preservation remains the same. There is no exhaustive list
of files and dirs requiring special treatment but at least the following needs to be considered:

**SSH host keys**

Correct ownership and mode of SSH host keys is very important for sshd to accept connections.
Getting this wrong, e.g. not restricted enough, may cause your host to become inaccessible via SSH, forcing
you to use other means of logging into the machine.

The following config may be used to preserve the RSA and Ed25519 host keys with Keep:

```nix
keepTo."/state".files = [
  { file = "/etc/ssh/ssh_host_rsa_key"; method = "symlink"; parent.enable = true; }
  { file = "/etc/ssh/ssh_host_ed25519_key"; method = "symlink"; parent.enable = true; }
];
```

The above config does not include access modes for the key files because the preservation
mode is `symlink` and the link's target is not touched by preservation without an explicit
`mkTarget = true`.

**Secrets and other files requiring special access modes**

Any files and dirs that need to have a mode that differs from the default (`0644` for files
and `0755` for dirs) must be configured explicitly to avoid having the default mode applied.

### When to persist

Files and dirs that need to be persisted early, must be explicitly configured. For example `/etc/machine-id`:

This file needs to be persisted very early, by explicitly setting `inInitrd` to `true`:
```nix
keepTo."/state".files = [
  { file = "/etc/machine-id"; inInitrd = true; }
];
```

### How to persist

The mode of preservation must be set explicitly for some files and dirs.
This can be done by setting `method` to either `symlink` or `bindmount` (default).
For most cases the default is sufficient but sometimes a symlink may be needed,
for example `/var/lib/systemd/random-seed`.

This file is expected to not exist before it is initialized. A symlink can be
used to cause its creation to happen on the persistent volume:

```nix
keepTo."/state".files = [
  {
    file = "/var/lib/systemd/random-seed";
    # create a symlink on the volatile volume
    method = "symlink";
    # prepare the preservation early during startup
    inInitrd = true;
  }
];
```

Note that no file is created at the symlink's target, unless `mkTarget` is set to `true`.

### Scaffold path components

Any dir that is not preserved itself but is a parent of a preserved file or dir
is called a scaffold path component here. Regarding the ownership and permissions of these
scaffold path components, the following needs to be considered.

#### Scaffold path components of user-specific files and dirs

Parent dirs of a preserved user-specific file or dir are created with the respective
user as their owner and permissions `0755`. This is the case for all scaffold path components
up to, but not including, the user's home dir.

**Example**

Consider the following preservation config:

```nix
keepTo."/state/userdata" = {
  username = "alice";
  dirs = [
    ".local/state/nvim"
  ];
};
```

This config will cause the module to configure a bind-mount for the subdir `nvim`, causing its
contents to be preserved. The scaffold path components `.local` and `state` will be created if
necessary, but their contents are not preserved. Owner is set to `alice`, group to alice's primary
group, i.e. `users.users.alice.group` and the mode is set to `0755`.


#### Scaffold path components of system-wide files and dirs

For system-wide files and dirs, missing components of a preserved path that do not already exist,
are created by systemd-tmpfiles with default ownership `root:root` and mode `0755`.

Should such dirs require different ownership or mode, the intended way to create and configure them
is via systemd-tmpfiles directly.

**Example**

Consider a preserved file `/foo/bar/baz`:

```nix
keepTo."/state".files = [
  { file = "/foo/bar/baz"; user = "baz"; group = "baz"; };
];
```

This would create the file with desired ownership on both the volatile and persistent volumes.
However, the parent dirs that did not exist before, i.e. `/foo` and `/foo/bar`, are
created with ownership `root:root` and mode `0755`.

Keep allows the configuration of immediate parents, so the permissions for `/foo/bar`
can be configured:
```nix
keepTo."/state".files = [
  {
    file = "/foo/bar/baz"; user = "baz"; group = "baz";
    parent.enable = true;
    parent.user = "baz";
    parent.group = "bar";
  };
];
```
Now the parent dir `/foo/bar` is configured with ownership `baz:bar`. But the first
path component `/foo` still has systemd-tmpfiles' default ownership and the configuration
becomes quite convoluted.

**Solution**

To create or configure scaffold path components of a persisted path, systemd-tmpfiles
may be used directly:

```nix
# configure preservation of single file
keepTo."/state".files = [
  { file = "/foo/bar/baz"; user = "baz"; group = "bar"; };
];

# create and configure parents of preserved file on the volatile volume with custom permissions
# The keep module also uses `settings.keep` here.
systemd.tmpfiles.settings.keep = {
  "/foo".d = { user = "foo"; group = "bar"; mode = "0775"; };
  "/foo/bar".d = { user = "bar"; group = "bar"; mode = "0755"; };
};
```

See [tmpfiles.d(5)](https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html)
for available configuration options.
