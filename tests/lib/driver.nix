# dinix test driver - extends nixos test driver with DinitMachine support
{ pkgs }:

let
  nixosTestDriver = pkgs.python3Packages.callPackage (pkgs.path + "/nixos/lib/test-driver") {
    nixosTests = { }; # stub, only used for passthru.tests
  };
in
nixosTestDriver.overrideAttrs (old: {
  pname = "dinix-test-driver";

  postPatch = (old.postPatch or "") + ''
    cp ${./dinit_machine.py} test_driver/dinit_machine.py
  '';
})
