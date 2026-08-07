#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

run_config() {
	local cfg=$1
	CONFIG_ENV="$cfg" bash "${ROOT}/scripts/config.sh" 2>&1
}

expect_config_failure() {
	local cfg=$1 expected=$2 out status
	set +e
	out=$(run_config "$cfg")
	status=$?
	set -e

	[ "$status" -ne 0 ] || fail "expected ${cfg} to fail validation"
	printf '%s' "$out" | grep -Fq "$expected" \
		|| fail "expected validation output to contain: ${expected}"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat >"${tmpdir}/sukisu-builtin-without-susfs.env" <<'EOF'
KERNEL_SOURCE=https://example.invalid/kernel.git
KERNEL_SOURCE_BRANCH=test
KERNEL_CONFIG=test_defconfig
KERNEL_IMAGE_NAME=Image
ARCH=arm64
KSU_VARIANT=sukisu-ultra
KSU_REF=builtin
ENABLE_SUSFS=false
EOF

expect_config_failure \
	"${tmpdir}/sukisu-builtin-without-susfs.env" \
	"KSU_VARIANT=sukisu-ultra with KSU_REF=builtin requires ENABLE_SUSFS=true"

printf 'config validation tests passed\n'
