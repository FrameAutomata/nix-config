# Android app development in Kotlin: the IDE and debugger, adb for a physical
# device, and a JDK for building from a terminal. Imported by frame-automata
# and frame-automobile, the machines Thomas develops on, and deliberately NOT by
# wonudesktop — same admin-vs-not split as dev-tools.nix and dev-databases.nix,
# whose family this joins.
#
# The SDK is NOT declared here. Studio's setup wizard and SDK Manager download
# it into ~/Android/Sdk, on purpose rather than through androidenv: nixpkgs
# wraps Studio in an FHS env precisely so the prebuilt tools those downloads
# contain (mksdcard, the emulator, ...) can run, while an SDK in the store is
# read-only. AGP could then never fetch a build-tools or platform version a
# project asks for, and every project's compileSdk would become an edit to this
# repo. The cost is that the SDK is per-user imperative state — README "Android
# development" has the first-run steps.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    android-studio
    android-tools # adb and fastboot; the udev side needs nothing, see below
    # For `./gradlew` in a terminal. Studio runs Gradle on its own bundled JBR
    # and ignores this; 21 matches that JBR so a terminal build and an IDE build
    # compile against the same JDK.
    jdk21
  ];

  # No programs.adb / adbusers: the option is removed from nixpkgs because
  # systemd 258+ ships a uaccess rule for ADB, ADB-DbC and fastboot interfaces
  # (70-uaccess.rules), so the logged-in seat user gets the device node without
  # a group.

  # AGP downloads aapt2 from Maven as a generic-Linux ELF whose interpreter is
  # /lib64/ld-linux-x86-64.so.2, which NixOS's stub loader refuses. Builds
  # launched from Studio run inside its FHS env and are fine; this is for the
  # ones started from a terminal. Both hosts already enable it for
  # claude-desktop (see their default.nix) — restated so this layer does not
  # silently depend on that.
  programs.nix-ld.enable = true;

  # What a terminal Gradle reads when a checkout has no local.properties, which
  # Studio writes per project and which is gitignored — i.e. any fresh clone.
  # This is Studio's own default SDK location on Linux. sessionVariables rather
  # than variables so a Studio started from the Plasma menu sees it too.
  environment.sessionVariables.ANDROID_HOME = "$HOME/Android/Sdk";
}
