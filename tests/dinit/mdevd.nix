# Dinit and mdevd readiness integration test.
{
  name = "dinit.mdevd";

  nodes.machine =
    { pkgs, ... }:
    {
      dinit.enable = true;
      services.mdevd.enable = true;
      hardware.console.enable = false;

      dinit.tasks.native-api = {
        command = pkgs.writeShellScript "dinit-native-api" ''
          echo ready > /run/dinit-native-api
        '';
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("dinit")
    machine.wait_for_console_text("run-coldplug")
    machine.succeed("test -f /run/dinit-native-api")
    machine.succeed("dinitctl status mdevd")
    machine.succeed("test -x /run/current-system/init")
    machine.shutdown()
  '';
}
