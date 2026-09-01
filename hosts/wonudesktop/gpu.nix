# RTX 2070 Super (Turing, TU104) — the display-and-games half of this host's
# GPU stack. modules/common/nvidia.nix carries what any NVIDIA host needs
# (driver, modesetting, hardware.graphics); this file is what a card that
# drives a monitor and runs Proton wants on top of it.
#
# Host-local rather than a modules/common/nvidia-desktop.nix: there is one
# such machine in this repo, and every choice below is about THIS GPU
# generation. Same reasoning as hosts/frame-automobile/power.nix.
{ ... }:

{
  # 32-bit Proton/Wine. programs.steam sets this too, inside its own mkIf —
  # stated here so the driver stack stands alone without it, exactly as
  # modules/common/amdgpu.nix does.
  hardware.graphics.enable32Bit = true;

  hardware.nvidia = {
    # Turing is precisely where upstream's advice flips. The nvidia module's
    # own assertion message: use the open kernel modules on Turing or later
    # (RTX series, GTX 16xx), the closed ones otherwise. This is a 2070 Super,
    # so it is on the recommended side of that line — and it is the side
    # NVIDIA develops against now, while the closed module is the one being
    # wound down. It also unlocks kernelSuspendNotifier below, which the
    # module turns on by itself for open + driver >= 595 (this tree ships
    # 595.71.05).
    #
    # The server stays on the closed module — modules/common/nvidia.nix
    # defaults it off and nothing there wants what the open one adds.
    #
    # If this machine ever misbehaves in a way that smells like the driver (a
    # session that will not start, a black screen after a wake), flipping this
    # to false is the first thing to try. It needs a REBOOT, not just a
    # switch: the kernel module already loaded is not swapped out underneath a
    # running system.
    open = true;

    # Saves VRAM contents on suspend and restores them on resume
    # (NVreg_PreserveVideoMemoryAllocations=1, written to /tmp — on disk here,
    # NixOS does not put /tmp on tmpfs by default). Without it NVIDIA
    # documents the contents as undefined across a suspend, which in practice
    # is corrupt windows or a black desktop after the machine wakes up. That
    # is the single failure this host's user is least equipped to diagnose,
    # and a desktop suspends every night.
    #
    # With `open` above, this rides the kernel's suspend notifier instead of
    # the older nvidia-suspend/nvidia-resume unit pair.
    powerManagement.enable = true;
  };

  # nvidiaSettings is left at its upstream default (true), so the nvidia-settings
  # GUI is installed. It is mostly an X11-era tool and does little under the
  # Wayland session Plasma starts by default — kept because when someone needs
  # to read a clock speed or a fan curve off the card, they need it right then.

  # Deliberately NOT installed: nvidia-vaapi-driver, the NVIDIA counterpart to
  # the iHD driver modules/common/intel-gpu.nix adds. That one is about
  # battery on a laptop; here it would save a 5800X3D from work it does not
  # notice, and the driver's failure mode is black video in a browser, which
  # costs far more than the decode it saves.
}
