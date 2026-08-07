# Haydn QGKI Build Configuration Design

## Problem

The Xiaomi `haydn-r-oss` tree generates a QGKI defconfig in this order:

1. `gki_defconfig`
2. `haydn_GKI.config` with every `=m` entry converted to `=y`
3. `haydn_QGKI.config`

The Action currently merges the raw GKI fragment, which leaves built-in QGKI
callers linked against module-only providers. The build then fails at the
`vmlinux` link stage with many unrelated undefined symbols.

The profile also selects KernelSU `v0.9.5` with direct manual hooks. That
KernelSU release defines its direct-hook state variables only when
`CONFIG_KPROBES` is disabled. The current profile leaves Kprobes enabled, so
the legacy hook patch creates undefined `ksu_*_hook` references.

## Design

Add an optional `KERNEL_CONFIG_ALLYES_FRAGMENTS` configuration field. For each
listed fragment, `prepare_fragment_defconfig` creates a generated companion
fragment by changing only line-ending `=m` values to `=y`. The merge order is
the base defconfig, generated all-yes fragments, and ordinary fragments. This
matches Xiaomi's `scripts/gki/generate_defconfig.sh` behavior while keeping
the Action independent of vendor-specific helper scripts.

Configure haydn with:

```text
KERNEL_CONFIG=gki_defconfig
KERNEL_CONFIG_ALLYES_FRAGMENTS=vendor/haydn_GKI.config
KERNEL_CONFIG_FRAGMENTS=vendor/haydn_QGKI.config
```

Remove the profile's manually maintained Qualcomm provider list. The official
GKI conversion supplies the complete built-in provider set and avoids another
round of symbol-by-symbol link fixes.

The all-yes conversion also keeps `QCOM_MINIDUMP` built in by making its
`QCOM_SMEM` and `POWER_RESET_MSM` dependencies built in. The existing
vendor source fix must therefore preserve `subsys_initcall` and only add the
semicolon missing from Xiaomi's source.

For the official `kernelsu` variant in `manual` mode, disable
`CONFIG_KPROBES` in `ksu_hook_configs`. Other variants and explicit Kprobes
mode retain their existing behavior.

## Scope and Non-goals

- Preserve existing fragment merging for profiles that do not set the new
  field.
- Match Xiaomi's order: base defconfig, GKI fragment with `=m` converted to
  `=y`, then QGKI fragment.
- Do not modify Xiaomi source files or vendor fragments.
- Do not change SUSFS, path_umount, packaging, or toolchain behavior.
- Keep generated fragments inside the ephemeral kernel workspace.

## Verification

- A fixture test must prove that a GKI `CONFIG_PROVIDER=m` reaches the merged
  defconfig as `CONFIG_PROVIDER=y` and that the QGKI fragment is applied after
  it.
- A KernelSU hook test must prove that official `kernelsu` manual mode writes
  `CONFIG_KPROBES` as disabled while Kprobes mode still enables it.
- The vendor source test must prove that the minidump fix preserves the
  built-in `subsys_initcall` level.
- Existing configuration, vendor-source, shell syntax, and profile tests must
  remain green.
