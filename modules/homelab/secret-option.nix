# Shared shape for "path to an agenix secret the host must declare": the
# default resolves the secret at eval time, with a pointed error when the
# host forgot to declare it. Import with:
#   mkSecretOption = import ../secret-option.nix { inherit lib config; };
# (./secret-option.nix from modules/homelab itself.)
#
# Hosts overriding one of these must point at a runtime path (an
# age.secrets.*.path, /run/agenix/*) — never a repo path literal, which
# would copy the secret into the world-readable nix store.
{ lib, config }:
{
  secret,
  # the full option path, for the error message — keep in sync when renaming
  optionPath,
  hint,
  description,
}:
lib.mkOption {
  type = lib.types.path;
  default =
    (config.age.secrets.${secret} or (throw ''
      ${optionPath}: the host must declare age.secrets.${secret}
      (${hint})
    '')).path;
  defaultText = "config.age.secrets.${secret}.path";
  inherit description;
}
