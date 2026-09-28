#!/usr/bin/env python3
"""Create the known-good 32 MiB MTK boot image for Archimedes.

The template supplies the tested Android v1 header, command line and display
DTB. The newly built gzip kernel is used, while its generated DTB is replaced
with the template DTB, matching the proven boot packaging procedure.
"""
from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

PAGE_SIZE = 2048
BOOT_SIZE = 32 * 1024 * 1024
KERNEL_ADDR = 0x40080000
TAGS_ADDR = 0x47880000
BOOTOPT = b"bootopt=64S3,32S1,64S1"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"


def u32(buf: bytes, off: int) -> int:
    return struct.unpack_from("<I", buf, off)[0]


def trailing_fdt(blob: bytes) -> tuple[bytes, int]:
    pos = blob.rfind(FDT_MAGIC)
    while pos >= 0:
        if pos + 8 <= len(blob):
            size = struct.unpack_from(">I", blob, pos + 4)[0]
            if size >= 40 and pos + size == len(blob):
                return blob[pos:], pos
        pos = blob.rfind(FDT_MAGIC, 0, pos)
    raise ValueError("no trailing FDT found")


def cstring(buf: bytes, off: int, size: int) -> bytes:
    return buf[off : off + size].split(b"\0", 1)[0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", type=Path, required=True)
    ap.add_argument("--kernel", type=Path, required=True, help="Image.gz-dtb")
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()

    template = args.template.read_bytes()
    built = args.kernel.read_bytes()
    if len(template) != BOOT_SIZE or template[:8] != b"ANDROID!":
        raise ValueError("template must be an exact 32 MiB Android boot image")
    if u32(template, 12) != KERNEL_ADDR or u32(template, 32) != TAGS_ADDR:
        raise ValueError("template has unexpected load addresses")
    if u32(template, 36) != PAGE_SIZE or u32(template, 40) != 1:
        raise ValueError("template is not an Android v1 / 2048-byte image")
    if u32(template, 1644) != 1648:
        raise ValueError("template header_size is not 1648")
    if u32(template, 16) or u32(template, 24) or u32(template, 1632):
        raise ValueError("template contains ramdisk/second/recovery_dtbo data")
    cmdline = cstring(template, 64, 512) + b" " + cstring(template, 608, 1024)
    if BOOTOPT not in cmdline:
        raise ValueError("template is missing bootopt=64S3,32S1,64S1")
    template_kernel_size = u32(template, 8)
    template_dtb, template_dtb_offset = trailing_fdt(
        template[PAGE_SIZE : PAGE_SIZE + template_kernel_size]
    )
    if b"aw87329_pa" not in template_dtb:
        raise ValueError("template DTB does not contain the tested AW87329 node")

    built_dtb, built_dtb_offset = trailing_fdt(built)
    kernel_gzip = built[:built_dtb_offset]
    if kernel_gzip[:2] != b"\x1f\x8b":
        raise ValueError("Image.gz-dtb prefix is not gzip")
    combined = kernel_gzip + template_dtb
    if PAGE_SIZE + len(combined) > BOOT_SIZE:
        raise ValueError("kernel plus template DTB does not fit in 32 MiB")

    out = bytearray(BOOT_SIZE)
    out[:PAGE_SIZE] = template[:PAGE_SIZE]
    struct.pack_into("<I", out, 8, len(combined))
    out[PAGE_SIZE : PAGE_SIZE + len(combined)] = combined
    out[576:608] = hashlib.sha1(combined).digest() + bytes(12)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(out)
    if args.output.stat().st_size != BOOT_SIZE:
        raise ValueError("output is not exactly 32 MiB")
    out_dtb, _ = trailing_fdt(bytes(out[PAGE_SIZE : PAGE_SIZE + len(combined)]))
    if out_dtb != template_dtb:
        raise ValueError("template DTB changed during packaging")
    print(f"output={args.output}")
    print(f"kernel_gzip={len(kernel_gzip)} template_dtb={len(template_dtb)}")
    print(f"sha256={hashlib.sha256(out).hexdigest()}")


if __name__ == "__main__":
    main()
