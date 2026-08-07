#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "${tmpdir}/drivers/soc/qcom"
cat >"${tmpdir}/drivers/soc/qcom/msm_minidump.c" <<'EOF'
static int __init msm_minidump_init(void)
{
	return 0;
}
subsys_initcall(msm_minidump_init)
EOF

export KERNEL_DIR="$tmpdir"
export WORKSPACE="$tmpdir"
. "${ROOT}/scripts/patches.sh"

vendor_source_fixes_apply

grep -Fxq 'subsys_initcall(msm_minidump_init);' \
	"${tmpdir}/drivers/soc/qcom/msm_minidump.c" \
	|| fail "msm_minidump initcall semicolon was not fixed"

printf 'vendor source fix tests passed\n'
