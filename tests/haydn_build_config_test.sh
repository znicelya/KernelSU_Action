#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

out=$(CONFIG_ENV="${ROOT}/config/haydn.env" bash "${ROOT}/scripts/config.sh" 2>&1)

config_value() {
	local key=$1
	printf '%s\n' "$out" \
		| sed -nE "s/^  ${key}[[:space:]]+= (.*)$/\1/p" \
		| tail -n1
}

allyes=$(config_value KERNEL_CONFIG_ALLYES_FRAGMENTS)
fragments=$(config_value KERNEL_CONFIG_FRAGMENTS)
extra=$(config_value EXTRA_DEFCONFIG)
ksu_variant=$(config_value KSU_VARIANT)
ksu_ref=$(config_value KSU_REF)
enable_susfs=$(config_value ENABLE_SUSFS)
susfs_branch=$(config_value SUSFS_BRANCH)
susfs_ref=$(config_value SUSFS_REF)
susfs_patch=$(config_value SUSFS_KERNEL_PATCH)

[ "$allyes" = "vendor/haydn_GKI.config" ] \
	|| fail "haydn GKI fragment is not configured for all-yes conversion"
[ "$fragments" = "vendor/haydn_QGKI.config" ] \
	|| fail "haydn QGKI fragment is not the regular overlay"
[ "$extra" = "CONFIG_TMPFS_XATTR=y CONFIG_TMPFS_POSIX_ACL=y" ] \
	|| fail "haydn EXTRA_DEFCONFIG still contains hand-maintained provider overrides"
[ "$ksu_variant" = "sukisu-ultra" ] \
	|| fail "haydn SUSFS build does not use SukiSU-Ultra"
[ "$ksu_ref" = "builtin" ] \
	|| fail "haydn SUSFS build does not use the builtin ref"
[ "$enable_susfs" = "true" ] || fail "haydn SUSFS is not enabled"
[ "$susfs_branch" = "kernel-5.4" ] \
	|| fail "haydn SUSFS branch is not pinned to kernel-5.4"
[ "$susfs_ref" = "76affd70abf61d77feb0a132f61365d6848505df" ] \
	|| fail "haydn SUSFS commit is not pinned"
[ "$susfs_patch" = "patches/haydn-susfs-5.4.patch" ] \
	|| fail "haydn custom SUSFS patch is not selected"

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

printf 'haydn build config tests passed\n'
