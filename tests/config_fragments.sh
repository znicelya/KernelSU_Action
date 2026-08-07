#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

kernel_dir="$tmpdir/kernel"
mkdir -p \
	"$kernel_dir/arch/arm64/configs/vendor" \
	"$kernel_dir/scripts/kconfig"

cat >"$kernel_dir/arch/arm64/configs/gki_defconfig" <<'EOF'
CONFIG_BASE=y
EOF

cat >"$kernel_dir/arch/arm64/configs/vendor/haydn_GKI.config" <<'EOF'
CONFIG_GKI_PROVIDER=m
CONFIG_ORDER=GKI
EOF

cat >"$kernel_dir/arch/arm64/configs/vendor/haydn_QGKI.config" <<'EOF'
CONFIG_QGKI=y
CONFIG_ORDER=QGKI
EOF

cat >"$kernel_dir/scripts/kconfig/merge_config.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=$KCONFIG_CONFIG
: >"$output"
for input in "$@"; do
	[ "$input" = "-m" ] && continue
	cat "$input" >>"$output"
done
EOF
chmod +x "$kernel_dir/scripts/kconfig/merge_config.sh"

export KERNEL_DIR="$kernel_dir"
export WORKSPACE="$tmpdir/workspace"
export ARCH=arm64
export KERNEL_CONFIG=gki_defconfig
export KERNEL_CONFIG_ALLYES_FRAGMENTS=vendor/haydn_GKI.config
export KERNEL_CONFIG_FRAGMENTS=vendor/haydn_QGKI.config
export DEVICE=haydn

. "$ROOT/scripts/build.sh"
prepare_fragment_defconfig

generated="$kernel_dir/arch/arm64/configs/vendor/haydn_defconfig"
[ -f "$generated" ] || fail "generated defconfig was not created"
grep -Fxq 'CONFIG_GKI_PROVIDER=y' "$generated" || fail "GKI module was not converted to a built-in config"
grep -Fxq 'CONFIG_QGKI=y' "$generated" || fail "QGKI fragment was not merged"
[ "$(grep 'CONFIG_ORDER=' "$generated" | tail -n1)" = 'CONFIG_ORDER=QGKI' ] || fail "QGKI fragment was not applied after the all-yes GKI fragment"

printf 'config fragment tests passed\n'
