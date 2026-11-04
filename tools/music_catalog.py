#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 assets/music/catalog.json 导出成人读的 assets/music/CATALOG.md。

用法：
    python tools/music_catalog.py

同时做基本校验：
  * active 曲目必须有文件且文件存在；
  * 同一个 slot 不能被两条 active 曲目同时声明（除非 level_scope 不重叠）；
  * intensity 必须在 1~5；
  * active/standby 曲目必须有 license。
有问题会把错误打印出来并返回非 0。
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "assets", "music", "catalog.json")
OUTPUT = os.path.join(ROOT, "assets", "music", "CATALOG.md")


def res_to_rel(path: str) -> str:
    if path.startswith("res://"):
        return path[len("res://"):]
    return path


def cell(value) -> str:
    if value is None or value == "":
        return "—"
    if isinstance(value, bool):
        return "是" if value else "否"
    if isinstance(value, list):
        return "、".join(str(v) for v in value) if value else "—"
    return str(value).replace("|", "\\|")


def license_cell(track: dict) -> str:
    lic = track.get("license")
    if not lic:
        return "—"
    parts = [str(lic.get("type", "?"))]
    if lic.get("author"):
        parts.append(str(lic["author"]))
    if lic.get("attribution_required"):
        parts.append("需署名")
    if lic.get("commercial_ok") is False:
        parts.append("不可商用")
    return " / ".join(parts)


def validate(tracks: list[dict]) -> list[str]:
    errors: list[str] = []
    slots: dict[str, list[tuple[str, list]]] = {}
    for t in tracks:
        tid = t.get("id", "?")
        status = t.get("status", "")
        intensity = t.get("intensity")
        if not isinstance(intensity, int) or not 1 <= intensity <= 5:
            errors.append(f"{tid}: intensity 必须是 1~5，当前 {intensity!r}")
        if status in ("active", "standby"):
            if not t.get("license"):
                errors.append(f"{tid}: {status} 曲目缺 license")
            if not t.get("file"):
                errors.append(f"{tid}: {status} 曲目缺 file")
            elif not os.path.exists(os.path.join(ROOT, res_to_rel(t["file"]))):
                errors.append(f"{tid}: 文件不存在 {t['file']}")
        if status == "active":
            for slot in t.get("slots") or []:
                slots.setdefault(slot, []).append((tid, t.get("level_scope") or ["all"]))
    for slot, owners in slots.items():
        if len(owners) < 2:
            continue
        for i in range(len(owners)):
            for j in range(i + 1, len(owners)):
                a_id, a_scope = owners[i]
                b_id, b_scope = owners[j]
                if "all" in a_scope or "all" in b_scope or set(a_scope) & set(b_scope):
                    errors.append(f"slot '{slot}' 被 {a_id} 和 {b_id} 同时占用且楼层重叠")
    return errors


def build_markdown(data: dict) -> str:
    tracks = data.get("tracks", [])
    active = [t for t in tracks if t.get("status") == "active"]
    standby = [t for t in tracks if t.get("status") == "standby"]
    missing = [t for t in tracks if t.get("status") == "missing"]

    lines: list[str] = []
    add = lines.append

    add("# 背景音乐曲库（自动生成，别手改）")
    add("")
    add(f"> 由 `tools/music_catalog.py` 从 `assets/music/catalog.json` 生成，"
        f"最后更新：{data.get('updated', '—')}。")
    add("> 要加歌/换歌/补缺口，改 JSON 再跑一次脚本，**不要直接改这个文件**。")
    add("")
    add(f"**统计**：在用 {len(active)} 首 · 备用 {len(standby)} 首 · 待补 {len(missing)} 条")
    add("")

    add("## 一、在用曲目")
    add("")
    add("| ID | 曲名 | 情绪 | 强度 | 状态 | 槽位 | 层角色 | 楼层 | 声音元素 | 授权 |")
    add("|---|---|---|---|---|---|---|---|---|---|")
    for t in active:
        add("| `{}` | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            t.get("id"), cell(t.get("title")), cell(t.get("emotion")), cell(t.get("intensity")),
            cell(t.get("states")), cell(t.get("slots")), cell(t.get("layer_role")),
            cell(t.get("level_scope")), cell(t.get("elements")), license_cell(t)))
    add("")

    add("## 二、备用曲目（已入库，未接入）")
    add("")
    add("| ID | 曲名 | 情绪 | 强度 | 建议用途 | 声音元素 | 授权 |")
    add("|---|---|---|---|---|---|---|")
    for t in standby:
        add("| `{}` | {} | {} | {} | {} | {} | {} |".format(
            t.get("id"), cell(t.get("title")), cell(t.get("emotion")), cell(t.get("intensity")),
            cell(t.get("notes")), cell(t.get("elements")), license_cell(t)))
    add("")

    add("## 三、待补曲目清单")
    add("")
    add("| 缺口 | 目标状态 | 情绪 | 强度 | 层角色 | 楼层 | 期望的声音元素 | 建议来源 |")
    add("|---|---|---|---|---|---|---|---|")
    for t in missing:
        add("| {} | {} | {} | {} | {} | {} | {} | {} |".format(
            cell(t.get("title")), cell(t.get("states")), cell(t.get("emotion")),
            cell(t.get("intensity")), cell(t.get("layer_role")), cell(t.get("level_scope")),
            cell(t.get("elements")), cell(t.get("notes"))))
    add("")

    add("## 四、按状态索引")
    add("")
    states: dict[str, list[str]] = {}
    for t in tracks:
        for s in t.get("states") or []:
            states.setdefault(s, []).append(
                f"{t.get('title')}（{t.get('status')}）")
    for s in sorted(states):
        add(f"- **{s}**：{('、'.join(states[s]))}")
    add("")

    add("## 五、按声音元素索引")
    add("")
    elements: dict[str, list[str]] = {}
    for t in tracks:
        for e in t.get("elements") or []:
            elements.setdefault(e, []).append(str(t.get("title")))
    for e in sorted(elements):
        add(f"- **{e}**：{('、'.join(elements[e]))}")
    add("")

    add("## 六、授权审计")
    add("")
    add("| ID | 授权 | 可商用 | 需署名 | 作者 | 来源 |")
    add("|---|---|---|---|---|---|")
    for t in tracks:
        lic = t.get("license") or {}
        add("| `{}` | {} | {} | {} | {} | {} |".format(
            t.get("id"), cell(lic.get("type")), cell(lic.get("commercial_ok")),
            cell(lic.get("attribution_required")), cell(lic.get("author")),
            cell(lic.get("source"))))
    add("")
    add("> 补素材站点：Audionautix（CC BY 4.0，**必须署名**）、Freesound（逐条看授权，"
        "避开 CC BY-NC）。新增曲目一律先确认 `commercial_ok` 再入库。")
    add("")
    return "\n".join(lines)


def main() -> int:
    if not os.path.exists(CATALOG):
        print(f"找不到 {CATALOG}", file=sys.stderr)
        return 1
    with open(CATALOG, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    errors = validate(data.get("tracks", []))
    if errors:
        print("校验失败：", file=sys.stderr)
        for e in errors:
            print("  -", e, file=sys.stderr)
        return 1

    md = build_markdown(data)
    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(md)
    print(f"OK -> {os.path.relpath(OUTPUT, ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
