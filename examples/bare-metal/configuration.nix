{ lib, pkgs, ... }:
{
  # Dinix uses Dinit unconditionally as PID 1.
  services.mdevd.enable = true;
  services.networkmanager.enable = true;
  services.dbus.enable = true;
  services.seatd.enable = true;

  networking.hostName = "dinix-example";

  # Generic UEFI boot configuration. Limine is Dinix's currently supported
  # bootloader. Removable installation works in VMs and does not require
  # efibootmgr to modify firmware variables.
  boot.loader.efi = {
    canTouchEfiVariables = false;
    efiSysMountPoint = "/boot";
  };
  programs.limine = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Format the target disk with these labels before installing:
  #   mkfs.ext4 -L DINIXROOT /dev/<root-partition>
  #   mkfs.vfat -F 32 -n DINIXBOOT /dev/<efi-partition>
  fileSystems."/" = {
    device = "/dev/disk/by-label/DINIXROOT";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/DINIXBOOT";
    fsType = "vfat";
  };

  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "sd_mod"
    "usb_storage"
    "usbhid"
    "xhci_pci"
  ];

  boot.kernelModules = [ "kvm" ];

  environment.systemPackages = with pkgs; [
    git
    vim
    pciutils
    usbutils
  ];
}
