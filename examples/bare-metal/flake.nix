{
  description = "Example Dinix bare-metal configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    dinix.url = "github:Sreehari425/dinix";
  };

  outputs =
    { nixpkgs, dinix, ... }:
    {
      nixosConfigurations.example = dinix.lib.dinixSystem {
        system = "x86_64-linux";
        inherit nixpkgs;
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
        ];
      };
    };
}
