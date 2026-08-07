# haydn SUSFS Branch Design

## Goal

Create a dedicated `haydn-susfs` branch from `haydn` that builds the Xiaomi
`haydn-r-oss` kernel with SukiSU-Ultra builtin and working SUSFS support. Keep
the existing `haydn` branch unchanged as the known-good non-SUSFS build.

## Baseline

- Branch base: `haydn` at `3c31046`.
- Kernel source: `MiCode/Xiaomi_Kernel_OpenSource`, branch `haydn-r-oss`.
- Kernel version: Linux 5.4.61 QGKI.
- KernelSU variant: `sukisu-ultra`, ref `builtin`, manual hook mode.
- SUSFS source: `simonpunk/susfs4ksu`, branch `gki-android12-5.10`, pinned to
  `ee7dc7a03b7c836952cce55c5f3834de62a465d1` (SUSFS v2.2.0).

The upstream `kernel-5.4` integration patch does not apply directly to the
Xiaomi tree. A dry-run against the official source identified conflicts in
Xiaomi-specific namespace, procfs, readdir, and Android KABI code, plus a
`bootconfig.c` hook for a file that does not exist in this Android 11 tree.

## Configuration

The branch continues to use `config/haydn.env`. It switches the profile to:

```text
KSU_VARIANT=sukisu-ultra
KSU_REF=builtin
KSU_HOOK_MODE=manual
ENABLE_SUSFS=true
SUSFS_BRANCH=gki-android12-5.10
SUSFS_REF=ee7dc7a03b7c836952cce55c5f3834de62a465d1
SUSFS_KERNEL_PATCH=patches/haydn-susfs-v2.2.0-5.4.patch
```

`ENABLE_PATH_UMOUNT=true` remains enabled because Linux 5.4 lacks
`path_umount()`. KPM and hide_stuff remain disabled to keep the branch focused
on SUSFS compatibility and avoid adding unrelated patch interactions.

`scripts/config.sh` gains optional `SUSFS_REF` and `SUSFS_KERNEL_PATCH`
settings with empty defaults. Existing profiles therefore retain their current
behavior.

## Patch Integration

`scripts/patches.sh` keeps the generic SUSFS path as its default. When
`SUSFS_REF` is set, it checks out that exact commit after cloning the configured
branch and fails if the checkout cannot be verified. When
`SUSFS_KERNEL_PATCH` is set, it resolves the repository-relative path, requires
the file to exist, and applies it instead of the upstream generic kernel patch.

The local `patches/haydn-susfs-v2.2.0-5.4.patch` is derived from the pinned
upstream `50_add_susfs_in_gki-android12-5.10.patch`. It preserves the complete
feature set while adapting the conflicting hunks to Xiaomi's source:

- use Xiaomi's mount allocation and Android KABI layouts;
- adapt proc fd, fdinfo, task maps, and readdir hooks to their local function
  shapes;
- place the command-line spoof hook in `fs/proc/cmdline.c`, because this tree
  has no `fs/proc/bootconfig.c`;
- preserve all cleanly applicable upstream hooks without scripted fuzzy edits.

SUSFS source files continue to come from the pinned upstream checkout and
report version `v2.2.0`.
SukiSU-Ultra builtin already declares and implements the KernelSU-side SUSFS
interface, so the stale generic `10_enable_susfs_for_ksu.patch` remains skipped.

## Failure Behavior

The patch stage stops immediately when any of these conditions is true:

- the configured SUSFS branch or pinned commit cannot be fetched;
- the custom patch path is absent or outside the expected repository input;
- the custom patch does not apply cleanly;
- reject files are produced;
- copied SUSFS sources expose no Kconfig symbols after KernelSU installation.

The build must never continue with only a partial SUSFS integration.

## Tests

Extend the shell regression suite to cover:

- resolved haydn profile values for SukiSU-Ultra, the pinned SUSFS ref, and the
  custom patch path;
- custom patch selection over the upstream generic patch;
- exact commit checkout and verification;
- fatal behavior for a missing custom patch or invalid pin;
- unchanged behavior for profiles that leave the new settings empty.

Before publishing, apply the complete patch flow to the official local
`haydn-r-oss` source, run all regression and syntax checks, and verify that no
`.rej` files exist. Push `haydn-susfs`, dispatch the GitHub Actions kernel build
with `config/haydn.env`, and treat a successful image artifact as the final
acceptance criterion.

## Scope Boundaries

- Do not modify the existing `haydn` branch.
- Do not introduce a separate kernel source fork.
- Do not enable KPM or hide_stuff in this work.
- Preserve the user's existing unstaged `.gitignore` change and exclude it from
  SUSFS commits.
