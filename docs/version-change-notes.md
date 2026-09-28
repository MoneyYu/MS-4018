# MS-4018 版本差異與授課基線（講師用）

> 此檔位於**公開** repository，僅存放不含憑證的課程備課說明。課前請重新核對官方課程內容與產品功能。

## 目前基線

- [Course MS-4018-A: Draft, analyze, and present with Microsoft 365 Copilot](https://learn.microsoft.com/en-us/training/courses/ms-4018)：1 天、Business User 導向，課程頁提供 **Achievement Code**，不表示本課本身有 Applied Skills／考試。
- [Learning path](https://learn.microsoft.com/en-us/training/paths/draft-analyze-present-microsoft-365-copilot/)：7 模組，順序為 Copilot 基礎、Copilot Chat、PowerPoint、Word、Teams、Excel、Outlook。
- [官方 Lab index](https://microsoftlearning.github.io/MS-4018-Draft-analyze-present-Microsoft-365-Copilot/)：Lab 00 設定，Lab 01–05 依序 Chat、PowerPoint、Word、Teams、Excel；**沒有** Outlook lab。現有 `.zh-cn` lab repo 無法使用，README 只提供英文 hosted index 與 archive。
- 本機 `PPT/MS-4018-ENU-PowerPoint_00.pptx` 至 `_08.pptx` 對應課前、M01–M07、結語；PPT 資料夾不進 Git。

## 相對於先前 README 的變化

| 舊內容／風險 | 本次採用的交付基線 |
| --- | --- |
| `## Links` 依 Word、PowerPoint、Excel、Teams、Outlook、Copilot app 等產品分類，並含多個通用功能索引 | `## Links` 依當前 M01–M07 教學順序排列，每節先給對應 Learn module，再給直接支持目標的官方說明。 |
| 舊影片清單混合基礎、各 app 與客戶案例，未核對頻道或可用性 | 僅保留 oEmbed 驗證為 LIVE、官方 Microsoft 頻道且對應模組的影片；用單一表格的 Module 欄標示歸屬。 |
| Learn 舊 URL 與部分 `/en-us/office/...` 相對 URL、退役的 Excel Python 頁 | 採用目前可解析的 canonical URL；退役頁不再引用。 |
| 連結至已不存在的中文 Lab repo | 僅放英文 hosted Lab index 與一個 archive；不列單項 exercise，不特別加入「沒有中文」警語。 |
| `## Course Info` 舊圖與 Applied Skill badge 容易暗示不存在的資格 | 移除舊圖，改用 generic achievement badge；依本梯次需求不加 Exam & Credential 區段。 |

**需要本梯次負責人確認：** 舊梯次問卷代碼 `aka.ms/ms4018survey` 於 2026-09-29 在匿名檢查時回傳 Metrics That Matter `Fault.aspx`（表面 HTTP 200，但不是可填問卷頁）。README 保留原本梯次的 Date、Course ID、Training key，暫不把失效問卷呈現為可點擊連結；交付新梯次前必須取得新問卷並重新驗證。

課堂節奏與各模組重點見 [備課指南](teaching-guide.md)；既有示範材料位置見 [Demo 索引](demo-environment.md)。未新增 Azure／Terraform 環境，因本課學習目標與 lab 均為 Microsoft 365 應用情境。
