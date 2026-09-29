# MS-4018 Ford Demo 講師 Runbook（2026-09-29）

> **僅供講師**：資料全部虛構；此公開 repository 不是權限邊界。對外請明示「模擬福特業務情境」，不可暗示真實業績、已發布召回或未公開營運資料。操作帳號只有 `admin@moneyyu.com`。

## 課前準備

**目前狀態：原 `ms4018-ford-auto-20260929` 為部分完成，禁止正式重跑。** 原 OneDrive `MS4018-Demo-20260929` 已有五本 Excel 與驗證標記；Alex 寄出的第一封郵件在 admin Inbox 可見（admin 只是 CC，不會在 admin Sent Items）。原情境的郵件串與 Teams 均**未完成**。加法備案 `ms4018-ford-auto-workshop-b-20260929` 已完成：OneDrive `MS4018-WorkshopB-20260929` 五本 Excel、五條 Outlook 郵件串、Team `20260929-MS-4018` 五個業務頻道與貼文。瀏覽器已核對上述資料；完整重跑後的唯讀 preflight 無待建立項目。

1. 從 `seed-data/scenarios/ms4018-ford-auto-workshop-b-20260929` 執行 `pwsh -File .\run.ps1 -PreflightOnly`：預期 OneDrive `Skip`、Team `Reuse`、五個頻道訊息 `Skip`、五條郵件串 `Skip`，沒有 `Create`。任何差異就停止，不修補、不正式重跑；保留本機忽略版的 `config.json` 與 `onedrive-receipt.json`。
2. 使用 `admin@moneyyu.com` 檢查 Teams `20260929-MS-4018`。若側邊欄只顯示 General，點 Team 的「See all channels」，並用「Show」把五個業務頻道顯示在側邊欄；再檢視貼文。Outlook 搜尋 `20260929 WorkshopB`，OneDrive 開啟 `MS4018-WorkshopB-20260929`。不要對已完成的情境再執行正式模式，也不可用「刪除重跑」解決中途失敗。
3. 讓 Microsoft 365 索引完成再測 Copilot。Email 是當天寄送，**不能**用 Graph 回填時間；Teams channel 訊息可顯示歷史時間。Outlook 場景不是官方 MS-4018 lab 的一部分。
4. 用 `DEMO-FILE/` 的本地備份準備離線講解；課前檢查 Copilot 授權、Excel 支援、tenant 索引、Teams／Outlook 可見性。授權或索引不足時不承諾 Copilot 產生特定答案。

## 12 分鐘示範腳本

| 時間 | 畫面與操作 | 教學重點／人工核對 |
| --- | --- | --- |
| 0–3 分 | Teams → `20260929-MS-4018` → 「经销商与库存」「供应链与品质」。用 [Prompt Library](04_Prompts/PromptLibrary.md) 的 Teams prompt 追問跨 channel 決策。 | 上海 240 天／北京 60 天；40 輛調撥**待核准**；B-0921 仍是內部調查，未宣告召回。Teams channel 不等於會議逐字稿／Facilitator。 |
| 3–6 分 | Outlook → 管理員收件匣搜尋 `20260929 WorkshopB`；開啟 Q3 復盤 thread，用 Outlook Copilot 摘要並草擬回覆。 | 只核對郵件**今天**收到，並核對 860/960、330、6%、31、92.4% 等數字。草稿不送出。 |
| 6–12 分 | OneDrive → Excel 打開「经销商库存.xlsx」「零部件品质追踪.xlsx」「售后NPS.xlsx」「工厂KPI.xlsx」，使用對應 prompts；展示 Table、公式欄與圖表。 | 自行讀原表驗算：`240/30*30=240`、`(1800-1470)=330`、`36/600=6%`、`62-31=31`、`924/1000=92.4%`。兩種不同分母不能相加。 |

## 備案與風險

- **授權／索引失敗**：從 `DEMO-FILE/` 用 Excel 開檔、Teams／Outlook 顯示已 seed 的原始資料，口頭演示「限定來源、指定輸出、人工核對」流程；不可偽稱 Copilot 已完成特定分析。
- **Team／郵件中途 seed 失敗**：停止，保存錯誤供租戶管理員唯讀排查；不要刪除或重命名任何資源，不對以名稱查得的 group 補權限。同一課程同一天的 Team 名稱固定，改 purpose 只能區隔資料夾，不能避開 Team 碰撞；新情境須另選日期，先審查與取得寫入核准。
- **資料使用**：所有郵件都是對 tenant 內部既有人員寄送；Outlook 寄件屬真實租戶副作用，課前與相關人員確認可接受。切勿使用客戶真實名單、附件或識別資訊。
