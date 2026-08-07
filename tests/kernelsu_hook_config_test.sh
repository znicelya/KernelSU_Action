#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export KERNEL_DIR="$tmpdir"
export WORKSPACE="$tmpdir/workspace"
. "$ROOT/scripts/kernelsu.sh"

manual_defconfig="$tmpdir/manual_defconfig"
cat >"$manual_defconfig" <<'EOF'
CONFIG_KPROBES=y
CONFIG_KPROBE_EVENTS=y
EOF

ksu_hook_configs kernelsu manual "$manual_defconfig" 5.4
grep -Fxq '# CONFIG_KPROBES is not set' "$manual_defconfig" || fail "official KernelSU manual mode did not disable KPROBES"
grep -Fxq '# CONFIG_KPROBE_EVENTS is not set' "$manual_defconfig" || fail "official KernelSU manual mode did not disable KPROBE_EVENTS"

kprobes_defconfig="$tmpdir/kprobes_defconfig"
cat >"$kprobes_defconfig" <<'EOF'
# CONFIG_KPROBES is not set
# CONFIG_HAVE_KPROBES is not set
# CONFIG_KPROBE_EVENTS is not set
# CONFIG_KRETPROBES is not set
EOF

ksu_hook_configs kernelsu kprobes "$kprobes_defconfig" 5.4 \
	|| fail "explicit KernelSU kprobes mode returned failure"
grep -Fxq 'CONFIG_KPROBES=y' "$kprobes_defconfig" || fail "explicit KernelSU kprobes mode no longer enables KPROBES"

printf 'KernelSU hook config tests passed\n'
