#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 Scripts/dele_a1_words.txt 等文件生成 Resources/BuiltinBooks/dele_a1.json。
每行格式：西语|中文|词性[|动词原形]
词性为 verb 时建议写原形；生成 JSON 时会写入 lemma 字段。

用法（在 Scripts 目录下）：
  python3 build_dele_vocab.py dele_a1 A1 dele_a1
  python3 build_dele_vocab.py dele_a2 A2 dele_a2
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RES = ROOT.parent / "MemorizeSpanish" / "Resources" / "BuiltinBooks"


def parse_line(line: str) -> dict:
    parts = [p.strip() for p in line.split("|")]
    if len(parts) < 3:
        raise ValueError(f"无效行: {line!r}")
    es, zh, pos = parts[0], parts[1], parts[2]
    lemma = parts[3] if len(parts) > 3 and parts[3] else None
    if pos == "verb" and not lemma:
        lemma = es
    w: dict = {"es": es, "zh": zh, "pos": pos, "note": None}
    if lemma:
        w["lemma"] = lemma
    return w


def build(words_file: Path, book_id: str, level_label: str, out_name: str) -> None:
    raw = words_file.read_text(encoding="utf-8")
    words: list[dict] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        words.append(parse_line(line))

    units = []
    group_size = 10
    for i in range(0, len(words), group_size):
        chunk = words[i : i + group_size]
        if not chunk:
            break
        g = i // group_size
        units.append(
            {
                "unitId": f"{book_id}.g{g:03d}",
                "title": f"DELE {level_label} · 第 {g + 1} 组",
                "bookId": book_id,
                "sortOrder": g,
                "words": chunk,
            }
        )

    out_path = RES / f"{out_name}.json"
    out_path.write_text(json.dumps(units, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已写入 {out_path}，共 {len(words)} 词，{len(units)} 组。")


def main() -> None:
    if len(sys.argv) != 4:
        print("用法: python3 build_dele_vocab.py <words.txt 前缀> <等级标签 A1> <bookId 如 dele_a1>")
        sys.exit(1)
    prefix, label, book_id = sys.argv[1], sys.argv[2], sys.argv[3]
    wf = ROOT / f"{prefix}_words.txt"
    if not wf.exists():
        print(f"找不到 {wf}")
        sys.exit(1)
    build(wf, book_id, label, book_id)


if __name__ == "__main__":
    main()
