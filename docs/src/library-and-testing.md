# Library and Testing

## Library

The functionality that is used in the module to discover the files and
dirs that are persisted and to generate the corresponding tmpfiles
config and mount units is available from [`lib.nix`](https://github.com/src-06/keep/blob/main/lib.nix).
It is also available from the flake `lib` output.

In both cases it needs to be instantiated with the nixpkgs `lib`.

## Testing

The integration test(s) can be found in [/tests](https://github.com/src-06/keep/blob/main/tests).
