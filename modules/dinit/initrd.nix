{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.boot.initrd;

  grantAccess = cfg.emergencyAccess == true || lib.isString cfg.emergencyAccess;

  fsPackages = lib.unique (
    lib.flatten (
      lib.concatMap (v: lib.optional v.enable v.packages or [ ]) (
        lib.attrValues config.boot.initrd.supportedFilesystems
      )
    )
  );

  path = pkgs.buildEnv {
    name = "initrd-path";
    paths = [
      pkgs.busybox
      pkgs.kmod
      (lib.hiPrio pkgs.util-linux.mount)
      pkgs.bash
    ]
    ++ [ config.dinit.package ]
    ++ lib.optionals config.services.mdevd.enable [
      config.services.mdevd.package
      pkgs.execline
      pkgs.util-linux
    ]
    ++ lib.optionals config.services.gardendevd.enable [
      config.services.gardendevd.package
      pkgs.util-linux
    ]
    ++ lib.optionals config.services.udev.enable [ config.services.udev.package ]
    ++ fsPackages;
    pathsToLink = [
      "/bin"
    ];

    ignoreCollisions = true;

    postBuild = ''
      # Remove wrapped binaries, they shouldn't be accessible via PATH.
      find $out/bin -maxdepth 1 -name ".*-wrapped" -type l -delete
    '';
  };
in
{
  options.boot.initrd = {
    emergencyAccess = lib.mkOption {
      type = with lib.types; nullOr (either bool (passwdEntry str));
      default = false;
      description = ''
        Set to `true` for unauthenticated emergency access to the initramfs
        rescue shell, and `false` or `null` for no access.

        Can also be set to a hashed super user password to allow
        authenticated access to the rescue mode.

        When access is denied, dinix prints the failure reason on console
        and reboots after 10s instead of opening a shell.
      '';
    };
  };

  config.boot.initrd = {
    dinit.tasks.modprobe = {
      command = "/bin/modprobe --all ${lib.concatStringsSep " " cfg.kernelModules}";
    };

    contents = [
      {
        target = "/init";
        source = pkgs.writeTextFile {
          name = "dinix-initrd-init";
          executable = true;
          text = lib.concatStringsSep "\n" [
                "#!/bin/sh"
                "set -u"
                ""
                "/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null || true"
                "/bin/busybox mkdir -p /dev"
                "/bin/busybox mkdir -p /proc /sys /run"
                "/bin/mount -t proc proc /proc 2>/dev/null || true"
                "/bin/mount -t sysfs sysfs /sys 2>/dev/null || true"
                "/bin/mount -t tmpfs -o mode=0755 tmpfs /run 2>/dev/null || true"
                "[ -e /dev/null ] || /bin/mknod -m 666 /dev/null c 1 3"
                "[ -e /dev/console ] || /bin/mknod -m 600 /dev/console c 5 1"
                "/bin/busybox ln -sfn /proc/self/fd /dev/fd"
                "/bin/busybox ln -sfn /proc/self/fd/0 /dev/stdin"
                "/bin/busybox ln -sfn /proc/self/fd/1 /dev/stdout"
                "/bin/busybox ln -sfn /proc/self/fd/2 /dev/stderr"
                ""
                ''
                    /bin/dinit &
                    dinitPid=$!
                    while [ ! -e /run/dinit-boot-complete ]; do
                      if ! /bin/busybox kill -0 "$dinitPid" 2>/dev/null; then
                        wait "$dinitPid"
                        exit 1
                      fi
                      /bin/busybox sleep 0.1
                    done

                    /bin/busybox kill -TERM "$dinitPid"
                    wait "$dinitPid" || true

                    stage2Init=/init
                    for option in $(/bin/busybox cat /proc/cmdline); do
                      case "$option" in
                        init=*) stage2Init=''${option#init=} ;;
                      esac
                    done

                    /bin/busybox mkdir -p /sysroot/dev /sysroot/etc/dinit.d /sysroot/proc /sysroot/run /sysroot/sys /sysroot/tmp /sysroot/var
                    /bin/busybox mount --bind /dev /sysroot/dev
                    /bin/busybox mount --bind /proc /sysroot/proc
                    /bin/busybox mount --bind /sys /sysroot/sys
                    /bin/busybox chroot /sysroot ${config.system.activation.out}
                    stage2Root=''${stage2Init%/init}
                    /bin/busybox ln -sfn "$stage2Root" /sysroot/run/current-system
                    exec /bin/busybox switch_root /sysroot "$stage2Init"
                  ''
          ];
        };
      }
      {
        target = "/bin";
        source = "${path}/bin";
      }
      {
        target = "/sbin";
        source = "${path}/bin";
      }
      {
        target = "/etc/os-release";
        source = pkgs.writeText "os-release" ''
          PRETTY_NAME="dinix - stage 1"
        '';
      }
      {
        target = "/etc/modules-load.d/dinix.conf";
        source = pkgs.writeText "dinix.conf" ''

          ${lib.concatStringsSep "\n" config.boot.initrd.kernelModules}
        '';
      }
      {
        target = "/etc/tmpfiles.d/dinix.conf";
        source = pkgs.writeText "dinix.conf" ''
          d /sysroot
          d /tmp
        '';
      }
      {
        target = "/etc/fstab";
        source = pkgs.writeText "fstab" ''
          # fstab.conf
          # tmpfs /run/wrappers tmpfs mode=755,nodev,size=50%,X-mount.mkdir 0 0

          tmpfs /run tmpfs mode=0755,nodev,nosuid,X-mount.mkdir 0 0
        '';
      }
      {
        target = "/etc/passwd";
        source = pkgs.writeText "passwd" ''
          root:x:0:0:root:/root:/bin/sh
        '';
      }
      {
        target = "/etc/group";
        source = pkgs.writeText "group" (
          lib.concatStringsSep "\n" (
            lib.concatMap (g: lib.optionals (g.gid != null) [ "${g.name}:x:${toString g.gid}:" ]) (
              lib.attrValues config.users.groups
            )
          )
        );
      }
      {
        target = "/etc/shadow";
        source =
          let
            password =
              if !grantAccess then
                "*"
              else if lib.isString cfg.emergencyAccess then
                cfg.emergencyAccess
              else
                "";
          in
          pkgs.writeText "shadow" ''
            root:${password}:1:0:99999:7:::
          '';
      }
    ];
  };
}
