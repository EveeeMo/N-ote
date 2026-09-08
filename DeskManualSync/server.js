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
    // 常见形容词词尾（启发式，可被预览页手动改）
    if (/(oso|osa|osos|osas|ivo|iva|able|ible|iente)$/u.test(lower)) return "adj";
    if (/^(lleno|blando|sucio|húmedo|humedo|calvo|canoso|corto|largo|liso|moreno|pelirrojo|rizado|rubio|claro|clara|claros|oscuro|oscuros|grises|gris|transparente|seguro|capaz)$/u.test(lower)) {
      return "adj";
    }
    const prep = new Set(["de", "a", "en", "con", "por", "para", "sin", "sobre", "entre", "hacia", "hasta", "mediante"]);
    if (prep.has(lower)) return "prep";
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
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 5000);
  try {
    const r = await fetch(url, { signal: ctrl.signal });
    if (!r.ok) throw new Error(`MyMemory HTTP ${r.status}`);
    const j = await r.json();
    return String(j?.responseData?.translatedText || "").trim();
  } finally {
    clearTimeout(timer);
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

/** 常见拼写/词形纠正（批量粘贴时用，可关）。 */
const SPELL_HINTS = Object.freeze({
  melizo: "mellizo",
  gries: "grises",
  parienta: "pariente",
});

function parseSpanishLines(raw) {
  const text = String(raw || "");
  const parts = text.split(/[\n,;]+/).map((s) => s.trim()).filter(Boolean);
  const out = [];
  const seen = new Set();
  for (const p of parts) {
    const key = normalizeSpanish(p);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(p);
  }
  return out;
}

function stripMdCell(raw) {
  let s = String(raw || "").trim();
  // **bold** / *italic* / `code` / ⭐
  s = s.replace(/\*\*/g, "").replace(/\*/g, "");
  s = s.replace(/`([^`]*)`/g, "$1");
  s = s.replace(/⭐+/g, "").trim();
  return s;
}

function splitMdRow(line) {
  let s = String(line || "").trim();
  if (s.startsWith("|")) s = s.slice(1);
  if (s.endsWith("|")) s = s.slice(0, -1);
  return s.split("|").map((c) => c.trim());
}

function isMdSeparatorRow(cells) {
  return cells.length > 0 && cells.every((c) => /^:?-{3,}:?$/.test(c.replace(/\s/g, "")));
}

function classifyHeaderCell(raw) {
  const t = stripMdCell(raw).toLowerCase();
  if (!t) return null;
  if (/(西语|西班牙语|spanish|\bes\b|palabra|词条|单词)/.test(t)) return "es";
  if (/(中文|释义|翻译|chinese|\bzh\b|意思|含义)/.test(t)) return "zh";
  if (/(备注|用法|重要|笔记|note|example|搭配)/.test(t)) return "note";
  if (/(词性|pos)/.test(t)) return "pos";
  return null;
}

/**
 * 解析粘贴内容：支持 Markdown 表格（西语/中文/备注）或纯西语列表。
 * @returns {{ es: string, zh?: string, note?: string, pos?: string }[]}
 */
function parseBatchInput(raw) {
  const text = String(raw || "").replace(/^\uFEFF/, "").trim();
  if (!text) return [];

  const lines = text.split(/\r?\n/);
  const tableLines = lines.filter((ln) => ln.includes("|"));
  // 至少表头 + 分隔 + 一行数据
  if (tableLines.length >= 3) {
    const rows = tableLines.map(splitMdRow).filter((c) => c.some((x) => x.trim()));
    if (rows.length >= 3) {
      let headerIdx = 0;
      let mapping = rows[0].map(classifyHeaderCell);
      // 若第一行不像表头，尝试找含「西语」的行
      if (!mapping.includes("es")) {
        for (let i = 0; i < Math.min(rows.length, 5); i++) {
          const m = rows[i].map(classifyHeaderCell);
          if (m.includes("es")) {
            headerIdx = i;
            mapping = m;
            break;
          }
        }
      }
      // 默认三列：西语 | 中文 | 备注
      if (!mapping.includes("es")) {
        mapping = rows[headerIdx].map((_, i) => (i === 0 ? "es" : i === 1 ? "zh" : i === 2 ? "note" : null));
      }

      const out = [];
      const seen = new Set();
      for (let r = headerIdx + 1; r < rows.length; r++) {
        const cells = rows[r];
        if (isMdSeparatorRow(cells)) continue;
        let es = "";
        let zh = "";
        let note = "";
        let pos = "";
        for (let i = 0; i < cells.length; i++) {
          const role = mapping[i];
          const val = stripMdCell(cells[i]);
          if (!role || !val) continue;
          if (role === "es") es = val;
          else if (role === "zh") zh = val;
          else if (role === "note") note = val;
          else if (role === "pos") pos = val;
        }
        // 无映射时：第 0 西语，第 1 中文，其余拼进备注
        if (!es && cells[0]) {
          es = stripMdCell(cells[0]);
          if (!zh && cells[1]) zh = stripMdCell(cells[1]);
          if (!note && cells.length > 2) {
            note = cells.slice(2).map(stripMdCell).filter(Boolean).join("；");
          }
        }
        if (!es) continue;
        const key = normalizeSpanish(es);
        if (!key || seen.has(key)) continue;
        seen.add(key);
        out.push({
          es,
          zh: zh || undefined,
          note: note || undefined,
          pos: pos || undefined,
        });
      }
      if (out.length) return out;
    }
  }

  // 纯列表
  return parseSpanishLines(text).map((es) => ({ es }));
}

function applySpellHint(es, enabled) {
  if (!enabled) return es;
  const hint = SPELL_HINTS[normalizeSpanish(es)];
  return hint || es;
}

/** 常见词本地释义（优先于机器翻译，可在预览页再改）。 */
const LOCAL_GLOSS = Object.freeze({
  gemelo: "双胞胎（男）；孪生的",
  mellizo: "双胞胎（男）；孪生的",
  madrina: "教母",
  padrino: "教父",
  cuñado: "姐夫；妹夫；内兄；小叔",
  nuera: "儿媳",
  suegro: "岳父；公公",
  yerno: "女婿",
  colega: "同事；同僚",
  conocido: "熟人；认识的",
  desconocido: "陌生人；未知的",
  pandilla: "一伙；帮派；朋友圈子",
  pareja: "伴侣；一对；一对情侣",
  pariente: "亲戚",
  parienta: "女亲戚（口语）",
  vecina: "女邻居",
  "de estudios": "学习上的；同学关系（de estudios）",
  "de piso": "合租的；同屋的（de piso）",
  calvo: "秃头的",
  canoso: "花白头发的",
  corto: "短的",
  largo: "长的",
  liso: "直的；光滑的（发质等）",
  moreno: "黑发的；皮肤较黑的",
  pelirrojo: "红头发的",
  rizado: "卷曲的",
  rubio: "金发的",
  claros: "浅色的；明亮的",
  grises: "灰色的",
  gries: "灰色的",
  oscuros: "深色的；黑暗的",
  lleno: "满的",
  rama: "树枝；分支",
  húmedo: "潮湿的",
  humedo: "潮湿的",
  brazo: "胳膊；手臂",
  carbón: "煤；木炭",
  carbon: "煤；木炭",
  blando: "软的",
  dedo: "手指；脚趾",
  sucio: "脏的",
  humo: "烟",
  mano: "手",
  fuerza: "力量；力气",
  cabeza: "头；头脑",
  capaz: "有能力的",
  letra: "字母；歌词；笔迹",
  mientras: "当…时；同时",
  risa: "笑；笑声",
  fuego: "火",
  llorar: "哭",
  pata: "（动物的）腿；爪",
  cordero: "羊羔；羊肉",
  lana: "羊毛",
  quitar: "去掉；拿开",
  cuerpo: "身体；躯体",
  adelante: "向前；继续",
  atrás: "向后；后面",
  detrás: "在后面",
  canción: "歌曲",
  cancion: "歌曲",
  hoja: "叶子；纸张",
  transparente: "透明的",
  seguro: "安全的；保险；肯定的",
  escalera: "楼梯；梯子",
  cruzar: "穿过；交叉",
  patio: "院子；天井",
  bosque: "森林；树林",
  pared: "墙",
  guerra: "战争",
  nariz: "鼻子",
  despertar: "叫醒；醒来；唤醒",
  "luchar contra": "与…作斗争；反对",
  "luchar a favor de": "为…而斗争；支持",
  "dar prioridad a": "优先考虑；给…优先权",
  mediante: "通过；凭借",
  "convertir a en b": "把 A 变成 B",
  "llevar a + inf.": "导致做某事；促使",
  "llevar a + inf": "导致做某事；促使",
  rechazar: "拒绝；排斥",
});

async function enrichWord(esRaw, { spellFix = true, translate = true, zh: zhIn, note, pos: posIn } = {}) {
  const es = applySpellHint(String(esRaw || "").trim(), spellFix);
  const local = LOCAL_GLOSS[normalizeSpanish(es)] || "";
  let zh = (zhIn && String(zhIn).trim()) || local;
  if (translate && !zh) {
    try {
      zh = await translateMyMemory(es);
    } catch {
      zh = "";
    }
  }
  let pos = (posIn && String(posIn).trim()) || appPartOfSpeech(es);
  if (/\s/.test(es) || /\+/.test(es) || /\//.test(es)) pos = "phrase";
  const lemma = pos === "verb" ? es : null;
  const noteVal = note && String(note).trim() ? String(note).trim() : null;
  return { es, zh, pos, lemma, note: noteVal, scheduleDue: true };
}

/** 有限并发；已有中文的条目跳过联网翻译。 */
async function enrichMany(items, { spellFix = true, concurrency = 3 } = {}) {
  const list = items.map((it) => (typeof it === "string" ? { es: it } : it));
  const rows = new Array(list.length);
  let next = 0;
  async function worker() {
    while (true) {
      const i = next++;
      if (i >= list.length) return;
      const it = list[i];
      const hasZh = Boolean(it.zh && String(it.zh).trim());
      rows[i] = await enrichWord(it.es, {
        spellFix,
        translate: !hasZh,
        zh: it.zh,
        note: it.note,
        pos: it.pos,
      });
    }
  }
  const n = Math.max(1, Math.min(concurrency, list.length || 1));
  await Promise.all(Array.from({ length: n }, () => worker()));
  return rows;
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
    let zh = "";
    try {
      zh = await translateMyMemory(q);
    } catch {
      zh = "";
    }
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

/**
 * 批量预览：粘贴西语列表或 Markdown 表 → 自动补全缺失释义 + 词性（不写入）。
 * body: { text?: string, words?: string[]|object[], spellFix?: boolean }
 */
app.post("/api/words/batch/preview", authBearer, async (req, res) => {
  try {
    const spellFix = req.body?.spellFix !== false;
    let items = parseBatchInput(req.body?.text);
    if (Array.isArray(req.body?.words) && req.body.words.length) {
      const extra = req.body.words
        .map((x) => (typeof x === "string" ? { es: x } : x))
        .filter((x) => x && x.es);
      // 合并：text 优先，再追加 words
      const seen = new Set(items.map((w) => normalizeSpanish(w.es)));
      for (const w of extra) {
        const k = normalizeSpanish(w.es);
        if (!k || seen.has(k)) continue;
        seen.add(k);
        items.push(w);
      }
    }
    if (!items.length) return res.status(400).json({ error: "empty_list" });
    if (items.length > 200) return res.status(400).json({ error: "too_many", max: 200 });

    const words = await enrichMany(items, { spellFix });
    res.json({ count: words.length, words });
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
});

/**
 * 批量写入：可直接传 text（含 Markdown 表），或传已校对的 words[{es,zh,pos,note,...}]。
 * 写入的词会带 scheduleDue，App 同步后排入今日复习。
 */
app.post("/api/words/batch", authBearer, async (req, res) => {
  try {
    const spellFix = req.body?.spellFix !== false;
    let rows = [];

    if (Array.isArray(req.body?.words) && req.body.words.length && typeof req.body.words[0] === "object") {
      const posOptions = new Set(["noun", "verb", "adj", "adv", "prep", "interj", "phrase"]);
      rows = await enrichMany(
        req.body.words.map((w) => ({
          es: w?.es,
          zh: w?.zh,
          note: w?.note,
          pos: w?.pos && posOptions.has(w.pos) ? w.pos : undefined,
        })),
        { spellFix }
      );
    } else {
      const items = parseBatchInput(req.body?.text);
      if (!items.length) return res.status(400).json({ error: "empty_list" });
      if (items.length > 200) return res.status(400).json({ error: "too_many", max: 200 });
      rows = await enrichMany(items, { spellFix });
    }

    if (!rows.length) return res.status(400).json({ error: "empty_list" });

    const store = await loadStore();
    let added = 0;
    let updated = 0;
    const dueSpanish = [];
    for (const row of rows) {
      const key = normalizeSpanish(row.es);
      if (!key) continue;
      const idx = store.words.findIndex((w) => normalizeSpanish(w.es) === key);
      const next = {
        es: row.es,
        zh: row.zh || "",
        pos: row.pos || "noun",
        lemma: row.pos === "verb" ? row.lemma || row.es : null,
        note: row.note || null,
        scheduleDue: true,
      };
      if (idx >= 0) {
        // 合并备注：新备注追加，不丢旧的
        const oldNote = store.words[idx].note || "";
        if (next.note && oldNote && !oldNote.includes(next.note)) {
          next.note = oldNote + "\n" + next.note;
        } else if (!next.note && oldNote) {
          next.note = oldNote;
        }
        if (!next.zh && store.words[idx].zh) next.zh = store.words[idx].zh;
        store.words[idx] = { ...store.words[idx], ...next };
        updated += 1;
      } else {
        store.words.push(next);
        added += 1;
      }
      dueSpanish.push(row.es);
    }
    store.revision = (store.revision || 1) + 1;
    store.updatedAt = new Date().toISOString();
    store.pendingDueSpanish = Array.from(
      new Set([...(store.pendingDueSpanish || []).map(normalizeSpanish), ...dueSpanish.map(normalizeSpanish)])
    );
    await saveStore(store);

    res.json({
      ok: true,
      revision: store.revision,
      count: store.words.length,
      added,
      updated,
      dueCount: dueSpanish.length,
      words: rows,
    });
  } catch (e) {
    res.status(502).json({ error: String(e.message || e) });
  }
});

/** App 确认已把这批词排入今日复习后清除 pending。 */
app.post("/api/due/ack", authBearer, async (req, res) => {
  const keys = Array.isArray(req.body?.keys)
    ? req.body.keys.map((k) => normalizeSpanish(k)).filter(Boolean)
    : [];
  const store = await loadStore();
  const pending = new Set((store.pendingDueSpanish || []).map(normalizeSpanish));
  if (keys.length) {
    for (const k of keys) pending.delete(k);
  } else {
    pending.clear();
  }
  for (const w of store.words) {
    if (!keys.length || keys.includes(normalizeSpanish(w.es))) {
      delete w.scheduleDue;
    }
  }
  store.pendingDueSpanish = Array.from(pending);
  store.updatedAt = new Date().toISOString();
  await saveStore(store);
  res.json({ ok: true, remaining: store.pendingDueSpanish.length });
});

/** APP 前台轮询调用：结构与教材 JSON `[BundledUnitDTO]` 一致。 */
app.get("/api/sync/unit", authBearer, async (_req, res) => {
  const store = await loadStore();
  const payload = await buildSyncUnit(store);
  const dueSpanish = (store.pendingDueSpanish || []).slice();
  // 同步单元里带上 scheduleDue，方便 App 识别
  const dueSet = new Set(dueSpanish.map(normalizeSpanish));
  for (const u of payload) {
    for (const w of u.words) {
      if (dueSet.has(normalizeSpanish(w.es)) || w.scheduleDue) {
        w.scheduleDue = true;
      }
    }
  }
  res.json({
    revision: store.revision ?? 1,
    units: payload,
    dueSpanish,
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
