{
  description = "A collection of overlays, modules, libs, and templates for working with dinix";

  outputs =
    { self }:
    {
      nixosModules = import ./modules;

      lib.dinixSystem =
        {
          lib ? null,
          specialArgs ? { },
          modules ? [ ],
          ...
        }:
        let
          config = lib.evalModules {
            class = "nixos";
            specialArgs = lib.recursiveUpdate { modules = self.nixosModules; } specialArgs;
            modules = [ self.nixosModules.default ] ++ modules;
          };
        in
        config
        // {
          inherit (config._module.args) pkgs;
          inherit lib;
        };

      # Compatibility alias for configurations written against the original
      # Finix project API. New configurations should use lib.dinixSystem.
      lib.finixSystem = self.lib.dinixSystem;

      formatter =
        let
          sources = import ./lon.nix;
          lib = import (sources.nixpkgs + "/lib");

          pkgsFor = system: import sources.nixpkgs { inherit system; };
        in
        lib.genAttrs' [ "aarch64-linux" "x86_64-linux" ] (
          system: lib.nameValuePair system (pkgsFor system).nixfmt-tree
        );
    };
}
