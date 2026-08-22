# AMD GPU: amdgpu is in-kernel and Mesa/RADV is the default Vulkan driver, so
# there is nothing to install. amdvlk usually regresses game performance.
{ ... }:

{
  hardware.graphics = {
    enable = true;
    # 32-bit Proton/Wine. programs.steam sets this too, but inside its own
    # mkIf — stated here so the driver stack stands alone without it.
    enable32Bit = true;
  };

  # Not set: hardware.amdgpu.initrd.enable. It only avoids a resolution change
  # partway through boot, and pulls amdgpu's ~500 firmware files (12-26 MiB)
  # into every generation's initrd to do it.
}
