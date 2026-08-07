#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

out=$(CONFIG_ENV="${ROOT}/config/haydn.env" bash "${ROOT}/scripts/config.sh")

config_value() {
	local key=$1
	printf '%s\n' "$out" \
		| sed -nE "s/^  ${key}[[:space:]]+= (.*)$/\1/p" \
		| tail -n1
}

allyes=$(config_value KERNEL_CONFIG_ALLYES_FRAGMENTS)
fragments=$(config_value KERNEL_CONFIG_FRAGMENTS)
extra=$(config_value EXTRA_DEFCONFIG)

[ "$allyes" = "vendor/haydn_GKI.config" ] \
	|| fail "haydn GKI fragment is not configured for all-yes conversion"
[ "$fragments" = "vendor/haydn_QGKI.config" ] \
	|| fail "haydn QGKI fragment is not the regular overlay"
[ "$extra" = "CONFIG_TMPFS_XATTR=y CONFIG_TMPFS_POSIX_ACL=y" ] \
	|| fail "haydn EXTRA_DEFCONFIG still contains hand-maintained provider overrides"

printf 'haydn profile test passed\n'
