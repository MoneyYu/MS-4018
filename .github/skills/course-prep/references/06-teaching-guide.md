# Phase 6 — Trainer teaching guide (備課指南)

Produce `docs/teaching-guide.md` — a **trainer-only** prep document (not attendee-facing). Write it
in the user's language (**Traditional Chinese / 正體中文**) while keeping technical terms, product
names, and links in **English**. Draw heavily on the **PPT speaker notes** (extracted in Phase 1)
for real talking points, demo cues, and gotchas.

Cross-link it from `docs/demo-environment.md` for discoverability. Verify every lab/exercise/doc
link resolves (HTTP 200).

## Structure (proven outline — adapt module count to the course)

1. **課程概覽** — positioning, length, audience, prerequisites. If the course was re-versioned,
   warn up front *not* to reuse old materials.
2. **課程地圖：N 個模組** — the ordered module list mapped to its lab(s).
3. **建議議程與時間分配** — a realistic agenda (e.g. 1 day ≈ 6.5 hrs teaching) with breaks/lunch.
4. **貫穿全課的核心觀念** — cross-cutting ideas to open with and reinforce, e.g.:
   - the workload "big picture" overview;
   - any key **API / concept comparison** the slides hinge on (e.g. *ChatCompletions vs Responses
     API*) as a short table;
   - **模型生命週期** reminder (re-check before each delivery — Phase 4);
   - per-lab environment realities (e.g. "每個練習都要先建立 Foundry 專案" — manage attendee
     expectations);
   - the **Entra-ID-only / key-less** security design of the demo environment.
5. **逐模組備課指南** — one subsection per module, each with the same layout:
   - **學習目標** → **講解重點** → **Demo / Lab 連結** → **常見問題 / 坑**（include the
     knowledge-check answers and known stumbling blocks）→ **重要連結**.
   - Fold in the relevant PPT speaker-note lines (sample phrasing, "can skip / pre-set by trainer"
     notes, prebuilt-vs-custom tips, etc.).
6. **預期學員問題 Q&A** — pre-answer likely questions (include the credential answer, e.g.
   "本課沒有 skill-based credential，只有成就碼" if that's what Phase 1 found).
7. **課前準備清單（開課前 1–2 天）** — quota/capacity checks, any **manual portal** model
   deployments, Skillable login, slide customization, etc.
8. **講師小技巧** — delivery tips, timing rescues, what to demo live vs show pre-built.

End with a **參考** section linking the learning path, lab repos, and the trainer docs.
