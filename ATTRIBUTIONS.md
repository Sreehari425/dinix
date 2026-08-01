# Dinix attributions

Dinix is a fork of the Finix project. Finix provided the Nix-based
operating-system module structure, boot integration, service modules, and test
infrastructure used as the foundation for Dinix.

Dinix replaces Finix's Finit-based init and service-supervision layer with
Dinit. The project is experimental and independently developed from that base.

- [Finix](https://github.com/finix-community/finix) — original project and
  community modules.
- [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs) — module patterns,
  packages, compatibility code, and the NixOS test framework. The applicable
  upstream copyright and license notice is preserved in [COPYING](COPYING).
- [Dinit](https://github.com/davmac314/dinit) — the init and service manager
  used by Dinix.

Individual files retain their original copyright notices and upstream
references. Renaming the project does not remove or replace those notices.
