#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

remote="$tmpdir/susfs-remote.git"
seed="$tmpdir/susfs-seed"
clone_dir="$tmpdir/susfs-clone"
patch_dir="$tmpdir/kernel_patches"
mkdir -p "$patch_dir"

git init -q --bare "$remote"
git init -q "$seed"
git -C "$seed" config user.email test@example.invalid
git -C "$seed" config user.name susfs-test
printf 'fixture\n' >"$seed/50_add_susfs_in_kernel-5.4.patch"
git -C "$seed" add 50_add_susfs_in_kernel-5.4.patch
git -C "$seed" commit -qm 'fixture SUSFS patch'
git -C "$seed" branch -M kernel-5.4
git -C "$seed" remote add origin "$remote"
git -C "$seed" push -q -u origin kernel-5.4
expected_commit=$(git -C "$seed" rev-parse HEAD)
git clone -q -b kernel-5.4 "$remote" "$clone_dir"
cp "$seed/50_add_susfs_in_kernel-5.4.patch" "$patch_dir/"

export KERNEL_DIR="$tmpdir/kernel"
export WORKSPACE="$tmpdir/workspace"
mkdir -p "$KERNEL_DIR"
. "$ROOT/scripts/patches.sh"

susfs_checkout_ref "$clone_dir" "$expected_commit" \
	|| fail "SUSFS checkout rejected a valid commit"
[ "$(git -C "$clone_dir" rev-parse HEAD)" = "$expected_commit" ] \
	|| fail "SUSFS checkout did not resolve the requested commit"

SUSFS_KERNEL_PATCH=tests/haydn_build_config_test.sh
[ "$(susfs_kernel_patch_for "$patch_dir" kernel-5.4)" = \
	"${ROOT}/tests/haydn_build_config_test.sh" ] \
	|| fail "custom SUSFS patch was not selected"

saved_repo_root=$REPO_ROOT
test_repo="$tmpdir/repo"
outside_patch="$tmpdir/outside.patch"
mkdir -p "$test_repo"
printf 'outside\n' >"$outside_patch"
ln -s "$outside_patch" "$test_repo/escape.patch"
REPO_ROOT=$test_repo

SUSFS_KERNEL_PATCH=missing.patch
if susfs_kernel_patch_for "$patch_dir" kernel-5.4 >/dev/null; then
	fail "missing custom SUSFS patch was accepted"
fi

SUSFS_KERNEL_PATCH=escape.patch
if susfs_kernel_patch_for "$patch_dir" kernel-5.4 >/dev/null; then
	fail "custom SUSFS patch symlink escaped the repository"
fi

REPO_ROOT=$saved_repo_root

unset SUSFS_KERNEL_PATCH
[ "$(susfs_kernel_patch_for "$patch_dir" kernel-5.4)" = \
	"${patch_dir}/50_add_susfs_in_kernel-5.4.patch" ] \
	|| fail "generic patch fallback changed"

strict_kernel_dir="$tmpdir/strict-kernel"
mkdir -p "$strict_kernel_dir"
printf 'other\nline1\nline2\nline3\nline4\n' >"$strict_kernel_dir/fuzzy.txt"
fuzzy_patch="$tmpdir/fuzzy.patch"
cat >"$fuzzy_patch" <<'EOF'
diff --git a/fuzzy.txt b/fuzzy.txt
--- a/fuzzy.txt
+++ b/fuzzy.txt
@@ -1,5 +1,5 @@
 context-before
 line1
-line2
+changed
 line3
 line4
EOF

if (cd "$strict_kernel_dir" && susfs_apply_strict "$fuzzy_patch" 1); then
	fail "custom SUSFS patch accepted a fuzzy hunk"
fi

KSU_SUSFS_BUNDLED_REFS=builtin
KSU_REF_RESOLVED=builtin
susfs_is_bundled || fail "SukiSU builtin SUSFS support was not detected"
KSU_REF_RESOLVED=other
if susfs_is_bundled; then
	fail "unlisted KernelSU ref was treated as bundled"
fi

if (susfs_checkout_ref "$clone_dir" 0000000000000000000000000000000000000000); then
	fail "invalid SUSFS commit was accepted"
fi

printf 'SUSFS branch tests passed\n'
