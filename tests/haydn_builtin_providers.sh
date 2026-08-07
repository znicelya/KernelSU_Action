#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

out=$(CONFIG_ENV="${ROOT}/config/haydn.env" bash "${ROOT}/scripts/config.sh")
extra=$(printf '%s\n' "$out" | sed -nE 's/^  EXTRA_DEFCONFIG[[:space:]]+= (.*)$/\1/p' | tail -n1)

[ -n "$extra" ] || fail "could not read EXTRA_DEFCONFIG from config output"

for tok in \
	CONFIG_QCOM_RPMH=y \
	CONFIG_QCOM_COMMAND_DB=y \
	CONFIG_QCOM_RPMHPD=y \
	CONFIG_QCOM_SMEM=y \
	CONFIG_POWER_RESET_MSM=y \
	CONFIG_COMMON_CLK_QCOM=y \
	CONFIG_QCOM_CLK_RPMH=y \
	CONFIG_QTI_RPM_STATS_LOG=y \
	CONFIG_PINCTRL_MSM=y \
	CONFIG_PINCTRL_LAHAINA=y \
	CONFIG_HH_RM_DRV=y \
	CONFIG_HH_DBL=y \
	CONFIG_QSEECOM=y \
	CONFIG_HDCP_QSEECOM=y
do
	printf '%s' "$extra" | grep -Fq "$tok" \
		|| fail "expected ${tok} in haydn EXTRA_DEFCONFIG"
done

printf 'haydn builtin provider test passed\n'
