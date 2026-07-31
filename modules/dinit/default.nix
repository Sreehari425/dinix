{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dinit;

  commandType = lib.types.coercedTo lib.types.package (value: "${value}") lib.types.str;

  rootTasks = lib.filterAttrs (
    name: task:
    task.enable
    && name != "ctrl-alt-del"
    # These tasks belong to the Finit-based boot layout.  Initrd module
    # loading is handled separately, while the test root already provides a
    # mounted Nix store and does not need wrapper generation during boot.
    && !(config.dinit.enable && lib.elem name [ "modprobe" "remount-nix-store" "suid-sgid-wrappers" ])
  ) config.finit.tasks;

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
      lib.filter (value: value != null) (map conditionToDependency (service.conditions or [ ]))
    );

  dependencyLines = service:
    lib.concatMapStringsSep "\n" (dependency: "depends-on: ${dependency}") (dependencies service);

  environmentFile = service:
    pkgs.writeText "dinit-${service.name}.env" (
      lib.generators.toKeyValue { } service.environment
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
    restart = ${if service.respawn or false then "true" else "false"}
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
    }) (enabled config.finit.services)
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
  }) (enabled config.finit.ttys);

  runFiles = lib.mapAttrs' (name: run: {
    name = "dinit.d/run-${name}";
    value = {
      mode = "direct-symlink";
      text = taskService name run;
    };
  }) (enabled config.finit.run);

  bootDependencies =
    (map (name: name) (lib.attrNames (enabled config.finit.services)))
    ++ (map (name: "task-${name}") (lib.attrNames rootTasks))
    ++ (lib.attrNames (enabled config.finit.ttys))
    ++ (map (name: "run-${name}") (lib.attrNames (enabled config.finit.run)));

  initrdTasks = lib.filterAttrs (
    name: task: task.enable && name != "switch-root"
  ) config.boot.initrd.finit.tasks;

  initrdTaskFiles = lib.mapAttrsToList (name: task: {
    target = "/etc/dinit.d/task-${name}";
    source = pkgs.writeText "dinit-initrd-task-${name}" (initrdTaskService name task);
  }) initrdTasks;

  initrdTaskNames = map (name: "task-${name}") (lib.attrNames initrdTasks);

  initrdServices = lib.filterAttrs (_: service: service.enable) config.boot.initrd.finit.services;

  initrdServiceFiles = lib.mapAttrsToList (name: service: {
    target = "/etc/dinit.d/${name}";
    source = pkgs.writeText "dinit-initrd-service-${name}" (processService name service);
  }) initrdServices;

  initrdServiceNames = lib.attrNames initrdServices;

  initrdRuns = lib.filterAttrs (
    name: run: run.enable && name != "switch-root" && name != "setup-stdio"
  ) config.boot.initrd.finit.run;

  initrdRunFiles = lib.mapAttrsToList (name: run: {
    target = "/etc/dinit.d/run-${name}";
    source = pkgs.writeText "dinit-initrd-run-${name}" (taskService name run);
  }) initrdRuns;

  initrdRunNames = map (name: "run-${name}") (lib.attrNames initrdRuns);

  customService = name: service: ''
    type = process
    command = ${service.command}
    restart = ${if service.restart then "true" else "false"}
    ${lib.optionalString (service.description != null) "# ${service.description}"}
    ${lib.concatMapStringsSep "\n" (dependency: "depends-on: ${dependency}") service.dependsOn}
    ${lib.optionalString (service.user != null) "run-as = ${service.user}"}
  '';

  customTask = name: task: ''
    type = scripted
    command = ${task.command}
    restart = false
    ${lib.optionalString (task.description != null) "# ${task.description}"}
    ${lib.concatMapStringsSep "\n" (dependency: "depends-on: ${dependency}") task.dependsOn}
  '';

  customFiles =
    lib.mapAttrs' (name: service: {
      name = "dinit.d/${name}";
      value = {
        mode = "direct-symlink";
        text = customService name service;
      };
    }) (enabled cfg.services)
    // lib.mapAttrs' (name: task: {
      name = "dinit.d/${name}";
      value = {
        mode = "direct-symlink";
        text = customTask name task;
      };
    }) (enabled cfg.tasks);

  targetFiles = lib.mapAttrs' (name: target: {
    name = "dinit.d/${name}";
    value = {
      mode = "direct-symlink";
      text = targetService name target.dependsOn;
    };
  }) (enabled cfg.targets);

  customBootDependencies =
    (lib.attrNames (enabled cfg.services)) ++ (lib.attrNames (enabled cfg.tasks));

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
  options.dinit = {
    enable = lib.mkEnableOption "dinit as the system service manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dinit;
      defaultText = lib.literalExpression "pkgs.dinit";
      description = "The dinit package used as PID 1 and for service control.";
    };

    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this dinit service" // { default = true; };
          command = lib.mkOption { type = commandType; description = "Command to supervise."; };
          dependsOn = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
          description = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          user = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          restart = lib.mkOption { type = lib.types.bool; default = true; };
        };
      });
      default = { };
      description = "Dinit process services.";
    };

    tasks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this dinit task" // { default = true; };
          command = lib.mkOption { type = commandType; description = "Command to execute."; };
          dependsOn = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
          description = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
        };
      });
      default = { };
      description = "Dinit scripted one-shot tasks.";
    };

    targets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this dinit target" // { default = true; };
          dependsOn = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
        };
      });
      default = { };
      description = "Dinit internal target services.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.init = "${cfg.package}/bin/dinit";

    environment.systemPackages = [ cfg.package ];

    environment.etc = serviceFiles // ttyFiles // runFiles // customFiles // targetFiles // {
      "dinit.d/boot" = {
        mode = "direct-symlink";
        text = targetService "boot" (bootDependencies ++ customBootDependencies);
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
