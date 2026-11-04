"""逐格生成漫画素材（只用 imagefree.net，失败就退避重试，不走 pollinations 兜底）。

原因：pollinations 的 flux 会画出照片级写实图 + 右下角水印，和「黑白漫画」完全不搭。

用法:
  python gen_panels.py tools/manifests/tyrant_intro_panels.json
"""
import json
import os
import sys
import time

import requests

ROOT = r"E:\computerProgram2\JuanGouMustDie"
RAW = os.path.join(ROOT, "tools", "_gen")
UA = {"User-Agent": "Mozilla/5.0", "Content-Type": "application/json"}


def log(msg):
    print(msg, flush=True)


def submit(prompt, ratio):
    body = json.dumps({"prompt": prompt, "aspect_ratio": ratio}).encode("utf-8")
    for attempt in range(6):
        r = requests.post("https://imagefree.net/api/generate", data=body, headers=UA, timeout=60)
        if r.status_code == 200:
            j = r.json()
            if j.get("taskId"):
                return j["taskId"]
        if r.status_code == 429:
            log("  429 rate limited, sleep 45s")
            time.sleep(45)
            continue
        log("  submit http %s: %s" % (r.status_code, r.text[:120]))
        time.sleep(10)
    raise RuntimeError("submit failed")


def poll(task_id, max_sec=300):
    waited = 0
    while waited < max_sec:
        time.sleep(3)
        waited += 3
        try:
            r = requests.get(
                "https://imagefree.net/api/generate/status",
                params={"taskId": task_id}, timeout=45)
        except Exception as e:
            log("  poll error: %s" % e)
            continue
        if r.status_code != 200:
            continue
        try:
            j = r.json()
        except Exception:
            continue
        st = j.get("status")
        if st == "completed" and j.get("image"):
            return j["image"]
        if st == "failed":
            raise RuntimeError("task failed: %s" % json.dumps(j)[:200])
    raise RuntimeError("timeout")


def download(url, dest):
    for attempt in range(4):
        try:
            r = requests.get(url, timeout=180, headers={"User-Agent": "Mozilla/5.0"})
            if r.status_code == 200 and len(r.content) > 5000:
                with open(dest, "wb") as f:
                    f.write(r.content)
                return True
            log("  download http %s len=%d" % (r.status_code, len(r.content)))
        except Exception as e:
            log("  download error: %s" % e)
        time.sleep(8)
    return False


def main():
    manifest = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "tools", "manifests", "tyrant_intro_panels.json")
    with open(manifest, "r", encoding="utf-8") as f:
        assets = json.load(f)
    force = "--force" in sys.argv
    only = ""
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = a.split("=", 1)[1]
    ok = fail = 0
    for a in assets:
        name = a["name"]
        dest = os.path.join(RAW, name + ".png")
        if only and name != only:
            continue
        if os.path.exists(dest) and not force:
            log("[skip] %s" % name)
            continue
        log("[gen ] %s (%s)" % (name, a.get("ratio", "1:1")))
        try:
            tid = submit(a["prompt"], a.get("ratio", "1:1"))
            url = poll(tid)
            if download(url, dest):
                log("  saved %s (%d bytes)" % (name, os.path.getsize(dest)))
                ok += 1
            else:
                fail += 1
        except Exception as e:
            log("  FAILED %s: %s" % (name, e))
            fail += 1
        time.sleep(4)
    log("DONE ok=%d fail=%d" % (ok, fail))


if __name__ == "__main__":
    main()
