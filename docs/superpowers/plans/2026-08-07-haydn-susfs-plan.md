# haydn SUSFS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `haydn-susfs` build haydn Linux 5.4.61 with SukiSU-Ultra builtin and SUSFS v1.5.5 through a pinned source revision and a haydn-compatible kernel patch.

**Architecture:** Add optional SUSFS commit and patch-path settings while preserving generic behavior for existing profiles. The haydn profile selects a strict local patch derived from the pinned upstream `kernel-5.4` patch. Shell fixtures test selection and pinning, then the complete patch is applied to the official haydn source and verified by GitHub Actions.

**Tech Stack:** Bash, GNU `patch`, Git, GitHub Actions, Linux 5.4 kernel source

## Global Constraints

- The branch is `haydn-susfs`, based on `haydn` at `3c31046`.
- The profile uses `KSU_VARIANT=sukisu-ultra`, `KSU_REF=builtin`, and `ENABLE_SUSFS=true`.
- SUSFS uses `kernel-5.4` at `76affd70abf61d77feb0a132f61365d6848505df`.
- The custom kernel patch is `patches/haydn-susfs-5.4.patch`.
- Empty `SUSFS_REF` and `SUSFS_KERNEL_PATCH` preserve existing generic behavior.
- Do not modify the existing `haydn` branch, KPM, or hide_stuff behavior.
- Preserve the user's unstaged `.gitignore` modification and do not stage it.

---

### Task 1: Add Failing Regression Coverage

**Files:** Modify `tests/haydn_build_config_test.sh`; create `tests/susfs_branch_test.sh`.

**Interfaces:** The tests consume `scripts/config.sh` and future functions `susfs_checkout_ref(REPO_DIR, REF)` and `susfs_kernel_patch_for(KERNEL_PATCH_DIR, BRANCH)`.

- [ ] **Step 1: Extend the haydn test.** Use its existing `config_value` helper and `fail` helper to assert exact values `KSU_VARIANT=sukisu-ultra`, `KSU_REF=builtin`, `ENABLE_SUSFS=true`, `SUSFS_BRANCH=kernel-5.4`, `SUSFS_REF=76affd70abf61d77feb0a132f61365d6848505df`, and `SUSFS_KERNEL_PATCH=patches/haydn-susfs-5.4.patch`.
- [ ] **Step 2: Create the helper test.** Build a temporary bare Git repository with a `kernel-5.4` branch and known commit, source `scripts/patches.sh` with a temporary `KERNEL_DIR`, and assert that `susfs_checkout_ref` makes `git rev-parse HEAD` equal the known full SHA. Set `SUSFS_KERNEL_PATCH=patches/haydn-susfs-5.4.patch` and assert `susfs_kernel_patch_for` returns `${ROOT}/patches/haydn-susfs-5.4.patch`; unset it and assert the generic return is `$patch_dir/50_add_susfs_in_kernel-5.4.patch`. Run an invalid SHA in a subshell and require nonzero status.
- [ ] **Step 3: Run `bash tests/haydn_build_config_test.sh` and `bash tests/susfs_branch_test.sh`.** Expected: the profile assertion fails and the helper test reports missing functions. Observe this red state before production edits.

### Task 2: Add the Pinned Configuration Contract

**Files:** Modify `scripts/config.sh`, `config/haydn.env`, and `tests/haydn_build_config_test.sh`.

**Interfaces:** `config.sh` exports `SUSFS_REF` and `SUSFS_KERNEL_PATCH` for `patches.sh`.

- [ ] **Step 1: Add `[SUSFS_REF]=""` and `[SUSFS_KERNEL_PATCH]=""` beside the existing SUSFS defaults.** Do not require either field; empty values preserve generic behavior.
- [ ] **Step 2: Set the haydn profile to `KSU_VARIANT=sukisu-ultra`, `KSU_REF=builtin`, `KSU_HOOK_MODE=manual`, `ENABLE_KPM=false`, `ENABLE_SUSFS=true`, `SUSFS_BRANCH=kernel-5.4`, `SUSFS_REF=76affd70abf61d77feb0a132f61365d6848505df`, and `SUSFS_KERNEL_PATCH=patches/haydn-susfs-5.4.patch`.** Keep path_umount, compiler, fragment, image, and packaging values unchanged.
- [ ] **Step 3: Run `bash tests/haydn_build_config_test.sh`; it must pass.** Commit with `git add scripts/config.sh config/haydn.env tests/haydn_build_config_test.sh` and `git commit -m "Configure haydn SUSFS build profile"`.

### Task 3: Implement Pinning and Strict Patch Selection

**Files:** Modify `scripts/patches.sh`; test `tests/susfs_branch_test.sh`.

**Interfaces:** Add `susfs_checkout_ref(REPO_DIR, REF)` returning zero only when HEAD equals the requested commit; add `susfs_kernel_patch_for(KERNEL_PATCH_DIR, BRANCH)` printing the configured repository-relative patch or the existing generic fallback; export `SUSFS_REF_RESOLVED` and `SUSFS_PATCH_RESOLVED` from `susfs_apply`.

- [ ] **Step 1: Implement `susfs_checkout_ref`.** Use `git fetch -q --depth=1 origin "$ref"`, detached checkout, and `git rev-parse HEAD`; return nonzero for fetch, checkout, or verification failures. Call it after the SUSFS clone when `SUSFS_REF` is nonempty and make failure fatal with the URL and ref.
- [ ] **Step 2: Implement `susfs_kernel_patch_for`.** A nonempty `SUSFS_KERNEL_PATCH` must be relative, resolve beneath `REPO_ROOT`, and exist. An empty value must retain the current branch-specific `50_add_susfs_in_*.patch` lookup. Missing custom or generic patches become fatal in `susfs_apply`.
- [ ] **Step 3: Apply configured patches strictly.** Run `patch -p1 --dry-run --force --silent` before applying a custom patch, skip the existing fuzz fallback for it, and fail if any `*.rej` exists afterward. Keep generic patches on the existing `apply_patch` path.
- [ ] **Step 4: Keep `susfs_is_bundled` unchanged.** SukiSU-Ultra builtin must skip the stale KernelSU-side SUSFS patch. Export the resolved commit and patch path in build metadata.
- [ ] **Step 5: Run `bash tests/susfs_branch_test.sh` and `bash -n scripts/*.sh patches/*.sh tests/*_test.sh`; commit with `git add scripts/patches.sh tests/susfs_branch_test.sh` and `git commit -m "Support pinned haydn SUSFS patches"`.

### Task 4: Build the haydn Compatibility Patch

**Files:** Create `patches/haydn-susfs-5.4.patch`; verify official `Xiaomi_Kernel_OpenSource` at `haydn-r-oss`.

**Interfaces:** The patch consumes the upstream `kernel-5.4` patch at commit `76affd70abf61d77feb0a132f61365d6848505df` and produces a strict `-p1` patch with no rejects or fuzzy hunks.

- [ ] **Step 1: Create a temporary detached full-source worktree** at `haydn-r-oss`, expanding sparse checkout without changing the user's official source worktree.
- [ ] **Step 2: Apply the upstream patch with rejects enabled and retain all clean hunks.** Adapt `fs/namespace.c`, `fs/notify/fdinfo.c`, `fs/proc/fd.c`, `fs/proc/task_mmu.c`, `fs/readdir.c`, and `include/linux/mount.h` to Xiaomi's function and Android KABI layouts. Omit nonexistent `fs/proc/bootconfig.c` and add its guarded spoof hook to `fs/proc/cmdline.c`. Preserve all other hooks and Kconfig guards.
- [ ] **Step 3: Generate `patches/haydn-susfs-5.4.patch` with `git diff --no-ext-diff --binary`, then run `git apply --check --verbose patches/haydn-susfs-5.4.patch` against a second clean haydn tree.** Expected: all hunks apply without error, fuzz, or `.rej` files.
- [ ] **Step 4: Run the Action SUSFS stage against a clean temporary haydn tree with the pinned profile.** Verify logs contain the pinned commit, custom patch name, SUSFS version, and no rejects. Commit with `git add patches/haydn-susfs-5.4.patch` and `git commit -m "Add haydn SUSFS kernel compatibility patch"`.

### Task 5: Full Verification and Publishing

**Files:** Verify all `tests/*_test.sh`, `config/haydn.env`, and `.github/workflows/build-kernel.yml`.

**Interfaces:** Consume Tasks 1-4 and produce a pushed `haydn-susfs` branch with a successful kernel artifact.

- [ ] **Step 1: Run `for test in tests/*_test.sh; do bash "$test" || exit $?; done`, `bash -n scripts/*.sh patches/*.sh tests/*_test.sh`, profile validation for `config.env config/*.env`, and `git diff --check`.** All must exit zero.
- [ ] **Step 2: Run `git diff haydn...HEAD -- scripts patches config/haydn.env` and `git status --short --branch`.** Confirm only intended SUSFS changes are present and `.gitignore` remains unstaged.
- [ ] **Step 3: Push with `git push -u origin haydn-susfs`.** Dispatch the existing Build Kernel workflow on `haydn-susfs` with `config= config/haydn.env` and all override inputs set to `config`.
- [ ] **Step 4: Require a successful build job and Image or AnyKernel3 artifact.** Resolve logs must show SukiSU-Ultra builtin, the pinned SUSFS commit, and SUSFS v1.5.5 with no patch, defconfig, or compile error. Record the workflow URL and final commit.
