# PipeWire, for every host with a speaker: the three workstations and the
# server's living-room TV seat (hosts/wheezertbts/tv.nix). Opt-in per host,
# like nvidia.nix — modules/common/default.nix stays a headless base, and a
# box that is only a server has no business running a sound daemon.
#
# Moved out of modules/workstation verbatim when the server grew a TV. The
# alternative was importing that module (Plasma, SDDM, Steam) onto the live
# server for these few lines.
#
# Deliberately NOT here: alsa.support32Bit. 32-bit-ness is a property of
# running Proton/Wine, not of having speakers, so it sits beside programs.steam
# in modules/workstation — the same split intel-gpu.nix makes for
# hardware.graphics.enable32Bit. On this server it would have pulled a whole
# i686 PipeWire closure (a second glibc, systemd and python, ~640 MB measured)
# onto a box that can execute none of it and runs no nix.gc timer.
#
# Note this also starts rtkit, a privileged daemon that hands out realtime
# scheduling — the price of glitch-free playback, and worth knowing about on a
# host whose day job is serving files.
{ ... }:

{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
