#!/usr/bin/env python3
"""B9：把所有 UI 图标重新装进 32x32 画布，内容最多 24x24（四周 4px 留白）。

不重新出图，只裁掉原有空白、等比缩放并居中，所以不会改变图标画风。
需要 Pillow：  python -m pip install pillow
用法：        python tools/repack_icons.py
"""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "art" / "ui" / "icons"
CANVAS = 32
CONTENT = 24


def repack(path: Path) -> tuple[int, int]:
    img = Image.open(path).convert("RGBA")
    bbox = img.getbbox()
    if bbox is None:
        return (0, 0)
    img = img.crop(bbox)
    w, h = img.size
    scale = min(CONTENT / float(w), CONTENT / float(h))
    nw = max(1, round(w * scale))
    nh = max(1, round(h * scale))
    if (nw, nh) != (w, h):
        img = img.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    out.paste(img, ((CANVAS - nw) // 2, (CANVAS - nh) // 2), img)
    out.save(path)
    return (nw, nh)


def main() -> None:
    files = sorted(p for p in ICON_DIR.glob("*.png") if p.is_file())
    if not files:
        raise SystemExit(f"no icons in {ICON_DIR}")
    for p in files:
        w, h = repack(p)
        print(f"{p.name:16s} content {w:2d}x{h:<2d} -> {CANVAS}x{CANVAS}")
    print(f"repacked {len(files)} icons")


if __name__ == "__main__":
    main()
