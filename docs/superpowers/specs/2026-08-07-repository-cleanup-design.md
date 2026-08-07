# Repository Cleanup Design

## Goal

Organize the repository after the successful haydn kernel build without losing
regression coverage for the failures found during bring-up.

## Test Layout

Keep four focused shell regression tests, all using the `*_test.sh` suffix:

- `haydn_build_config_test.sh` combines the haydn profile assertions with the
  fragment merge-order and all-yes conversion test.
- `config_validation_test.sh` keeps invalid profile validation coverage.
- `kernelsu_hook_config_test.sh` keeps KernelSU manual and kprobes mode coverage.
- `vendor_source_fixes_test.sh` keeps the Qualcomm minidump source-fix coverage.

The haydn tests belong together because they jointly verify the checked-in
profile and the build helper behavior that interprets its GKI and QGKI
fragments. The other tests cover independent production behavior and remain
separate.

## Continuous Integration

CI path filters include `tests/**`, and the regression step executes only
`tests/*_test.sh`. Shell syntax and profile validation continue to cover all
production scripts and configuration profiles.

## Repository Files

Remove the tracked `docs/superpowers` planning artifacts after implementation.
Normalize the existing user-created `.gitignore` entry to `/docs/` so future
local process documents do not appear as repository changes.

Production scripts and `config/haydn.env` are intentionally unchanged.

## Verification

Run every final regression test, parse every configuration profile, check Bash
syntax for scripts, patches, and tests, and run `git diff --check` before the
cleanup commit is pushed.
