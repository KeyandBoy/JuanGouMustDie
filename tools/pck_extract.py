"""Godot 4 PCK 解析/提取（pixel_art_portrait_generator 用）。

PCK 头：GDPC + 版本 + 文件表；文件表项为
  path_len(u32) path(补 4 字节) offset(u64) size(u64) md5(16) flags(u32)

用法：
  python tools/pck_extract.py <pck> <out_dir> [关键字]
"""

import os
import struct
import sys


def _try_parse(data, pos, has_flags, rel_base, file_base, limit=None):
    entries = []
    n = len(data)
    while pos + 4 <= n and (limit is None or len(entries) < limit):
        path_len = struct.unpack_from("<I", data, pos)[0]
        if path_len == 0 or path_len > 4096 or pos + 4 + path_len > n:
            return None
        raw = data[pos + 4:pos + 4 + path_len]
        if b"res://" not in raw and not raw.rstrip(b"\x00").startswith(("/", "assets", "images")):
            return None
        pos += 4 + path_len
        need = 8 + 8 + 16 + (4 if has_flags else 0)
        if pos + need > n:
            return None
        off, size = struct.unpack_from("<QQ", data, pos)
        pos += 16
        md5 = data[pos:pos + 16]
        pos += 16
        flags = 0
        if has_flags:
            flags = struct.unpack_from("<I", data, pos)[0]
            pos += 4
        if rel_base:
            off += file_base
        if off < 0 or off + size > n:
            return None
        entries.append((raw.rstrip(b"\x00").decode("utf-8", "replace"), off, size, flags, md5.hex()))
        if pos >= n:
            break
    return entries or None


def parse_pck(path):
    data = open(path, "rb").read()
    if data[:4] != b"GDPC":
        raise SystemExit("不是 GDPC PCK 文件")
    pack_version, ver_major, ver_minor, ver_patch = struct.unpack_from("<IIII", data, 4)
    engine = (ver_major, ver_minor, ver_patch)

    # Godot 3（pack_version=1）：头 84 字节 + 文件数(u32)，条目无 flags，offset 绝对
    # Godot 4（pack_version=2）：头 100 字节，条目带 flags
    candidates = []
    if pack_version <= 1:
        count = struct.unpack_from("<I", data, 84)[0]
        candidates.append((88, False, False, 0, count))
    else:
        flags = struct.unpack_from("<I", data, 20)[0]
        file_base = struct.unpack_from("<Q", data, 24)[0]
        candidates.append((100, True, bool(flags & 2), file_base, None))
        candidates.append((84, False, False, 0, None))

    for pos, has_flags, rel_base, file_base, limit in candidates:
        entries = _try_parse(data, pos, has_flags, rel_base, file_base, limit)
        if entries:
            return {
                "pack_version": pack_version,
                "engine": engine,
                "flags": struct.unpack_from("<I", data, 20)[0] if pack_version >= 2 else 0,
                "file_base": file_base,
                "data": data,
                "entries": entries,
            }
    raise SystemExit("无法解析 PCK 文件表（引擎 %s）" % (engine,))


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    pck = sys.argv[1]
    out_dir = sys.argv[2]
    keyword = sys.argv[3] if len(sys.argv) > 3 else ""
    info = parse_pck(pck)
    print("pack_version", info["pack_version"], "engine", info["engine"],
          "flags", info["flags"], "file_base", info["file_base"])
    data = info["data"]
    written = 0
    for name, off, size, flags, md5 in info["entries"]:
        if keyword and keyword not in name:
            continue
        rel = name.replace("res://", "")
        dest = os.path.join(out_dir, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(data[off:off + size])
        written += 1
    print("entries", len(info["entries"]), "written", written, "->", out_dir)


if __name__ == "__main__":
    main()
