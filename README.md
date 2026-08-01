# Dinix

Dinix is based on and continues the work of [Finix](https://github.com/finix-community/finix).

Dinix is an experimental hobby project for learning about the
[Dinit](https://github.com/davmac314/dinit) service manager and exploring how it
can work with a NixOS-style system.

It is unfinished, may change frequently, and is not intended for production use.

## Flake usage

Dinix exposes a NixOS-compatible `nixosConfigurations` interface. Start with
the example in `examples/bare-metal`, replace its hardware configuration, and
build it with:

```sh
nix build ./examples/bare-metal#nixosConfigurations.example.config.system.build.toplevel
nixos-rebuild switch --flake ./examples/bare-metal#example
```
