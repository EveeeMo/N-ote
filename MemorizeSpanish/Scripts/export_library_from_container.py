#!/usr/bin/env python3
"""从 Xcode 下载的 .xcappdata 导出 MemorizeSpanish.library.v1 备份 JSON。"""

from __future__ import annotations

import json
import plistlib
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

CORE_DATA_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
FORMAT = "MemorizeSpanish.library.v1"
PREF_KEYS = (
    "reminder.enabled",
    "reminder.hour",
    "reminder.minute",
    "app.conjugation.enabledTensesJSON",
)


def cd_timestamp_to_iso(value: float | None) -> str | None:
    if value is None:
        return None
    dt = CORE_DATA_EPOCH + timedelta(seconds=float(value))
    # 与 Swift JSONEncoder.iso8601 对齐（UTC、秒级）
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def find_store(xcappdata: Path) -> Path:
    store = xcappdata / "AppData/Library/Application Support/default.store"
    if not store.is_file():
        raise FileNotFoundError(f"找不到 SwiftData 库：{store}")
    return store


def load_preferences(xcappdata: Path) -> dict[str, str]:
    plist = xcappdata / "AppData/Library/Preferences/com.eve.memorizespanish.plist"
    if not plist.is_file():
        return {}
    with plist.open("rb") as f:
        raw = plistlib.load(f)
    prefs: dict[str, str] = {}
    for key in PREF_KEYS:
        if key not in raw:
            continue
        val = raw[key]
        if isinstance(val, bool):
            prefs[key] = "true" if val else "false"
        else:
            prefs[key] = str(val)
    return prefs


def export_backup(xcappdata: Path, out_path: Path) -> None:
    store = find_store(xcappdata)
    conn = sqlite3.connect(f"file:{store}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA wal_checkpoint(FULL)")

        units = [
            {
                "stableId": r["ZSTABLEID"],
                "title": r["ZTITLE"],
                "bookId": r["ZBOOKID"],
                "sortOrder": int(r["ZSORTORDER"] or 0),
            }
            for r in conn.execute(
                "SELECT ZSTABLEID, ZTITLE, ZBOOKID, ZSORTORDER FROM ZTEXTBOOKUNIT ORDER BY ZSTABLEID"
            )
        ]
        unit_pk_to_stable = {
            int(r["Z_PK"]): r["ZSTABLEID"]
            for r in conn.execute("SELECT Z_PK, ZSTABLEID FROM ZTEXTBOOKUNIT")
        }

        review_by_word_pk: dict[int, dict] = {}
        for r in conn.execute(
            "SELECT Z_PK, ZWORD, ZNEXTREVIEW, ZINTERVALDAYS, ZEASEFACTOR, ZREPETITIONS FROM ZREVIEWITEM"
        ):
            if r["ZWORD"] is None:
                continue
            review_by_word_pk[int(r["ZWORD"])] = {
                "nextReview": cd_timestamp_to_iso(r["ZNEXTREVIEW"]),
                "intervalDays": float(r["ZINTERVALDAYS"] or 0),
                "easeFactor": float(r["ZEASEFACTOR"] or 2.5),
                "repetitions": int(r["ZREPETITIONS"] or 0),
            }

        words = []
        for r in conn.execute(
            """
            SELECT ZSTABLEID, ZDEDUPEKEY, ZSPANISH, ZCHINESE, ZPARTOFSPEECH, ZLEMMA,
                   ZUSERNOTE, ZCREATEDAT, ZLASTACTIVITYAT, ZUNIT, Z_PK
            FROM ZWORDENTRY
            ORDER BY ZSTABLEID
            """
        ):
            pk = int(r["Z_PK"])
            unit_pk = r["ZUNIT"]
            words.append(
                {
                    "stableId": r["ZSTABLEID"],
                    "dedupeKey": r["ZDEDUPEKEY"] or (r["ZSPANISH"] or "").strip().lower(),
                    "spanish": r["ZSPANISH"] or "",
                    "chinese": r["ZCHINESE"] or "",
                    "partOfSpeech": r["ZPARTOFSPEECH"] or "noun",
                    "lemma": r["ZLEMMA"],
                    "userNote": r["ZUSERNOTE"] or "",
                    "createdAt": cd_timestamp_to_iso(r["ZCREATEDAT"]),
                    "lastActivityAt": cd_timestamp_to_iso(r["ZLASTACTIVITYAT"] or r["ZCREATEDAT"]),
                    "unitStableId": unit_pk_to_stable.get(int(unit_pk)) if unit_pk is not None else None,
                    "review": review_by_word_pk.get(pk),
                }
            )

        plans = [
            {
                "planId": r["ZPLANID"],
                "nextGroupIndex": int(r["ZNEXTGROUPINDEX"] or 0),
                "lastGroupCountDayStart": cd_timestamp_to_iso(r["ZLASTGROUPCOUNTDAYSTART"]),
                "groupsCompletedToday": int(r["ZGROUPSCOMPLETEDTODAY"] or 0),
            }
            for r in conn.execute(
                "SELECT ZPLANID, ZNEXTGROUPINDEX, ZLASTGROUPCOUNTDAYSTART, ZGROUPSCOMPLETEDTODAY FROM ZLEARNINGPLANPROGRESS"
            )
        ]
    finally:
        conn.close()

    prefs = load_preferences(xcappdata)
    payload = {
        "format": FORMAT,
        "exportedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "exportedFromAppVersion": None,
        "exportedFromBundleId": "com.eve.memorizespanish",
        "metadata": {"source": "xcappdata-export"},
        "preferences": prefs or None,
        "units": units,
        "words": words,
        "learningPlans": plans,
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"导出完成：{out_path}")
    print(f"  单元 {len(units)} · 词条 {len(words)} · 学习计划 {len(plans)}")


def main() -> None:
    if len(sys.argv) < 2:
        print("用法: python3 export_library_from_container.py <path/to/*.xcappdata> [输出.json]")
        sys.exit(1)
    xcappdata = Path(sys.argv[1]).expanduser().resolve()
    if not xcappdata.suffix == ".xcappdata":
        raise SystemExit("请传入 .xcappdata 路径")
    if len(sys.argv) >= 3:
        out = Path(sys.argv[2]).expanduser().resolve()
    else:
        stamp = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
        out = xcappdata.parent / f"MemorizeSpanish-library-from-device-{stamp}.json"
    export_backup(xcappdata, out)


if __name__ == "__main__":
    main()
