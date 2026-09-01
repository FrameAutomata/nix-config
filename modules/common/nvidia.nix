# The NVIDIA driver stack, shared by the two hosts with an NVIDIA card:
# wheezertbts (GTX 1650, headless, NVENC transcoding for Jellyfin) and
# wonudesktop (RTX 2070 Super, a desktop that runs games). Only the parts both
# want live here — the gaming-side additions are hosts/wonudesktop/gpu.nix.
#
# Works headless: videoDrivers does not require services.xserver.enable —
# the driver's PCI modalias + udev kmod rules load the modules and create
# the /dev nodes with no X involved.
{ lib, ... }:

{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    # mkDefault, because open-vs-closed is a per-card decision rather than a
    # house style: upstream's own guidance is closed below Turing, open on
    # Turing and later. false is the conservative end and what the server
    # runs; hosts/wonudesktop/gpu.nix overrides it for a card on the other
    # side of that line, with the reasoning there.
    open = lib.mkDefault false;
  };
  # Fallback if device nodes are ever missing at boot on a headless host:
  #   hardware.nvidia.nvidiaPersistenced = true;
}
