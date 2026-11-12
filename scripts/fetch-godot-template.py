#!/usr/bin/env python3
"""Fetches one file out of Godot's export template archive (.tpz, a ZIP) with HTTP
range requests, so a build does not download the whole 1.3 GB for the one template
it needs. The file is checked against the CRC-32 the archive lists for it.

    python3 scripts/fetch-godot-template.py URL MEMBER OUT
"""
import struct
import sys
import urllib.request
import zlib


def get(url, start, end):
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def size(url):
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as r:
        return int(r.headers["Content-Length"]), r.geturl()


def main(url, member, out):
    total, url = size(url)
    tail = get(url, max(0, total - 65536), total - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        sys.exit("no end of central directory")
    cd_size, cd_off = struct.unpack("<II", tail[eocd + 12:eocd + 20])
    if cd_off == 0xFFFFFFFF or cd_size == 0xFFFFFFFF:
        loc = tail.rfind(b"PK\x06\x07")
        z64 = struct.unpack("<Q", tail[loc + 8:loc + 16])[0]
        rec = get(url, z64, z64 + 55)
        cd_size, cd_off = struct.unpack("<QQ", rec[40:56])
    cd = get(url, cd_off, cd_off + cd_size - 1)
    pos = 0
    while pos < len(cd):
        (sig, _, _, _, method, _, _, crc, csize, usize, nlen, xlen, clen, _, _, _,
         lho) = struct.unpack("<IHHHHHHIIIHHHHHII", cd[pos:pos + 46])
        name = cd[pos + 46:pos + 46 + nlen].decode()
        extra = cd[pos + 46 + nlen:pos + 46 + nlen + xlen]
        pos += 46 + nlen + xlen + clen
        if name != member:
            continue
        # zip64 extra field carries the real sizes/offset
        i = 0
        while i < len(extra):
            hid, hlen = struct.unpack("<HH", extra[i:i + 4])
            if hid == 1:
                vals = list(struct.unpack(f"<{hlen // 8}Q", extra[i + 4:i + 4 + hlen]))
                if usize == 0xFFFFFFFF:
                    usize = vals.pop(0)
                if csize == 0xFFFFFFFF:
                    csize = vals.pop(0)
                if lho == 0xFFFFFFFF:
                    lho = vals.pop(0)
            i += 4 + hlen
        head = get(url, lho, lho + 29)
        n2, x2 = struct.unpack("<HH", head[26:30])
        start = lho + 30 + n2 + x2
        data = get(url, start, start + csize - 1)
        if method == 8:
            data = zlib.decompress(data, -15)
        elif method != 0:
            sys.exit(f"unsupported compression {method}")
        if len(data) != usize or zlib.crc32(data) != crc:
            sys.exit(f"{member}: damaged download (size or CRC-32 does not match)")
        with open(out, "wb") as f:
            f.write(data)
        print(f"{member}: {usize} bytes -> {out}")
        return
    sys.exit(f"{member} not in archive")


if __name__ == "__main__":
    main(*sys.argv[1:4])
