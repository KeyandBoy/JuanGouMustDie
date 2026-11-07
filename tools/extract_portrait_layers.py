"""从 portrait 生成器的 .stex（WEBP 封装）批量提取图层 PNG。

用法：
  python tools/extract_portrait_layers.py <extracted_pck_dir> <out_dir>

PCK 里只有 .import/${name}.png-${hash}.stex 和对应的 ${name}.png.import 文本；
后者记录了原始 res://images/... 路径，用它还原目录结构。
"""

import io
import os
import re
import sys

from PIL import Image

RE_PATH = re.compile(r'path="res://\.import/([^"]+\.stex)"')
RE_SOURCE = re.compile(r'source_file="res://([^"]+)"')


def build_map(src_root):
    mapping = {}
    for dirpath, _dirs, files in os.walk(src_root):
        for name in files:
            if not name.endswith(".import"):
                continue
            text = open(os.path.join(dirpath, name), encoding="utf-8", errors="replace").read()
            m_path = RE_PATH.search(text)
            m_src = RE_SOURCE.search(text)
            if m_path and m_src:
                mapping[m_path.group(1)] = m_src.group(1)
    return mapping


def convert_tree(src_root, out_root):
    mapping = build_map(src_root)
    print("import map", len(mapping))
    import_dir = os.path.join(src_root, ".import")
    count = 0
    fails = []
    for name in sorted(os.listdir(import_dir)):
        if not name.endswith(".stex"):
            continue
        path = os.path.join(import_dir, name)
        rel = mapping.get(name)
        if not rel:
            fails.append("no source mapping: " + name)
            continue
        data = open(path, "rb").read()
        idx = data.find(b"RIFF")
        if idx < 0 or data[idx + 8:idx + 12] != b"WEBP":
            fails.append("not webp: " + name)
            continue
        try:
            im = Image.open(io.BytesIO(data[idx:]))
            im.load()
        except Exception as exc:  # noqa: BLE001
            fails.append("%s (%s)" % (name, exc))
            continue
        dest = os.path.join(out_root, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        im.save(dest)
        count += 1
    print("converted", count, "failed", len(fails))
    for f in fails[:12]:
        print("  FAIL", f)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    convert_tree(sys.argv[1], sys.argv[2])
