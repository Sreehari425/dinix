{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.sysklogd;
in
{
  options.services.sysklogd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable [sysklogd](${pkgs.sysklogd.meta.homepage}) as a system service.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sysklogd;
      defaultText = lib.literalExpression "pkgs.sysklogd";
      description = ''
        The package to use for `sysklogd`.
      '';
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Additional `sysklogd` configuration. See {manpage}`syslog.conf(5)`
        for additional details.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # dinit has explicit sysklogd support, requires `logger` to be available in `PATH`
    dinit.path = [
      cfg.package
    ];

    dinit.services.syslogd = {
      description = "system logging daemon";
      runlevels = "S0123456789";
      conditions =
        lib.optionals config.services.gardendevd.enable [ "run/gardendevctl:2/success" ]
        ++ lib.optionals config.services.keventd.enable [ "pid/keventd" ]
        ++ lib.optionals config.services.udev.enable [ "run/udevadm:5/success" ]
        ++ lib.optionals config.services.mdevd.enable [ "run/coldplug/success" ];
      command = "${cfg.package}/bin/syslogd -F";
      notify = "pid";
    };

    environment.etc."syslog.d/nixos.conf".text = cfg.extraConfig;
    environment.etc."syslog.conf".source =
      lib.mkDefault "${cfg.package}/share/doc/sysklogd/syslog.conf";

    # TODO: add dinit.services.reloadTriggers option
    environment.etc."dinit.d/syslogd.conf".text = lib.mkAfter ''

      # reload trigger
      # ${config.environment.etc."syslog.d/nixos.conf".source}
      # ${config.environment.etc."syslog.conf".source}
    '';

    system.switch.inhibitors.syslogd = config.dinit.services.syslogd.command;
  };
}
