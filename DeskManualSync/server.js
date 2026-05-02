#!/usr/bin/env node
/**
 * 可部署在公网（https）或本地：静态网页 + BundledUnitDTO JSON，APP 拉取 GET /api/sync/unit（Bearer）。
 */
import cors from "cors";
import express from "express";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, "public");

const TOKEN = process.env.NOTE_DESK_SYNC_TOKEN ?? "CHANGE_ME_NOTE_DESK_SYNC";
const HOST = process.env.NOTE_DESK_SYNC_HOST ?? "0.0.0.0";
const PORT = Number.parseInt(process.env.PORT ?? "8787", 10);

const STORE_PATH = path.join(__dirname, "data", "manual-desk-store.json");

const MANUAL_META = Object.freeze({
  unitId: "unit.manual",
  title: "手动添加",
  bookId: "manual",
  sortOrder: 100,
});

function normalizeSpanish(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase();
}

/** 与 Swift `SpanishPOSInference` 中非 NLTagger 的规则尽量一致（多词条则混合为 phrase）。 */
function appPartOfSpeech(spanish) {
  const trimmed = String(spanish || "").trim();
  if (!trimmed) return "noun";
  const words = trimmed.split(/\s+/).filter(Boolean);
  if (words.length === 0) return "noun";

  function inferredPOSForSingleToken(word) {
    const cleaned = word.replace(/^[\s\p{P}]+|[\s\p{P}]+$/gu, "").trim().toLowerCase();
    if (!cleaned) return "noun";
    const lower = cleaned;
    const verbShort = new Set(["ir", "ser", "dar", "ver", "estar"]);
    if (verbShort.has(lower)) return "verb";
    if (lower.length >= 3 && /(ar|er|ir)$/.test(lower)) return "verb";
    if (lower.endsWith("mente")) return "adv";
    if (/(ción|sión|dad)$/u.test(lower)) return "noun";
    return "noun";
  }

  if (words.length === 1) return inferredPOSForSingleToken(words[0]);
  const tags = words.map(inferredPOSForSingleToken);
  const first = tags[0];
  return tags.every((t) => t === first) ? first : "phrase";
}

async function loadStore() {
  try {
    const raw = await fs.readFile(STORE_PATH, "utf8");
    const j = JSON.parse(raw);
    if (!Array.isArray(j.words)) j.words = [];
    if (typeof j.revision !== "number") j.revision = 1;
    return j;
  } catch {
    return { revision: 1, words: [] };
  }
}

async function saveStore(store) {
  await fs.mkdir(path.dirname(STORE_PATH), { recursive: true });
  await fs.writeFile(STORE_PATH, JSON.stringify(store, null, 2), "utf8");
}

function authBearer(req, res, next) {
  const hdr = req.headers.authorization || "";
  const m = /^Bearer\s+(.+)$/i.exec(hdr);
  const got = (m?.[1] || "").trim();
  if (!got || got !== TOKEN.trim()) {
    res.status(401).json({ error: "invalid_or_missing_token" });
    return;
  }
  next();
}

async function translateMyMemory(spanish) {
  const trimmed = spanish.trim();
  if (!trimmed) return "";
  const qs = new URLSearchParams({
    q: trimmed,
    langpair: "es|zh-CN",
  });
  const url = `https://api.mymemory.translated.net/get?${qs}`;
  const r = await fetch(url);
  if (!r.ok) throw new Error(`MyMemory HTTP ${r.status}`);
  const j = await r.json();
  return String(j?.responseData?.translatedText || "").trim();
}

async function buildSyncUnit(store) {
  return [
    {
      ...MANUAL_META,
      words: store.words.slice(),
    },
  ];
}

const TRUST_PROXY = Math.min(3, Math.max(0, Number.parseInt(process.env.TRUST_PROXY_HOPS ?? "1", 10) || 0));

const app = express();
app.disable("x-powered-by");
app.set("trust proxy", TRUST_PROXY);
app.use(
  cors({
    origin: true,
    methods: ["GET", "POST", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
    maxAge: 86400,
  })
);
app.use(express.json({ limit: "512kb" }));

app.get("/health", (_req, res) => res.json({ ok: true }));

app.use(express.static(ROOT));

app.post("/api/translate", async (req, res) => {
  try {
    const q = typeof req.body?.q === "string" ? req.body.q : "";
    const zh = await translateMyMemory(q);
    const pos = appPartOfSpeech(q);
    res.json({ zh, pos });
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
});

/** 网页展示当前服务端列表（结构与 sync 同源）。 */
app.get("/api/words", authBearer, async (_req, res) => {
  const store = await loadStore();
  res.json({ revision: store.revision ?? 1, words: store.words.slice() });
});

app.post("/api/word", authBearer, async (req, res) => {
  const es = typeof req.body?.es === "string" ? req.body.es.trim() : "";
  let zh = typeof req.body?.zh === "string" ? req.body.zh.trim() : "";
  let pos = typeof req.body?.pos === "string" ? req.body.pos.trim() : "";
  let lemma =
    typeof req.body?.lemma === "string" && req.body.lemma.trim()
      ? req.body.lemma.trim()
      : null;
  const note = typeof req.body?.note === "string" ? req.body.note.trim() : "";

  if (!es) return res.status(400).json({ error: "empty_es" });
  const key = normalizeSpanish(es);
  if (!key) return res.status(400).json({ error: "bad_es" });

  if (!zh) {
    try {
      const t = await translateMyMemory(es);
      if (t) zh = t;
    } catch {
      /* 允许只有 es，由用户在网页手写 */
    }
  }

  const inferred = appPartOfSpeech(es);

  const posOptions = new Set(["noun", "verb", "adj", "adv", "prep", "interj", "phrase"]);
  if (!pos || !posOptions.has(pos)) pos = inferred;

  if (pos === "verb") {
    lemma = lemma && lemma.length ? lemma : es;
  } else {
    lemma = null;
  }

  const store = await loadStore();
  const idx = store.words.findIndex((w) => normalizeSpanish(w.es) === key);
  const row = {
    es,
    zh,
    pos,
    lemma,
    note: note || null,
  };
  if (idx >= 0) store.words[idx] = row;
  else store.words.push(row);
  store.revision = (store.revision || 1) + 1;
  store.updatedAt = new Date().toISOString();

  await saveStore(store);
  res.json({ ok: true, revision: store.revision, count: store.words.length });
});

app.post("/api/word/delete", authBearer, async (req, res) => {
  const raw = typeof req.body?.es === "string" ? req.body.es : "";
  const key = normalizeSpanish(raw);
  if (!key) return res.status(400).json({ error: "bad_es" });
  const store = await loadStore();
  store.words = store.words.filter((w) => normalizeSpanish(w.es) !== key);
  store.revision = (store.revision || 1) + 1;
  store.updatedAt = new Date().toISOString();
  await saveStore(store);
  res.json({ ok: true, revision: store.revision });
});

/** APP 前台轮询调用：结构与教材 JSON `[BundledUnitDTO]` 一致。 */
app.get("/api/sync/unit", authBearer, async (_req, res) => {
  const store = await loadStore();
  const payload = await buildSyncUnit(store);
  res.json({
    revision: store.revision ?? 1,
    units: payload,
  });
});

app.listen(PORT, HOST, async () => {
  await fs.mkdir(path.dirname(STORE_PATH), { recursive: true });
  if (TOKEN === "CHANGE_ME_NOTE_DESK_SYNC") {
    console.warn("[DeskManualSync] NOTE_DESK_SYNC_TOKEN 仍为占位值，请在公网尽快改为强随机串。");
  }
  const where = HOST === "0.0.0.0" ? "0.0.0.0 (平台会映射到 https 域名)" : HOST;
  console.log(`[DeskManualSync] PORT=${PORT} host=${where} trustProxy=${TRUST_PROXY}`);
});
