#!/usr/bin/env bash
# Verify that the kernel-side ReSukiSU manual hooks are present.
#
# ReSukiSU does not hook via kprobe; the kernel source itself must call the
# ksu_handle_* entry points. Those calls are added by
# NonGKI_Kernel_Build_2nd's syscall_hook_patches.sh and are committed on this
# branch. If a future rebase drops them, fail loudly at build time instead of
# silently producing a boot image where root simply does not work.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# file -> symbol that must appear in it
declare -a CHECKS=(
  "fs/exec.c:ksu_handle_execveat"
  "fs/open.c:ksu_handle_faccessat"
  "fs/read_write.c:ksu_handle_sys_read"
  "fs/stat.c:ksu_handle_stat"
  "drivers/input/input.c:ksu_handle_input_handle_event"
  "kernel/reboot.c:ksu_handle_sys_reboot"
  "kernel/sys.c:ksu_handle_setresuid"
)

missing=0
for entry in "${CHECKS[@]}"; do
  file=${entry%%:*}
  sym=${entry##*:}

  if [[ ! -f "$ROOT/$file" ]]; then
    printf 'MISSING FILE  %s\n' "$file" >&2
    missing=$((missing + 1))
    continue
  fi

  if grep -q "$sym" "$ROOT/$file"; then
    printf 'ok    %-28s %s\n' "$file" "$sym"
  else
    printf 'FAIL  %-28s missing %s\n' "$file" "$sym" >&2
    missing=$((missing + 1))
  fi
done

if ((missing > 0)); then
  printf '\nERROR: %d ReSukiSU hook(s) missing; kernel-side patches are not applied.\n' "$missing" >&2
  exit 1
fi

printf 'All ReSukiSU manual hooks present.\n'
