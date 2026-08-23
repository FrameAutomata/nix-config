# Intel Xe / Arc graphics: the kernel driver and Mesa's Vulkan driver are both
# in-tree, so only the VA-API userspace needs installing.
{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    # 32-bit Proton/Wine. programs.steam sets this too, but inside its own
    # mkIf — stated here so the driver stack stands alone without it.
    enable32Bit = true;

    # iHD, the VA-API driver for Gen8 and newer. Without it hardware video
    # decode is absent rather than merely slower: browsers and mpv fall back to
    # the CPU, which on a laptop is watts off the battery.
    extraPackages = [ pkgs.intel-media-driver ];
  };

  # Not set: LIBVA_DRIVER_NAME. iHD is the only VA-API driver installed here,
  # so libva's autodetect has nothing to disambiguate.
  #
  # Not set: extraPackages32. That would be a full i686 build of the driver for
  # 32-bit apps that decode video — rare enough to add on demand.
}
