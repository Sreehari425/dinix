# Dinix attributions

Dinix is a renamed fork and continuation of the Finix project. The original
Finix project and its contributors provided the Nix-based operating-system
module structure, boot integration, service modules, and test infrastructure
from which Dinix is derived:

- [Finix](https://github.com/finix-community/finix) — original project and
  community modules.
- [NixOS/nixpkgs](https://github.com/NixOS/nixpkgs) — module patterns,
  packages, compatibility code, and the NixOS test framework. The applicable
  upstream copyright and license notice is preserved in [COPYING](COPYING).
- [Finit](https://github.com/finit-project/finit) — the original init and
  service-supervision integration retained for compatibility during migration.
- [Dinit](https://github.com/davmac314/dinit) — the target init and service
  manager for the Dinix backend.

Individual files retain their original copyright notices and upstream
references. Renaming the project does not remove or replace those notices.
