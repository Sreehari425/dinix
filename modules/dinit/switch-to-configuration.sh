#!@bash@/bin/bash
set -euo pipefail

out="@out@"
installHook="@installHook@"
inhibitCheck="@inhibitCheck@"
dinit="@dinit@"
logger="@logger@"
coreutils="@coreutils@"
action="${1-}"

case "$action" in
  switch|boot|test) ;;
  *) echo "Usage: $0 [switch|boot|test]" >&2; exit 1 ;;
esac

if [[ "$action" != boot && "${NIXOS_NO_CHECK-}" != 1 ]]; then
  "$inhibitCheck" "$out"
fi

if [[ "$action" == switch || "$action" == boot ]]; then
  "$installHook" "$out"
fi

if [[ "${NIXOS_NO_SYNC-}" != 1 ]]; then
  "$coreutils/bin/sync" -f /nix/store || true
fi

[[ "$action" == boot ]] && exit 0

echo "activating the configuration..." >&2
res=0
"$out/activate" || res=2
if ! "$dinit/bin/dinitctl" reload; then
  (( res == 0 )) && res=3
fi
exit "$res"
