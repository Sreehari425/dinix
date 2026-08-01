{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dinit;

  rootTasks = lib.filterAttrs (
    name: task:
    task.enable
    && name != "ctrl-alt-del"
    # These tasks belong to the Dinit-based boot layout.  Initrd module
    # loading is handled separately, while the test root already provides a
    # mounted Nix store and does not need wrapper generation during boot.
    && !(config.dinit.enable && lib.elem name [ "modprobe" "remount-nix-store" "suid-sgid-wrappers" ])
  ) config.dinit.tasks;

  enabled = attrs: lib.filterAttrs (_: value: value.enable) attrs;

  conditionToDependency = condition:
    let
      parts = lib.splitString "/" condition;
    in
    if lib.length parts >= 2 && builtins.elemAt parts 0 == "service" then
      builtins.elemAt parts 1
    else if lib.length parts >= 2 && builtins.elemAt parts 0 == "task" then
      "task-${builtins.elemAt parts 1}"
    else
      null;

  dependencies = service:
    lib.unique (
      (service.dependsOn or [ ])
      ++ lib.filter (value: value != null) (map conditionToDependency (service.conditions or [ ]))
    );

  dependencyLines = service:
    lib.concatMapStringsSep "\n" (dependency: "depends-on: ${dependency}") (dependencies service);

  environmentFile = service:
    pkgs.writeText "dinit-${service.name}.env" (
      lib.generators.toKeyValue { } (
        cfg.environment
        // lib.optionalAttrs ((cfg.path ++ (service.path or [ ])) != [ ]) {
          PATH = lib.makeBinPath (cfg.path ++ (service.path or [ ]));
        }
        // service.environment
      )
    );

  commandForDinit = service:
    lib.replaceStrings
      [ "-D %n" "--ready-notify=%n" "%n" ]
      [ "-D 3" "--ready-notify=3" service.name ]
      (toString service.command);

  common = service: ''
    ${lib.optionalString (service.description or null != null) "# ${service.description}"}
    ${dependencyLines service}
    ${lib.optionalString (service.user or null != null) "run-as = ${service.user}"}
    ${lib.optionalString (service.environment or { } != { })
      "env-file = ${environmentFile service}"}
    ${lib.optionalString ((service.notify or null) == "s6") "ready-notification = pipefd:3"}
  '';

  processService = name: service: ''
    type = process
    command = ${commandForDinit (service // { inherit name; })}
    restart = ${if (service.respawn or false) || (service.restart or 0) != 0 then "true" else "false"}
    ${lib.optionalString (service.log or false != false) "logfile = /var/log/${name}.log"}
    ${common service}
  '';

  taskService = name: task: ''
    type = scripted
    command = ${task.command}
    restart = false
    ${common task}
  '';

  initrdTaskService = name: task:
    taskService name (
      task
      // {
        command = lib.replaceStrings [ "${pkgs.busybox}/bin/loadkmap" ] [ "/bin/busybox loadkmap" ] (
          toString task.command
        );
      }
    );

  targetService = name: deps: ''
    type = internal
    ${lib.concatMapStringsSep "\n" (dependency: "depends-on: ${dependency}") deps}
  '';

  serviceFiles =
    lib.mapAttrs' (name: service: {
      name = "dinit.d/${name}";
      value = {
        mode = "direct-symlink";
        text = processService name service;
      };
    }) (enabled config.dinit.services)
    // lib.mapAttrs' (name: task: {
      name = "dinit.d/task-${name}";
      value = {
        mode = "direct-symlink";
        text = taskService name task;
      };
    }) rootTasks;

  ttyFiles = lib.mapAttrs' (name: tty: {
    name = "dinit.d/${name}";
    value = {
      mode = "direct-symlink";
      text = ''
        type = process
        command = ${
          if tty.command or null != null then
            tty.command
          else
            "${pkgs.util-linux}/bin/agetty --noclear ${tty.device}"
        }
        restart = true
      '';
    };
  }) (enabled config.dinit.ttys);

  runFiles = lib.mapAttrs' (name: run: {
    name = "dinit.d/run-${name}";
    value = {
      mode = "direct-symlink";
      text = taskService name run;
    };
  }) (enabled config.dinit.run);

  bootDependencies =
    (map (name: name) (lib.attrNames (enabled config.dinit.services)))
    ++ (map (name: "task-${name}") (lib.attrNames rootTasks))
    ++ (lib.attrNames (enabled config.dinit.ttys))
    ++ (map (name: "run-${name}") (lib.attrNames (enabled config.dinit.run)));

  initrdTasks = lib.filterAttrs (
    name: task: task.enable && name != "switch-root"
  ) config.boot.initrd.dinit.tasks;

  initrdTaskFiles = lib.mapAttrsToList (name: task: {
    target = "/etc/dinit.d/task-${name}";
    source = pkgs.writeText "dinit-initrd-task-${name}" (initrdTaskService name task);
  }) initrdTasks;

  initrdTaskNames = map (name: "task-${name}") (lib.attrNames initrdTasks);

  initrdServices = lib.filterAttrs (_: service: service.enable) config.boot.initrd.dinit.services;

  initrdServiceFiles = lib.mapAttrsToList (name: service: {
    target = "/etc/dinit.d/${name}";
    source = pkgs.writeText "dinit-initrd-service-${name}" (processService name service);
  }) initrdServices;

  initrdServiceNames = lib.attrNames initrdServices;

  initrdRuns = lib.filterAttrs (
    name: run: run.enable && name != "switch-root" && name != "setup-stdio"
  ) config.boot.initrd.dinit.run;

  initrdRunFiles = lib.mapAttrsToList (name: run: {
    target = "/etc/dinit.d/run-${name}";
    source = pkgs.writeText "dinit-initrd-run-${name}" (taskService name run);
  }) initrdRuns;

  initrdRunNames = map (name: "run-${name}") (lib.attrNames initrdRuns);

  targetFiles = lib.mapAttrs' (name: target: {
    name = "dinit.d/${name}";
    value = {
      mode = "direct-symlink";
      text = targetService name target.dependsOn;
    };
  }) (enabled cfg.targets);

  switchRootScript = pkgs.writeText "dinit-initrd-switch-root" ''
    set -eu

    stage2Init=/init
    for option in $(/bin/busybox cat /proc/cmdline); do
      case "$option" in
        init=*) stage2Init=''${option#init=} ;;
      esac
    done

    if [ ! -d /sysroot ] || ! /bin/busybox mountpoint -q /sysroot || [ ! -x "/sysroot$stage2Init" ]; then
      echo "dinit: real root is not ready" > /dev/console
      exec /bin/busybox reboot -f
    fi

    exec /bin/busybox switch_root /sysroot "$stage2Init"
  '';

  initrdBootDependencies = initrdServiceNames ++ initrdTaskNames ++ initrdRunNames;
in
{
  imports = [
    ./initrd.nix
    ./mount.nix
    ./options.nix
    ./stage1-options.nix
    ./tmpfiles.nix
  ];

  config = lib.mkIf cfg.enable {
    boot.init = "${cfg.package}/bin/dinit";

    environment.systemPackages = [ cfg.package ];

    environment.etc = serviceFiles // ttyFiles // runFiles // targetFiles // {
      "dinit.d/boot" = {
        mode = "direct-symlink";
        text = targetService "boot" bootDependencies;
      };
    };

    boot.initrd.contents = initrdServiceFiles ++ initrdTaskFiles ++ initrdRunFiles ++ [
      {
        target = "/etc/dinit.d/boot";
        source = pkgs.writeText "dinit-initrd-boot" ''
          type = internal
          depends-on: boot-complete
        '';
      }
      {
        target = "/etc/dinit.d/boot-complete";
        source = pkgs.writeText "dinit-initrd-boot-complete" ''
          type = scripted
          command = /bin/busybox touch /run/dinit-boot-complete
          restart = false
          ${lib.concatMapStringsSep "\n" (dependency: "depends-on: ${dependency}") initrdBootDependencies}
        '';
      }
      {
        target = "/etc/dinit.d/switch-root";
        source = pkgs.writeText "dinit-switch-root" ''
          type = scripted
          command = /bin/busybox sh /etc/dinit-switch-root
          restart = false
          ${lib.concatMapStringsSep "\n" (dependency: "depends-on: ${dependency}") (initrdServiceNames ++ initrdTaskNames ++ initrdRunNames)}
        '';
      }
      {
        target = "/etc/dinit-switch-root";
        source = switchRootScript;
      }
    ];

    assertions = [
      {
        assertion = lib.hasAttr "dinit" pkgs;
        message = "dinit.enable requires pkgs.dinit (or an explicit dinit.package).";
      }
    ];
  };
}
