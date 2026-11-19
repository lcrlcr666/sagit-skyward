#!/usr/bin/env python3
"""unpack_bootimg_v0.py — 解 Android boot image（v0 头）

为什么需要自带：
  Android 9 (Pie) 里 `unpack_bootimg.py` **根本不存在**（它随
  `system/tools/mkbootimg` 在 Android 10 才独立出来）。Pie 只有
  `system/core/mkbootimg/` 的 host 版 `mkbootimg`（只能打包，不能解包）。
  所以抽 TWRP 内核时用这个脚本自己按 v0 头解析。

v0 头布局（little-endian）：
  0   magic[8] = "ANDROID!"
  8   kernel_size     12  kernel_addr
  16  ramdisk_size    20  ramdisk_addr
  24  second_size     28  second_addr
  32  tags_addr       36  page_size
  40  header_version  44  os_version
  48  name[16]        64  cmdline[512]
  576 id[8*32]        832 extra_cmdline[1024]

用法：
  python3 unpack_bootimg_v0.py --boot_img twrp.img --out out/
"""
import argparse
import os
import struct
import sys


def align(n, page):
    return n if n % page == 0 else n + (page - n % page) if False else ((n + page - 1) // page) * page


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--boot_img', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--format', default='mkbootimg', help='兼容 AOSP 参数，忽略')
    args = ap.parse_args()

    with open(args.boot_img, 'rb') as f:
        data = f.read()

    if data[:8] != b'ANDROID!':
        print('!! 不是 boot image（前 8 字节不是 ANDROID!）', file=sys.stderr)
        print('   前 40 字节: %r' % data[:40], file=sys.stderr)
        return 2

    (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr,
     second_size, second_addr, tags_addr, page_size, header_version,
     os_version) = struct.unpack('<10I', data[8:48])

    if header_version not in (0, 1, 2):
        print('!! 不支持的 header_version=%d' % header_version, file=sys.stderr)
        return 3
    if page_size not in (2048, 4096, 8192, 16384, 65536):
        print('!! 异常 page_size=%d' % page_size, file=sys.stderr)
        return 3

    cmdline = data[64:576].split(b'\x00', 1)[0].decode('utf-8', 'replace')
    name = data[48:64].split(b'\x00', 1)[0].decode('utf-8', 'replace')

    print('magic=ANDROID!  page_size=%d  header_version=%d' % (page_size, header_version))
    print('kernel=%d  ramdisk=%d  second=%d' % (kernel_size, ramdisk_size, second_size))
    print('name=%s' % name)
    print('cmdline=%s' % cmdline)

    os.makedirs(args.out, exist_ok=True)

    off = page_size
    parts = []
    if kernel_size:
        parts.append(('kernel', off, kernel_size))
        off += align(kernel_size, page_size)
    if ramdisk_size:
        parts.append(('ramdisk', off, ramdisk_size))
        off += align(ramdisk_size, page_size)
    if second_size:
        parts.append(('second', off, second_size))
        off += align(second_size, page_size)
    if header_version == 2:
        # v2 有独立的 dtb / dtb_addr；但 sagit 是 v0（dtb 追加在 kernel 尾部）
        pass

    for nm, o, sz in parts:
        if o + sz > len(data):
            print('!! %s 越界（off=%d size=%d file=%d）' % (nm, o, sz, len(data)), file=sys.stderr)
            return 4
        path = os.path.join(args.out, nm)
        with open(path, 'wb') as f:
            f.write(data[o:o + sz])
        print('  写出 %s  %d 字节' % (path, sz))

    # 给 mkbootimg 用的元信息
    with open(os.path.join(args.out, 'info.txt'), 'w') as f:
        f.write('kernel_size=%d\nramdisk_size=%d\nsecond_size=%d\n'
                'page_size=%d\nheader_version=%d\ncmdline=%s\n'
                % (kernel_size, ramdisk_size, second_size, page_size, header_version, cmdline))
    return 0


if __name__ == '__main__':
    sys.exit(main())
