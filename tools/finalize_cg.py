"""把单幅过场原图（tools/_gen/<name>.png）裁白边 + 强制黑白单红后落到 art/cutscene/。

用法:
  python tools/finalize_cg.py intro_classroom intro_board intro_hall
"""
import os
import sys

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose_manga import ROOT, trim_white, unify_mono  # noqa: E402

RAW = os.path.join(ROOT, "tools", "_gen")
OUT = os.path.join(ROOT, "art", "cutscene")


def main():
    args = sys.argv[1:]
    dark = 1.0
    blur = 0.0
    names = []
    for a in args:
        if a.startswith("--dark="):
            dark = float(a.split("=", 1)[1])
        elif a.startswith("--blur="):
            blur = float(a.split("=", 1)[1])
        else:
            names.append(a)
    if not names:
        print("usage: python tools/finalize_cg.py [--dark=0.6] [--blur=2] <name> [name...]")
        return
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        src = os.path.join(RAW, name + ".png")
        if not os.path.exists(src):
            print("missing", src)
            continue
        img = Image.open(src).convert("RGB")
        before = img.size
        img = trim_white(img)
        img = unify_mono(img)
        if blur > 0.0:
            img = img.filter(ImageFilter.GaussianBlur(blur))
        if dark < 1.0:
            img = Image.eval(img, lambda v: int(v * dark))
        dst = os.path.join(OUT, name + ".png")
        img.save(dst)
        print("%s %s -> %s %s (dark=%.2f blur=%.1f)" % (name, before, img.size, dst, dark, blur))


if __name__ == "__main__":
    main()
