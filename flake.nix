{
  outputs = inputs: {
    lib = import ./lib.nix; # need to pass nixpkgs-lib
    nixosModules = {
      default = inputs.self.nixosModules.keep;
      keep = ./module.nix;
    };
  };
}
