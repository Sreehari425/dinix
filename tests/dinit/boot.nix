# Minimal dinit boot smoke test.
{
  name = "dinit.boot";

  nodes.machine =
    { pkgs, ... }:
    {
      dinit.enable = true;
      services.mdevd.enable = true;

      dinit.tasks.native-api = {
        command = pkgs.writeShellScript "dinit-native-api" ''
          echo ready > /run/dinit-native-api
        '';
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_console_text("dinit")
    machine.succeed("test -f /run/dinit-native-api")
    machine.succeed("test -x /run/current-system/init")
    machine.succeed("dinitctl list")
    machine.shutdown()
  '';
}
