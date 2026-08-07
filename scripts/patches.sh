#!/usr/bin/env bash
# Kernel source patching: SUSFS, path_umount backport, hide_stuff, manual hooks.
#
# Everything here is idempotent and version-aware. Each step is skipped with a
# clear message when it is unnecessary (feature already present) rather than
# failing, because these trees are frequently already partially patched.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must point at the kernel source tree}
WORKSPACE=${WORKSPACE:-$(cd "${KERNEL_DIR}/.." && pwd)}
# Resolved from this file's location, not $PWD -- several helpers below run
# with the working directory changed into the kernel tree.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# ====================================================================== SUSFS

# susfs_branch_for KVER -- map a kernel version onto a susfs4ksu branch.
#
# susfs4ksu is branched per kernel version. The GKI branches are named after
# the Android release they ship with; where a kernel version spans two Android
# releases (5.10 -> android12/android13, 5.15 -> android13/android14) we pick
# the older, which is the one the vast majority of trees are based on.
# Override with SUSFS_BRANCH when that guess is wrong.
susfs_branch_for() {
	case "$1" in
		4.9)  echo "kernel-4.9" ;;
		4.14) echo "kernel-4.14" ;;
		4.19) echo "kernel-4.19" ;;
		5.4)  echo "kernel-5.4" ;;
		5.10) echo "gki-android12-5.10" ;;
		5.15) echo "gki-android13-5.15" ;;
		6.1)  echo "gki-android14-6.1" ;;
		6.6)  echo "gki-android15-6.6" ;;
		6.12) echo "gki-android16-6.12" ;;
		*)    echo "" ;;
	esac
}

susfs_checkout_ref() {
	local repo_dir=$1 ref=$2 resolved
	[ -n "$ref" ] || return 0
	git -C "$repo_dir" fetch -q --depth=1 origin "$ref" >/dev/null 2>&1 || return 1
	git -C "$repo_dir" checkout -q --detach "$ref" >/dev/null 2>&1 || return 1
	resolved=$(git -C "$repo_dir" rev-parse HEAD) || return 1
	[ "$resolved" = "$ref" ]
}

susfs_kernel_patch_for() {
	local kp=$1 branch=$2 custom=${SUSFS_KERNEL_PATCH:-} candidate repo_root

	if [ -n "$custom" ]; then
		case "$custom" in
			/*) return 1 ;;
		esac
		candidate="${REPO_ROOT}/${custom}"
		[ -f "$candidate" ] || return 1
		repo_root=$(realpath -e -- "$REPO_ROOT") || return 1
		candidate=$(realpath -e -- "$candidate") || return 1
		case "$candidate" in
			"${repo_root}"/*) ;;
			*) return 1 ;;
		esac
		printf '%s\n' "$candidate"
		return 0
	fi

	candidate="${kp}/50_add_susfs_in_${branch}.patch"
	if [ ! -f "$candidate" ]; then
		candidate=$(find "$kp" -maxdepth 1 -name '50_add_susfs_in_*.patch' | head -n1)
	fi
	[ -f "$candidate" ] || return 1
	printf '%s\n' "$candidate"
}

susfs_apply_strict() {
	local patch_file=$1 strip=${2:-1}
	patch -p"$strip" --dry-run --force --fuzz=0 --silent <"$patch_file" \
		>/dev/null 2>&1 || return 1
	patch -p"$strip" --force --fuzz=0 --no-backup-if-mismatch <"$patch_file" \
		>/dev/null
}

susfs_apply() {
	local repo=${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}
	local branch=${SUSFS_BRANCH:-auto}
	local ref=${SUSFS_REF:-}
	local kver
	kver=$(kernel_version "$KERNEL_DIR") || die "cannot read kernel version from ${KERNEL_DIR}/Makefile"

	group "Applying SUSFS"

	if [ "$branch" = "auto" ]; then
		branch=$(susfs_branch_for "$kver")
		[ -n "$branch" ] || die "no susfs4ksu branch is known for kernel ${kver}; set SUSFS_BRANCH explicitly.
       Available: $(git ls-remote --heads "$repo" | awk '{print $2}' | sed 's@refs/heads/@@' | tr '\n' ' ')"
		info "kernel ${kver} -> susfs branch '${branch}'"
	fi

	ref_exists "$repo" "$branch" \
		|| die "susfs4ksu has no branch '${branch}'.
       Available: $(git ls-remote --heads "$repo" | awk '{print $2}' | sed 's@refs/heads/@@' | tr '\n' ' ')"

	local susfs_dir="${WORKSPACE}/susfs4ksu"
	rm -rf "$susfs_dir"
	retry 3 git clone -q --depth=1 -b "$branch" "$repo" "$susfs_dir" \
		|| die "failed to clone ${repo} @ ${branch}"
	if [ -n "$ref" ]; then
		susfs_checkout_ref "$susfs_dir" "$ref" \
			|| die "failed to resolve SUSFS commit '${ref}' in ${repo}"
	fi

	local kp="${susfs_dir}/kernel_patches"
	[ -d "$kp" ] || die "unexpected susfs4ksu layout: ${kp} missing"

	# 1. Drop in the SUSFS sources. The non-GKI branches carry sus_su.c too.
	info "copying SUSFS sources into the kernel tree"
	cp -v "${kp}/fs/"*.c              "${KERNEL_DIR}/fs/"            2>/dev/null || true
	cp -v "${kp}/include/linux/"*.h   "${KERNEL_DIR}/include/linux/" 2>/dev/null || true

	# 2. Patch the kernel itself.
	local kernel_patch
	kernel_patch=$(susfs_kernel_patch_for "$kp" "$branch") \
		|| die "no usable SUSFS kernel patch was found"
	if [ -n "${SUSFS_KERNEL_PATCH:-}" ]; then
		( cd "$KERNEL_DIR" && susfs_apply_strict "$kernel_patch" 1 ) \
			|| die "the custom SUSFS kernel patch did not apply cleanly"
		if find "$KERNEL_DIR" -name '*.rej' -print -quit | grep -q .; then
			die "the custom SUSFS kernel patch produced reject files"
		fi
	else
		( cd "$KERNEL_DIR" && apply_patch "$kernel_patch" 1 ) \
			|| die "the SUSFS kernel patch did not apply cleanly.
       This usually means SUSFS_BRANCH does not match your kernel. Detected
       kernel ${kver}, used branch '${branch}'."
	fi

	# 3. Patch the KernelSU side -- but only when the variant does not already
	#    ship SUSFS support. SukiSU-Ultra's 'builtin' branch, for instance,
	#    declares CONFIG_KSU_SUSFS itself; applying the patch on top conflicts.
	local ksu_dir="${KERNEL_DIR}/${KSU_DIR:-KernelSU}"
	local ksu_patch="${kp}/KernelSU/10_enable_susfs_for_ksu.patch"

	if susfs_is_bundled; then
		info "${KSU_NAME:-the selected variant} already bundles SUSFS at ref '${KSU_REF_RESOLVED:-}'; skipping 10_enable_susfs_for_ksu.patch"
	elif [ ! -d "$ksu_dir" ]; then
		warn "KernelSU directory ${ksu_dir} not found; skipping the KernelSU-side SUSFS patch"
	elif [ ! -f "$ksu_patch" ]; then
		warn "branch ${branch} ships no KernelSU/10_enable_susfs_for_ksu.patch; skipping"
	else
		( cd "$ksu_dir" && apply_patch "$ksu_patch" 1 ) || {
			warn "the KernelSU-side SUSFS patch did not apply."
			warn "susfs4ksu's non-GKI branches were last updated in early 2025 and still"
			warn "target the old flat KernelSU layout; modern forks have since moved to a"
			warn "modular kernel/ tree. Try a variant/ref whose layout matches, or a fork"
			warn "that bundles SUSFS itself (e.g. KSU_VARIANT=sukisu-ultra KSU_REF=builtin)."
			die "SUSFS integration failed"
		}
	fi

	# Record the SUSFS version and exact inputs for the build summary.
	local sv resolved_ref
	sv=$(sed -nE 's/.*SUSFS_VERSION[[:space:]]+"([^"]+)".*/\1/p' \
		"${KERNEL_DIR}/include/linux/susfs.h" 2>/dev/null | head -n1)
	resolved_ref=$(git -C "$susfs_dir" rev-parse HEAD) \
		|| die "cannot resolve the checked-out SUSFS commit"
	export_env SUSFS_VERSION "${sv:-unknown}"
	export_env SUSFS_BRANCH_RESOLVED "$branch"
	export_env SUSFS_REF_RESOLVED "$resolved_ref"
	export_env SUSFS_PATCH_RESOLVED "$kernel_patch"
	ok "SUSFS ${sv:-?} applied from branch ${branch} @ ${resolved_ref}"
	summary "| SUSFS | \`${sv:-unknown}\` (branch \`${branch}\`, commit \`${resolved_ref}\`) |"
	endgroup
}

# Does the selected variant+ref already contain SUSFS?
susfs_is_bundled() {
	local bundled=${KSU_SUSFS_BUNDLED_REFS:--} ref=${KSU_REF_RESOLVED:-}
	[ "$bundled" = "-" ] && return 1
	local r
	for r in $bundled; do
		[ "$r" = "$ref" ] && return 0
	done
	# Fall back to inspecting the tree, which is authoritative.
	local ksu_dir="${KERNEL_DIR}/${KSU_DIR:-KernelSU}"
	[ -d "$ksu_dir" ] && grep -rqs 'CONFIG_KSU_SUSFS\|config KSU_SUSFS' "${ksu_dir}/kernel/Kconfig" 2>/dev/null
}

susfs_defconfig() {
	local defconfig=$1
	local ksu_dir="${KERNEL_DIR}/${KSU_DIR:-KernelSU}"

	# The SUSFS option set is NOT stable across branches, so it is discovered
	# from the Kconfig that was actually patched in rather than hardcoded.
	#
	# Concretely: the GKI branches ship SUSFS v2.x, which declares SUS_MAP and
	# has dropped the AUTO_ADD_*/SUS_OVERLAYFS/HAS_MAGIC_MOUNT knobs. The
	# non-GKI branches are still on v1.5.5 (last touched early 2025), which is
	# the exact opposite: it has the AUTO_ADD_* family and no SUS_MAP. A
	# hardcoded list is therefore wrong on one side or the other -- and wrong
	# in the silent direction, since an unknown symbol in a defconfig is simply
	# dropped, leaving the feature off with no warning.
	local syms
	syms=$(grep -rhoE '^[[:space:]]*config[[:space:]]+KSU_SUSFS[A-Z_]*' \
			"$ksu_dir" "${KERNEL_DIR}/fs/Kconfig" "${KERNEL_DIR}/drivers/kernelsu" 2>/dev/null \
		| awk '{print $2}' | sort -u)

	if [ -z "$syms" ]; then
		die "found no KSU_SUSFS Kconfig symbols to enable.
       The SUSFS sources are in the tree but nothing declares its options, so
       the feature would silently compile out and you would ship a kernel that
       looks patched but hides nothing. Check that the KernelSU-side patch
       applied, or pick a variant that bundles SUSFS."
	fi

	local s enabled=0
	for s in $syms; do
		case "$s" in
			# sus_su is the legacy in-kernel su backend, superseded by the
			# manager; overlayfs hiding conflicts with magic mount. Both are
			# off in the reference builds.
			KSU_SUSFS_SUS_SU | KSU_SUSFS_SUS_OVERLAYFS)
				kconf_disable "$defconfig" "CONFIG_${s}" ;;
			*)
				kconf_enable "$defconfig" "CONFIG_${s}"; enabled=$((enabled + 1)) ;;
		esac
	done
	ok "enabled ${enabled} SUSFS options discovered from Kconfig"
	debug "SUSFS symbols: $(printf '%s ' $syms)"
}

# =============================================================== path_umount

# path_umount() landed upstream in Linux 5.9. KernelSU uses it to unmount its
# own overlays before handing control to an app that is checking for root, so
# on older trees it has to be backported or module unmounting silently no-ops.
#
# The body below is upstream's, unchanged. It is inserted immediately before
# the comment that introduces the umount syscall, which puts it after
# do_umount() -- its only forward dependency -- in every tree from 4.9 to 5.4.
path_umount_apply() {
	local ns="${KERNEL_DIR}/fs/namespace.c"
	group "Backporting path_umount()"

	local kver
	kver=$(kernel_version "$KERNEL_DIR") || die "cannot read kernel version"

	if ver_ge "$kver" "5.9"; then
		info "kernel ${kver} already provides path_umount() upstream; nothing to do"
		endgroup; return 0
	fi
	[ -f "$ns" ] || die "fs/namespace.c not found"

	if grep -q '^int path_umount\|^static int path_umount' "$ns"; then
		info "path_umount() is already present in fs/namespace.c; nothing to do"
		endgroup; return 0
	fi

	local anchor='Now umount can handle mount points as well as block devices'
	grep -q "$anchor" "$ns" \
		|| die "could not find the insertion point in fs/namespace.c; patch this kernel manually"

	local snippet
	snippet=$(mktemp)
	# 'can_umount' is a separate helper upstream; guard it in case a partial
	# backport already added it.
	if ! grep -q 'static int can_umount' "$ns"; then
		cat >>"$snippet" <<'EOF'
static int can_umount(const struct path *path, int flags)
{
	struct mount *mnt = real_mount(path->mnt);

	if (flags & ~(MNT_FORCE | MNT_DETACH | MNT_EXPIRE | UMOUNT_NOFOLLOW))
		return -EINVAL;
	if (!may_mount())
		return -EPERM;
	if (path->dentry != path->mnt->mnt_root)
		return -EINVAL;
	if (!check_mnt(mnt))
		return -EINVAL;
	if (mnt->mnt.mnt_flags & MNT_LOCKED) /* Check optimistically */
		return -EINVAL;
	if (flags & MNT_FORCE && !capable(CAP_SYS_ADMIN))
		return -EPERM;
	return 0;
}

EOF
	fi
	cat >>"$snippet" <<'EOF'
int path_umount(struct path *path, int flags)
{
	struct mount *mnt = real_mount(path->mnt);
	int ret;

	ret = can_umount(path, flags);
	if (!ret)
		ret = do_umount(mnt, flags);

	/* we mustn't call path_put() as that would clear mnt_expiry_mark */
	dput(path->dentry);
	mntput_no_expire(mnt);
	return ret;
}

EOF

	# Insert before the line *above* the anchor comment body, i.e. at the '/*'
	# that opens it.
	local lineno
	lineno=$(grep -n "$anchor" "$ns" | head -n1 | cut -d: -f1)
	# Walk back to the opening '/*' of that comment block.
	local start=$lineno
	while [ "$start" -gt 1 ] && ! sed -n "${start}p" "$ns" | grep -q '/\*'; do
		start=$((start - 1))
	done

	local tmp
	tmp=$(mktemp)
	head -n "$((start - 1))" "$ns" >"$tmp"
	cat "$snippet" >>"$tmp"
	tail -n "+${start}" "$ns" >>"$tmp"
	mv "$tmp" "$ns"
	rm -f "$snippet"

	grep -q '^int path_umount' "$ns" || die "path_umount() insertion failed"
	ok "path_umount() backported into fs/namespace.c (kernel ${kver})"
	summary "| path_umount | backported (kernel ${kver}) |"
	endgroup
}

# ============================================================== extra patches

vendor_source_fixes_apply() {
	group "Applying vendor source fixes"

	local fixed=0
	local minidump="${KERNEL_DIR}/drivers/soc/qcom/msm_minidump.c"

	# Xiaomi haydn-r-oss enables QCOM_MINIDUMP, but the published source misses
	# the semicolon after this initcall and fails with clang at line 599.
	if [ -f "$minidump" ] &&
	   grep -qE '^subsys_initcall\(msm_minidump_init\)[[:space:]]*$' "$minidump"; then
		sed -i -E 's/^(subsys_initcall\(msm_minidump_init\))[[:space:]]*$/\1;/' "$minidump"
		ok "fixed missing semicolon in drivers/soc/qcom/msm_minidump.c"
		fixed=1
	fi

	if [ "$fixed" -eq 0 ]; then
		info "no known vendor source fixes needed"
	fi

	endgroup
}

SUKISU_PATCH_REPO=${SUKISU_PATCH_REPO:-https://github.com/ShirkNeko/SukiSU_patch.git}

# Clone the shared patch/tool repo once, on demand.
sukisu_patch_dir() {
	local dir="${WORKSPACE}/SukiSU_patch"
	if [ ! -d "$dir" ]; then
		retry 3 git clone -q --depth=1 "$SUKISU_PATCH_REPO" "$dir" \
			|| die "failed to clone ${SUKISU_PATCH_REPO}"
	fi
	printf '%s' "$dir"
}

# hide_stuff removes the most obvious KernelSU fingerprints from the build.
hide_stuff_apply() {
	group "Applying hide_stuff"
	local dir patch
	dir=$(sukisu_patch_dir)
	patch="${dir}/69_hide_stuff.patch"
	[ -f "$patch" ] || { warn "69_hide_stuff.patch not found in the patch repo; skipping"; endgroup; return 0; }
	( cd "$KERNEL_DIR" && apply_patch "$patch" 1 ) || warn "hide_stuff did not apply cleanly; continuing"
	endgroup
}

# Manual/syscall hook patches for pre-GKI trees, used when the fork expects the
# hooks to already exist in the kernel source rather than hooking via kprobes.
hooks_patch_apply() {
	local variant=${KSU_VARIANT:-none} kver
	kver=$(kernel_version "$KERNEL_DIR") || return 0

	group "Applying manual syscall hooks (kernel ${kver})"

	# ReSukiSU publishes scope-minimised hook patches keyed by kernel version.
	if [ "$variant" = "resukisu" ]; then
		local dir="${WORKSPACE}/ReSukiSU_Patches"
		[ -d "$dir" ] || retry 3 git clone -q --depth=1 \
			https://github.com/ReSukiSU/ReSukiSU_Patches.git "$dir" || true
		local p="${dir}/scope-minimized/kernel-${kver}.patch"
		if [ -f "$p" ]; then
			( cd "$KERNEL_DIR" && apply_patch "$p" 1 ) && { endgroup; return 0; }
		else
			info "ReSukiSU ships no scope-minimized patch for kernel ${kver}"
		fi
	fi

	# SukiSU's patch repo carries per-version hook patches too.
	if [ "$variant" = "sukisu-ultra" ]; then
		local dir p
		dir=$(sukisu_patch_dir)
		for p in "${dir}/${kver}/"*hook*.patch "${dir}/hooks/syscall_hooks.patch"; do
			[ -f "$p" ] || continue
			if ( cd "$KERNEL_DIR" && apply_patch "$p" 1 ); then endgroup; return 0; fi
		done
	fi

	# Fall back to the in-repo sed script, which is what this action shipped
	# historically and still works for the 4.9-5.4 KernelSU 0.9.x hook API.
	info "falling back to the bundled legacy hook script"
	( cd "$KERNEL_DIR" && bash "${REPO_ROOT}/patches/legacy_ksu_hooks.sh" )
	endgroup
}

# ======================================================================== KPM

# SukiSU-Ultra's Kernel Patch Module support needs a post-link step: the
# patch_linux tool rewrites the built Image and emits oImage.
kpm_patch_image() {
	local image=$1
	group "Applying KPM (patch_linux)"
	local dir tool
	dir=$(sukisu_patch_dir)
	tool="${dir}/kpm/patch_linux"
	[ -f "$tool" ] || die "kpm/patch_linux not found in ${SUKISU_PATCH_REPO}"
	chmod +x "$tool"
	( cd "$(dirname "$image")" && "$tool" "$(basename "$image")" ) \
		|| die "patch_linux failed"
	local out
	out="$(dirname "$image")/oImage"
	[ -f "$out" ] || die "patch_linux did not produce oImage"
	mv -f "$out" "$image"
	ok "KPM applied to $(basename "$image")"
	summary "| KPM | applied |"
	endgroup
}

# --------------------------------------------------------------------- main ---

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	case "${1:-all}" in
		susfs)        susfs_apply ;;
		path_umount)  path_umount_apply ;;
		hide_stuff)   hide_stuff_apply ;;
		hooks)        hooks_patch_apply ;;
		kpm)          kpm_patch_image "$2" ;;
		all)
			vendor_source_fixes_apply

			# Order matters and this is the tested one (4.19 + SukiSU builtin
			# + SUSFS 1.5.5, no rejects):
			#   path_umount and the hook patches both key off textual anchors
			#   in files that SUSFS later rewrites, so they go first.
			if is_true "${ENABLE_PATH_UMOUNT:-false}"; then path_umount_apply; fi

			# Driven by the *resolved* hook mode, not the raw setting, so that
			# KSU_HOOK_MODE=auto on a pre-GKI kernel still gets its hooks
			# patched in rather than only getting the Kconfig symbol set.
			if [ "${KSU_VARIANT:-none}" != "none" ] &&
			   [ "${KSU_HOOK_MODE_RESOLVED:-}" = "manual" ]; then
				hooks_patch_apply
			fi

			if is_true "${ENABLE_SUSFS:-false}";      then susfs_apply;      fi
			if is_true "${ENABLE_HIDE_STUFF:-false}"; then hide_stuff_apply; fi
			;;
		*) die "unknown patch step '$1'" ;;
	esac
fi
