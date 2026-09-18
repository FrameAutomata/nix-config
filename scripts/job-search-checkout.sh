#!/usr/bin/env bash
# Create (or update) a job-search checkout for one person on this host.
#
#   sudo ./job-search-checkout.sh cory FrameAutomata/corys-job-search
#   sudo ./job-search-checkout.sh eli  FrameAutomata/elis-job-search
#
# ORDER MATTERS, and it is the thing most likely to waste an evening:
#   1. `agenix -e hosts/wheezertbts/secrets/job-search-<name>.age` (admin key)
#   2. nixos-rebuild switch          <- creates the jobsearch-<name> user
#   3. THIS SCRIPT                   <- needs that user to exist to chown
#   4. systemctl restart job-search-ui-<name>
# Between 2 and 3 the unit fails on a missing WorkingDirectory. That is
# expected, not a problem.
#
# Deliberately NOT done by the Nix module: the checkout is a git working copy
# whose career-ops/ data the UI rewrites on every status change, Refresh and
# Push. Nix owning it would mean either clobbering that state on every rebuild
# or pretending mutable state is declarative. A service that silently re-cloned
# a missing checkout would also turn a failed mount into a quiet data reset.
set -euo pipefail

name="${1:?usage: job-search-checkout.sh <name> <owner/repo>}"
repo="${2:?usage: job-search-checkout.sh <name> <owner/repo>}"
user="jobsearch-${name}"
dest="/var/lib/job-search/${name}"
secret="/run/agenix/job-search-${name}"

[[ $EUID -eq 0 ]] || { echo "run as root (the chown needs it)" >&2; exit 1; }
id "$user" >/dev/null 2>&1 || {
  echo "user $user does not exist — run nixos-rebuild switch first (step 2)" >&2; exit 1; }
[[ -r "$secret" ]] || {
  echo "$secret is not readable — is the .age created and the rebuild done?" >&2; exit 1; }

# The token the service already has. Read it here rather than asking for it
# again, so there is exactly one copy of it on this machine.
GH_TOKEN="$(grep -E '^GH_TOKEN=' "$secret" | cut -d= -f2-)"
[[ -n "$GH_TOKEN" ]] || { echo "no GH_TOKEN= line in $secret" >&2; exit 1; }
export GH_TOKEN

mkdir -p "$(dirname "$dest")"

if [[ -d "$dest/.git" ]]; then
  echo "==> $dest exists; fetching"
  sudo -u "$user" --preserve-env=GH_TOKEN git -C "$dest" fetch --quiet origin
  sudo -u "$user" --preserve-env=GH_TOKEN git -C "$dest" merge --ff-only origin/main
else
  echo "==> cloning $repo -> $dest"
  # Clone as the service user so every object is owned correctly from the
  # start; a root clone + chown leaves root-owned pack files on some setups.
  sudo -u "$user" --preserve-env=GH_TOKEN \
    gh repo clone "$repo" "$dest" -- --quiet
fi

# The remote must NOT carry the token: it would land in .git/config, be world-
# readable to anything that can read the checkout, and survive a token rotation
# as a stale credential. gh authenticates from GH_TOKEN in the environment,
# which systemd supplies from the same secret file.
sudo -u "$user" git -C "$dest" remote set-url origin "https://github.com/${repo}.git"

chown -R "$user:$user" "$dest"
chmod 750 "$dest"

echo "==> done. Next:"
echo "    systemctl restart job-search-ui-${name}"
echo "    systemctl status  job-search-ui-${name} --no-pager"
echo "    # career-ops/ is created by the first Refresh; no setup.sh, no npm, no venv."
