# Minimal dinit boot smoke test.
{
  name = "dinit.boot";

  nodes.machine =
    { pkgs, ... }:
    {
      dinit.enable = true;
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
    machine.succeed("test -f /run/dinit-native-api")
    machine.succeed("test -x /run/current-system/init")
    machine.succeed("grep -q '^ID=dinix$' /etc/os-release")
    machine.succeed("dinitctl start nix-daemon")
    machine.wait_until_succeeds("test -S /nix/var/nix/daemon-socket/socket", timeout=10)
    machine.succeed("dinitctl list | grep -q nix-daemon")
    machine.succeed("dinitctl list")
    machine.shutdown()
  '';
}
