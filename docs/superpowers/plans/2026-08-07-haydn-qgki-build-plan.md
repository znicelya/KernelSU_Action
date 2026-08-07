# Haydn QGKI Build Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the haydn KernelSU Action follow Xiaomi's QGKI fragment generation and build KernelSU v0.9.5 with valid manual hooks.

**Architecture:** Add an optional all-yes fragment phase to the existing `prepare_fragment_defconfig` merge pipeline. The haydn profile sends its GKI fragment through that phase and keeps only QGKI in the normal fragment phase. The official KernelSU manual hook path disables Kprobes before applying the legacy source hooks.

**Tech Stack:** Bash, Linux Kconfig fragment files, GitHub Actions shell steps, existing repository regression scripts.

## Global Constraints

- Preserve the existing base-only and ordinary-fragment configuration behavior.
- Match Xiaomi's order: base defconfig, GKI fragment with `=m` converted to `=y`, then QGKI fragment.
- Keep the haydn profile on official KernelSU `v0.9.5`, `KSU_HOOK_MODE=manual`, and `ENABLE_SUSFS=false`.
- Use ASCII edits and the repository's existing Bash helpers.
- Run tests before claiming completion and do not run a full local kernel build.

---

### Task 1: Add regression tests for official fragment ordering

**Files:**
- Create: `tests/config_fragments.sh`
- Test: `scripts/build.sh::prepare_fragment_defconfig` using a temporary fake kernel tree and fake `scripts/kconfig/merge_config.sh`

**Interfaces:**
- Consumes: `KERNEL_CONFIG_ALLYES_FRAGMENTS`, `KERNEL_CONFIG_FRAGMENTS`, and `prepare_fragment_defconfig`.
- Produces: A test that fails until all-yes fragments are generated and inserted before ordinary fragments.

- [ ] **Step 1: Write the failing fixture test**

Create a temporary arm64 kernel tree containing `gki_defconfig`, a GKI fragment
with `CONFIG_GKI_PROVIDER=m`, a QGKI fragment with `CONFIG_QGKI=y`, and a fake
merge script that concatenates its input fragments into `KCONFIG_CONFIG`. Set
`KERNEL_CONFIG_ALLYES_FRAGMENTS` to the GKI fragment and
`KERNEL_CONFIG_FRAGMENTS` to the QGKI fragment, source `scripts/build.sh`, run
`prepare_fragment_defconfig`, and assert the generated defconfig contains
`CONFIG_GKI_PROVIDER=y` and `CONFIG_QGKI=y`.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/config_fragments.sh
```

Expected: FAIL because the current implementation ignores
`KERNEL_CONFIG_ALLYES_FRAGMENTS` and does not generate the converted GKI
fragment.

### Task 2: Implement all-yes fragment merging

**Files:**
- Modify: `scripts/config.sh` in `DEFAULTS`
- Modify: `scripts/build.sh` in `prepare_fragment_defconfig`

**Interfaces:**
- Consumes: `KERNEL_CONFIG_ALLYES_FRAGMENTS` as a whitespace-separated list of
  paths relative to `arch/<ARCH>/configs`, matching the existing fragment
  field.
- Produces: Generated `<fragment-basename>_allyes.config` files and a merged
  device defconfig.

- [ ] **Step 1: Add the configuration default**

Add `[KERNEL_CONFIG_ALLYES_FRAGMENTS]=""` next to
`[KERNEL_CONFIG_FRAGMENTS]` so config resolution exports the field and the
workflow can override it consistently.

- [ ] **Step 2: Generate and merge converted fragments**

Update `prepare_fragment_defconfig` to:

1. Return early only when both fragment lists are empty.
2. Resolve and validate paths from both lists.
3. For each all-yes fragment, create a sibling named
   `<basename-without-.config>_allyes.config` using
   `sed 's/=m$/=y/g'`.
4. Invoke `merge_config.sh -m` with the base defconfig, generated all-yes
   paths, and ordinary fragment paths in that order.
5. Report both fragment lists in the log.

- [ ] **Step 3: Run the focused test**

Run `bash tests/config_fragments.sh` and expect PASS.

### Task 3: Make haydn use the official QGKI profile shape

**Files:**
- Modify: `config/haydn.env`
- Modify: `tests/haydn_builtin_providers.sh`

**Interfaces:**
- Consumes: The all-yes fragment field from Task 2.
- Produces: A haydn profile with GKI all-yes conversion, QGKI overlay, and no
  fragile provider-symbol allowlist.

- [ ] **Step 1: Write the failing profile assertion**

Change the profile test to assert that the resolved configuration contains
`KERNEL_CONFIG_ALLYES_FRAGMENTS=vendor/haydn_GKI.config`,
`KERNEL_CONFIG_FRAGMENTS=vendor/haydn_QGKI.config`, and no Qualcomm provider
entries in `EXTRA_DEFCONFIG`.

- [ ] **Step 2: Run the profile test to verify it fails**

Run `bash tests/haydn_builtin_providers.sh`.

Expected: FAIL against the current profile because it still lists raw GKI and
the manually maintained built-in provider block.

- [ ] **Step 3: Update the profile**

Set the two fragment fields as specified, retain only the generic TMPFS
entries in `EXTRA_DEFCONFIG`, and keep the existing haydn KernelSU/SUSFS
choices unchanged.

- [ ] **Step 4: Run the profile test**

Run `bash tests/haydn_builtin_providers.sh` and expect PASS.

### Task 4: Make official KernelSU manual hooks self-consistent

**Files:**
- Modify: `scripts/kernelsu.sh` in `ksu_hook_configs`
- Create: `tests/kernelsu_hook_config.sh`

**Interfaces:**
- Consumes: `ksu_hook_configs variant mode defconfig kernel_version`.
- Produces: `CONFIG_KPROBES=n` for official `kernelsu` manual mode; existing
  Kprobes mode behavior remains enabled.

- [ ] **Step 1: Write the failing hook configuration test**

Create a temporary defconfig containing `CONFIG_KPROBES=y`, source
`scripts/kernelsu.sh`, call `ksu_hook_configs kernelsu manual <file> 5.4`, and
assert `kconf_get` returns `n`. In the same test, use a second defconfig and
call `ksu_hook_configs kernelsu kprobes <file> 5.4`, asserting Kprobes is `y`.

- [ ] **Step 2: Run the test to verify it fails**

Run `bash tests/kernelsu_hook_config.sh`.

Expected: FAIL because the current official KernelSU manual branch is a no-op
and leaves `CONFIG_KPROBES=y`.

- [ ] **Step 3: Implement the minimal manual-mode change**

In the official `kernelsu` manual branch, call `kconf_disable` for
`CONFIG_KPROBES` and `CONFIG_KPROBE_EVENTS`; leave all other variant branches
unchanged.

- [ ] **Step 4: Run the focused hook test**

Run `bash tests/kernelsu_hook_config.sh` and expect PASS.

### Task 5: Verify, document, and commit

**Files:**
- Modify: `README.md` only if the new fragment field is documented by the
  existing configuration table

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: A tested commit pushed to the `haydn` branch.

- [ ] **Step 1: Run targeted and syntax tests**

Run:

```bash
bash tests/config_fragments.sh
bash tests/kernelsu_hook_config.sh
bash tests/config_validation.sh
bash tests/vendor_source_fixes.sh
bash tests/haydn_builtin_providers.sh
bash -n scripts/config.sh scripts/build.sh scripts/patches.sh scripts/kernelsu.sh tests/*.sh
git diff --check
```

- [ ] **Step 2: Review the diff**

Confirm only the fragment pipeline, KernelSU manual hook configuration, haydn
profile/tests, and required design/plan documentation changed.

- [ ] **Step 3: Commit and push**

Use:

```bash
git add config/haydn.env scripts/config.sh scripts/build.sh scripts/kernelsu.sh tests docs/superpowers
git commit -m "Fix haydn QGKI fragment build"
git -c http.version=HTTP/1.1 push origin haydn
```
