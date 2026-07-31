{ pkgs, lib, ... }:
let
  dinix-logo = pkgs.runCommand "dinix-logo" { } ''
    install -Dm644 ${../../assets/finix-logo.svg} $out/share/icons/hicolor/scalable/apps/dinix-logo.svg
  '';
in
{
  imports = [
    ./etc
    ./path
    ./shells
  ];

  options.environment.binsh = lib.mkOption {
    type = lib.types.path;
    default = "${pkgs.bashInteractive}/bin/sh";
    defaultText = lib.literalExpression ''"''${pkgs.bashInteractive}/bin/sh"'';
    example = lib.literalExpression ''"''${pkgs.dash}/bin/dash"'';
    description = ''
      Default shell linked system-wide to `/bin/sh`. Do your best to make sure any
      modifications to this shell are POSIX-compliant.
    '';
  };

  config = {
    environment.systemPackages = [ dinix-logo ];
    environment.etc."nsswitch.conf".text = ''
      # /etc/nsswitch.conf
      #
      # Example configuration of GNU Name Service Switch functionality.
      # If you have the `glibc-doc-reference' and `info' packages installed, try:
      # `info libc "Name Service Switch"' for information about this file.

      passwd:         files
      group:          files
      shadow:         files
      gshadow:        files

      hosts:          files dns
      networks:       files

      protocols:      db files
      services:       db files
      ethers:         db files
      rpc:            db files

      netgroup:       nis
    '';

    environment.etc.os-release.text = ''
      ANSI_COLOR="0;38;2;231;56;71"
      BUG_REPORT_URL="https://github.com/Sreehari425/dinix/issues/"
      DEFAULT_HOSTNAME=dinix
      HOME_URL="https://github.com/Sreehari425/dinix/"
      ID=dinix
      LOGO=dinix-logo
      NAME=dinix
      PRETTY_NAME="dinix"
      VENDOR_NAME=dinix
      VENDOR_URL="https://github.com/Sreehari425/dinix/"
      VERSION="rolling"
      VERSION_ID="rolling"
    '';
  };
}
