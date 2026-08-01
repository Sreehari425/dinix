{
  config,
  lib,
  pkgs,
  ...
}:
let
  tmpfiles = "${pkgs.systemd}/bin/systemd-tmpfiles";
in
{
  options.dinit.tmpfiles.rules = lib.mkOption {
    type = with lib.types; listOf str;
    default = [ ];
    example = [ "d /tmp 1777 root root 10d" ];
    description = ''
      Rules for creation, deletion and cleaning of volatile and temporary files
      automatically. See {manpage}`tmpfiles.d(5)` for the exact format.
    '';
  };

  config = {
    environment.etc."tmpfiles.d/dinix.conf".text = ''
      # This file is created automatically and should not be modified.
      # Please change the option ‘dinit.tmpfiles.rules’ instead.

      ${lib.concatStringsSep "\n" config.dinit.tmpfiles.rules}
    '';

    dinit.tasks.tmpfiles-setup.command = "${tmpfiles} --create";

    providers.scheduler.tasks = {
      tmpfiles-clean = {
        interval = "daily";
        command = "${tmpfiles} --clean";
      };
    };

    # needed for dinit tmpfiles Z implementation: pkgs.policycoreutils
    # TODO: make this an optional dependency, fixup Z behaviour in general
  };
}
