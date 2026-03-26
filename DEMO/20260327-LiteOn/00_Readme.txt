MS-4018 Demo Pack — 光寶科技（LiteOn Technology）
=============================================

本資料夾包含 4 組完整的 Live Demo 場景，每組都涵蓋 Word / Excel / PowerPoint / Teams / Outlook / Copilot Chat + Agents 的全套展示。
講師可依當天聽眾背景選擇最適合的場景（或跨梯次輪換）。

## 4 組場景概覽

| # | 資料夾 | 場景 | 適合聽眾 | 故事線核心 |
|---|--------|------|---------|-----------|
| 1 | 01_供應鏈優化與品質管理/ | 供應鏈品質 | SQE/SCM/品質 | 向高層提交供應商品質提升與來料風險控管提案 |
| 2 | 02_ESG永續發展與碳盤查/ | ESG 碳盤查 | ESG/EHS/永續 | 準備年度 ESG 報告與碳減排策略，董事會審查 |
| 3 | 03_新產品開發與市場策略/ | 新產品策略 | PM/RD/行銷/業務 | AI 伺服器 GaN 電源上市計畫，NPD 委員會審查 |
| 4 | 04_全球營運管理/ | 全球營運 | 營運/廠區/PMC/HR | 跨廠區 Q4 營運績效檢討與成本優化提案 |

## 每組場景包含

- `MS-4018_LiveDemo_Runbook_*.md` — 完整 Demo 腳本（含每段時間、步驟、提示、備援）
- `01_Story/StoryBrief.md` — 故事線概述
- `02_Docs/` — 3 個 Word 文件（政策草案 + 會議紀錄 + 高層提案初稿）
- `03_Data/` — 1 個 Excel 文件（含 Table 格式的樣本資料 + KPI 目標表）
- `04_Prompts/PromptLibrary.md` — 所有 Prompt 快速參考（可直接貼到 Copilot）
- `05_Agents/AgentsBlueprint.md` — Copilot Chat Agent 設計稿

## 課前準備（重要！）

1. 選定要使用的場景（建議依聽眾產業/職能決定）
2. 將該場景的 02_Docs/ 和 03_Data/ 資料夾中的檔案上傳到 OneDrive 或 SharePoint
3. 確認 Excel 檔案可正常開啟 Copilot（需 Table 格式 + OneDrive/SharePoint，本 Demo 已預設）
4. 確認 Teams 聽錄/逐字稿功能（若受限，各 Runbook 有備援方案）

## Demo 時間規劃（每組 ~165 分鐘）

| 段落 | 時間 |
|------|------|
| 課前準備 | 10 min |
| Word 全功能 Demo | 25–30 min |
| Excel 全功能 Demo | 25–30 min |
| PowerPoint 全功能 Demo | 20–25 min |
| Teams 全功能 Demo | 15–18 min |
| Outlook 全功能 Demo | 15–18 min |
| Copilot Chat + Agents | 18–20 min |
| Hands-on 練習 | 30–40 min |
| 收尾 | 5 min |

## 新功能亮點（2025–2026）

- **Excel — Edit with Copilot**（2026.03）：多步驟工作簿編輯，原 Agent Mode
- **Word — Agent Mode**（2026.03）：對話式文件建立/編輯，可引用多來源
- **PowerPoint — Narrative Builder**：從 Word 自動產出含表格的簡報
- **PowerPoint — 一鍵講者備忘**（2025.03）
- **Outlook — Coaching by Copilot**：語氣/清晰度/訊息有效性建議

## 檔案產生器

`generate_demo_files.py` — 使用 `uv run generate_demo_files.py` 可重新產生所有 .docx 和 .xlsx 範例檔案。

## 注意事項

- 所有文件為虛構的課程 Demo 內容，可自由修改
- Excel 資料中刻意埋入異常值，讓 Copilot 有「洞察」可以發現
- 每組 Runbook 的 Section 0 都有詳細的課前準備說明