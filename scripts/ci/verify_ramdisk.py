import sys, gzip, io, os

def parse_cpio(data):
    out = []
    off = 0
    while True:
        if data[off:off+6] not in (b'070701', b'070702'):
            break
        hdr = data[off:off+110]
        namesize = int(hdr[94:102], 16)
        filesize = int(hdr[54:62], 16)
        name = data[off+110:off+110+namesize-1].decode('utf-8', 'replace')
        out.append((name, filesize))
        off += 110 + namesize
        off = (off + 3) & ~3
        off += filesize
        off = (off + 3) & ~3
        if name == 'TRAILER!!!':
            break
    return out

p = sys.argv[1]
d = open(p, 'rb').read()
print('ramdisk first bytes:', d[:4].hex())
if d[:2] == b'\x1f\x8b':
    d = gzip.decompress(d)
    print('gunzip ok, size:', len(d))
entries = parse_cpio(d)
print('total entries:', len(entries))
want = ('init.recovery', 'sagit-', 'WCNSS_qcom_cfg.ini', 'wpa_supplicant.conf',
        'sbin/recovery', 'sbin/adbd', 'sbin/toybox', 'sbin/magiskboot')
for name, size in entries:
    if any(w in name for w in want):
        print(f'  {name}  {size}')
