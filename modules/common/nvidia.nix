# NVIDIA proprietary driver stack for hardware transcoding (NVENC).
# Works headless: videoDrivers does not require services.xserver.enable —
# the driver's PCI modalias + udev kmod rules load the modules and create
# the /dev nodes with no X involved.
{ ... }:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
  };
  # Fallback if device nodes are ever missing at boot on a headless host:
  #   hardware.nvidia.nvidiaPersistenced = true;
}
