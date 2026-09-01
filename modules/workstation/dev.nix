# Thomas's admin/dev layer: the tools that only matter on a machine this repo
# is edited from and the homelab is administered from. Imported by
# frame-automata and frame-automobile, and deliberately NOT by wonudesktop —
# that host runs the same Plasma base (modules/workstation) for someone who
# uses none of this, and an app menu full of editors, terminals and CLIs is a
# real cost on a machine whose user is new to the platform.
#
# The split is admin-vs-not, not desktop-vs-laptop: anything true of every
# interactive machine stays in modules/workstation/default.nix, so there is
# still one place to edit it.
#
# claude-code and headroom come from the overlays the flake's `shared` module
# applies, so this module is only complete when composed with it.
{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # editors / terminal
    neovim
    zed-editor
    ghostty
    # dev + homelab admin
    gh
    # Zed's Nix extension declares nil and nixd but downloads neither — it
    # only `which`es them, so an uninstalled server is silently no server.
    # nixd over nil for the NixOS option completion this repo is made of;
    # ~/.config/zed/settings.json points it at the flake and disables nil.
    nixd
    claude-code
    headroom # pkgs/headroom — context-compression proxy, `headroom wrap claude`
  ];

  # direnv + nix-direnv, so a checkout carrying an .envrc drops you into its
  # dev shell on cd rather than everyone remembering to type `nix develop`.
  #
  # nix-direnv (on by default under this option) is the reason this is
  # system-level rather than a per-project shell script: it caches each dev
  # shell's closure under that project's .direnv/ and registers it as a GC
  # root, so the nix.gc in modules/workstation cannot collect a toolchain a
  # checkout still depends on. That failure is worth avoiding specifically — a
  # pip venv built against a store python keeps a bare symlink into
  # /nix/store, so a gc that takes the interpreter away surfaces later as an
  # unrelated-looking missing .so rather than as anything pointing at the
  # collection.
  #
  # Opt-in per project regardless: direnv ignores an .envrc until it is
  # `direnv allow`ed. Needs a fresh login, since the shell hook is installed
  # at session start.
  programs.direnv.enable = true;

  # Weekly check for a newer NixOS stable release. NOTIFIES rather than
  # switching: there is no rolling "nixos-stable" alias to follow, and a
  # release hop carries breaking changes documented in the release notes.
  # A user service so the notification reaches the Plasma session.
  #
  # Here rather than in the workstation base because the answer is per
  # RELEASE, not per host: every workstation builds from the same
  # nixpkgs-workstation input, so all of them would report the same thing on
  # the same day. It belongs on the machines whose user can act on it — a
  # "read the release notes, then move this host" popup is noise on a machine
  # whose user does not deploy this repo.
  systemd.user.services.nixos-release-check = {
    description = "Check whether a newer NixOS stable release is available";
    startAt = "weekly";
    serviceConfig.Type = "oneshot";
    path = with pkgs; [
      curl
      gnugrep
      gnused
      coreutils
      libnotify
    ];
    script = ''
      set -eu
      current="${config.system.nixos.release}"
      newest=$(curl -sf --max-time 30 "https://nix-channels.s3.amazonaws.com/?delimiter=/" \
        | grep -oE 'nixos-[0-9]{2}\.[0-9]{2}/' \
        | sed 's#nixos-##; s#/##' \
        | sort -V | tail -1) || exit 0
      [ -n "$newest" ] || exit 0
      if [ "$newest" != "$current" ] \
         && [ "$(printf '%s\n%s\n' "$current" "$newest" | sort -V | tail -1)" = "$newest" ]; then
        echo "NixOS $newest is available (running $current)"
        # || true: no notification daemon (early login, SDDM greeter's own user
        # manager) must not fail the unit under set -e
        notify-send -u normal -i system-software-update \
          "NixOS $newest is available" \
          "Running $current. Read the release notes, then move this host to nixos-$newest and rebuild." || true
      else
        echo "Up to date: running $current, newest stable is $newest"
      fi
    '';
  };

  systemd.user.timers.nixos-release-check.timerConfig = {
    Persistent = true;
    RandomizedDelaySec = "6h";
  };
}
