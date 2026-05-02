#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从开放词频 CSV 生成 dele_a1_words.txt … dele_b2_words.txt（合规流程见 cefr_dictionary_README.txt）。

默认读 ./input/frequency.csv。CSV 需至少包含「排名或顺序」「词条」「词性」；
若含「英文释义」列可自动填入第二列（中文栏位暂用英文时，请后续人工替换为中文）。

支持格式（自动探测）：
  A) doozan/spanish_data frequency.csv 表头：
     count,spanish,pos,flags,usage
     行已按频率降序；排名 = 数据行顺序（第 1 行数据 = 排名 1）。
  B) 含列名 lemma / word 的通用 CSV
  C) 无表头：lemma, pos 或 lemma, count

使用前请将 frequency.csv 放到 input/ 目录（自行从 doozan/spanish_data 下载，遵守其 LICENSE）。
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEFAULT_INPUT = ROOT / "input" / "frequency.csv"
BANDS_PATH = ROOT / "cefr_rank_bands.yaml"

_DEFAULT_BANDS = {"a1_max_rank": 800, "a2_max_rank": 2500, "b1_max_rank": 6000, "b2_max_rank": 15000}


def load_bands() -> dict[str, int]:
    if not BANDS_PATH.exists():
        return dict(_DEFAULT_BANDS)
    out = dict(_DEFAULT_BANDS)
    for line in BANDS_PATH.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        k, v = k.strip(), v.strip()
        if k in out:
            out[k] = int(v)
    return out


def normalize_pos(raw: str) -> str:
    """将来源词性映射到 App 使用的 partOfSpeech（与 AddWordView 等一致）。"""
    r = raw.strip().lower()
    if r in ("none",):
        return "phrase"
    if r in ("pron", "art", "det"):
        return "phrase"
    if r in ("num",):
        return "noun"
    # doozan frequency.csv 中动词记为 v
    if r in ("v", "verb", "vblex"):
        return "verb"
    if r.startswith("n") or r in ("nc", "np", "noun"):
        return "noun"
    if r.startswith("adj"):
        return "adj"
    if r.startswith("adv"):
        return "adv"
    if r in ("prep", "pr"):
        return "prep"
    if r in ("conj", "c"):
        return "phrase"
    if r in ("intj", "ij", "interj", "interjection"):
        return "interj"
    if r in ("phrase", "phr"):
        return "phrase"
    return "noun"


def level_for_rank(rank: int, bands: dict[str, int]) -> str | None:
    if rank <= bands["a1_max_rank"]:
        return "dele_a1"
    if rank <= bands["a2_max_rank"]:
        return "dele_a2"
    if rank <= bands["b1_max_rank"]:
        return "dele_b1"
    if rank <= bands["b2_max_rank"]:
        return "dele_b2"
    return None


def parse_frequency_csv(path: Path) -> list[tuple[int, str, str, str | None]]:
    """
    返回 (rank, lemma, pos, gloss_en_optional)
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    if not lines:
        return []
    delim = "\t" if lines[0].count("\t") >= lines[0].count(",") else ","
    rows = list(csv.reader(lines, delimiter=delim))
    if not rows:
        return []

    header = [c.strip().lower() for c in rows[0]]
    header_markers = (
        "lemma",
        "word",
        "palabra",
        "rank",
        "freq",
        "count",
        "spanish",
        "pos",
    )
    has_header = any(h in header for h in header_markers)
    start = 1 if has_header else 0
    col_idx = {name: i for i, name in enumerate(header)} if has_header else {}

    out: list[tuple[int, str, str, str | None]] = []
    rank = 0
    for line in rows[start:]:
        if not line or not any(cell.strip() for cell in line):
            continue
        lemma = ""
        pos = "noun"
        gloss = None

        if has_header:
            if "spanish" in col_idx:
                lemma = line[col_idx["spanish"]].strip()
            elif "lemma" in col_idx:
                lemma = line[col_idx["lemma"]].strip()
            elif "word" in col_idx:
                lemma = line[col_idx["word"]].strip()
            else:
                lemma = line[0].strip()
            if "pos" in col_idx and len(line) > col_idx["pos"]:
                pos = line[col_idx["pos"]].strip()
            if "gloss" in col_idx and len(line) > col_idx["gloss"]:
                gloss = line[col_idx["gloss"]].strip() or None
            if "english" in col_idx and len(line) > col_idx["english"]:
                gloss = line[col_idx["english"]].strip() or None
        else:
            lemma = line[0].strip()
            if len(line) > 1 and not line[1].strip().isdigit():
                pos = line[1].strip()
            elif len(line) > 2:
                pos = line[2].strip()

        if not lemma or lemma.startswith("#"):
            continue
        rank += 1
        out.append((rank, lemma, pos, gloss))

    return out


def lemma_to_line(lemma: str, pos: str, gloss: str | None) -> str:
    pos_n = normalize_pos(pos)
    zh = gloss if gloss else f"（待译）{lemma}"
    if pos_n == "verb":
        return f"{lemma}|{zh}|verb|{lemma}"
    return f"{lemma}|{zh}|{pos_n}"


def main() -> None:
    input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INPUT
    bands = load_bands()
    if not input_path.exists():
        print(f"请将词频 CSV 放到: {DEFAULT_INPUT}", file=sys.stderr)
        print("或运行: python3 build_cefr_dele_words.py /path/to/frequency.csv", file=sys.stderr)
        print("来源示例: https://github.com/doozan/spanish_data 中的 frequency.csv（遵守 LICENSE）", file=sys.stderr)
        sys.exit(1)

    rows = parse_frequency_csv(input_path)
    buckets: dict[str, list[str]] = {"dele_a1": [], "dele_a2": [], "dele_b1": [], "dele_b2": []}

    for rank, lemma, pos, gloss in rows:
        lvl = level_for_rank(rank, bands)
        if lvl is None:
            continue
        if len(lemma) > 80:
            continue
        line = lemma_to_line(lemma, pos, gloss)
        buckets[lvl].append(line)

    for bid, lines in buckets.items():
        path = ROOT / f"{bid}_words.txt"
        path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
        print(f"写入 {path.name}：{len(lines)} 行")

    print("完成。请人工检查「（待译）」条目，将第二列改为中文后，再运行 build_dele_vocab.py。")


if __name__ == "__main__":
    main()
