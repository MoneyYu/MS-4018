# 廣達電腦 MS-4018 講師操作指南（2026-11-12）

僅供講師：所有專案、客戶代號及營運數字均為虛構，不代表廣達官方營運資料。業務畫面使用自然的工作用語，真實性來自一致的原始數據及決策狀態，不應對外宣稱是真實客戶資料。

**交付狀態：已依 2026-11-12 使用者「灌入正式內容」指示完成單次正式灌入。** 執行前重新計算的清單 fingerprint 與審查版完全一致；runner exit 0，建立五本 Excel、五條郵件串（15 封）及一個 Team 的五個業務頻道（10 則主貼文、10 則回覆）。沒有修改使用者 profile 或既有 Ford 資料，未重跑完整 runner。

灌入後、開啟 Excel 前的唯讀 preflight 顯示 OneDrive `Skip`、Team `Reuse`、五個頻道訊息及五條郵件串均 `Skip`，沒有待建立項目。額外 GET 核對 15 封郵件的 sender／To／CC／內文、Admin owner 與九位 Team 成員，以及五本遠端活頁簿的儲存格／公式／Tables／圖表／中繼資料，皆符合來源。

主 agent 已用 Playwright 以 Admin 親自檢視五條三封郵件串、五個業務頻道及回覆，以及五本 Excel 閱讀檢視，畫面數值符合上述口徑。私密 `config.json` 與本次 `onedrive-receipt.json` 已在本機 ignored 目錄，務必保留 receipt，不提交或傳給他人。完整重跑沒有再次驗證，已完成情境不要再正式執行；只用 `-PreflightOnly`。Copilot 索引／特定生成答案未列為本次成功聲明；課前仍須檢查。

**目前限制：檔案版本已漂移，禁止重跑或修補。** 在 `action=view` 網站驗收後，`產能與良率.xlsx` 的 ID 不變，但 eTag 與大小改變（9044 → 12459 bytes，Graph 顯示修改者 MOD Administrator）；其他四本與 receipt 相符。最後一次 preflight 因此正確停止。再次 GET 下載全部五本後，儲存格、公式、Table 名稱／範圍、圖表數量、作者與描述均與來源相同；沒有發現業務資料差異。是否由 Excel 容器／計算儲存造成屬推測，不能僅憑閱讀檢視參數判定原因。不要更新 receipt、覆寫或重新寄信來消除這個警告。內容已可使用，但「UI 驗收後 receipt 仍完全相符」關卡未通過，issue #5 保持開啟追蹤。

## 資產與操作邊界

使用 `admin@moneyyu.com` 作為唯一操作帳號，不登入業務角色。交付情境位於 `seed-data\scenarios\ms4018-quanta-operations-20261112-reviewed`；唯一編輯來源為 `seed-data\packs\ms4018-quanta-operations\pack.yaml`。較早的 `ms4018-quanta-operations-20261112` 僅為未執行的初版產物，不作正式執行入口；它保留不覆寫，修正後只生成至新的 `-reviewed` 本機目錄。這不是另一個租戶 Team，也不是額外寫入許可。

| 畫面 | 名稱與內容 |
| --- | --- |
| Teams | `20261112-MS-4018`；General 及五個業務頻道；10 則主貼文、10 則回覆 |
| Outlook | 搜尋 `20261112 營運週會`；5 串、每串 3 封，Admin 均為 CC |
| OneDrive | `MS4018-OperationsReview-20261112`；五本 Excel 與 `.ms4018-seed-proof.json` 技術檔 |
| 本機 Excel | scenario 內的 `FILES`；用於離線講解，不手改日期化來源 |

Team 背後會建立 M365 Group 與相應 Site，不另建立 SharePoint 情境。既有共享使用者 profile 不修改；admin 部門的既有 `Demo` 用語及內部 `demoUserUpn` 欄位不在業務文案檢查範圍。安全技術檔可能在 OneDrive 清單可見，不能刪除或假裝一定隱藏。

## 課程範圍

官方課程目前為 **Draft, analyze, and present with Microsoft Copilot**，七模組包含 Outlook；這套資料支援 Teams 協作、Excel 分析及 Outlook 溝通，不宣稱完整覆蓋七模組，也未提供 Word / PowerPoint 成品。頻道貼文不等於會議逐字稿或 Facilitator。

https://learn.microsoft.com/en-us/training/courses/ms-4018

https://learn.microsoft.com/en-us/training/paths/draft-analyze-present-microsoft-365-copilot/

## 五條業務線與人工核對

資料截止 **2026-11-11**。Teams 訊息是歷史時間；Outlook 顯示實際寄送日，不能回填收件時間。

| 頻道／活頁簿 | 原始表 | 可驗算結果與未結事項 |
| --- | --- | --- |
| NPI專案協作／專案里程碑.xlsx | NpiMilestones、NpiSummary | 完成 21/24=87.5%；022 待料、023 待驗證、024 待核准 |
| 物料與供應風險／物料交期追蹤.xlsx | MaterialDelivery | 1200−1050=150 件；1050/1200=87.5%；替代料待核准 |
| 品質與製程／品質異常追蹤.xlsx | QualityLots | QN-1106：12/400=3%；隔離待判，未證實根因 |
| 產能與排程／產能與良率.xlsx | ProductionYield | 11/11 一區 962/1000=96.2%；96.2−98.5=−2.3 個百分點；二區 98.7% |
| 出貨與客戶交付／客戶交付追蹤.xlsx | ShipmentCommitments | 客戶 A：800−720=80 台；720/800=90%；調整交付日待核准 |

比率欄以 0–100 儲存，標題包含 `(%)`；不是 0–1 的 Excel 百分比格式。抽驗率、FPY、達交率分母不同；150 件物料缺口不能直接解釋 80 台未交。`資料口徑` 頁說明截止時間與狀態。

## Prompt

### Teams：決策與責任人

> 請依「NPI專案協作」「物料與供應風險」「品質與製程」「產能與排程」「出貨與客戶交付」截至 11/11 的貼文，整理 ORION 專案已完成、待驗證、待核准事項、負責人及 11/13 截止日。列出對應來源；不要把替代料、跨區排程或交期變更寫成已執行，也不要把相關線索當成已證實根因。

若側邊欄未顯示頻道，用 Team 的 See all channels 檢視，不據此再建立 Team。

### Outlook：摘要與草稿

> 請摘要主旨含「20261112 營運週會」的五條郵件串，按 NPI、物料、品質、產能、交付分類，列出數據事實、待確認假設、負責人與截止日。用繁體中文草擬給 Megan 的回覆，保留待核准狀態並引用郵件來源。只產生草稿，不寄送。

### Excel：原表、公式與推論邊界

> 在「專案里程碑.xlsx」核對 NpiMilestones 與 NpiSummary，說明完成率的分子分母、三項未結工作及其責任人。請列出 Table 與來源儲存格，不修改原檔。

> 在「物料交期追蹤.xlsx」的 MaterialDelivery 與「品質異常追蹤.xlsx」的 QualityLots，分別驗算 MTR-A01 缺口和 QN-1106 抽驗異常率。說明兩個分母與狀態為何不能混用，不修改原檔。

> 在「產能與良率.xlsx」依 ProductionYield 比較兩區 11/11 的首次直通良率及前幾日趨勢，算出相對目標的百分點差距，區分觀察與原因假設。再依「客戶交付追蹤.xlsx」ShipmentCommitments 驗算客戶 A 的未交台數與達交率。不要直接歸因、不修改原檔。

Copilot 回覆須由講師回到上述原表核對。openpyxl 不會計算 cached formula value；離線數值驗算不等於 Excel UI 已計算。課堂若需展示編輯能力，另建立明確副本；不能修改 receipt 保護的來源後再修補 receipt。

## 生成、審查與灌入

在新的廣達 worktree 執行；已存在的正式 scenario 不得覆寫。測試使用新的暫存目錄。以下生成命令僅適用於目的地尚未建立時：

```powershell
$env:UV_INDEX_URL = 'https://packagefeedproxy.microsoft.io/pypi/simple/'
uv run --no-project .\seed-data\generator\build_scenario.py --pack .\seed-data\packs\ms4018-quanta-operations\pack.yaml --date 20261112 --output .\seed-data\scenarios\ms4018-quanta-operations-20261112-reviewed
```

取得目前有效 app credential，只放本機 ignored `config.json`；不要將舊失效 Secret 複製過來。Admin 三欄一致，不更動角色 profile，不增加權限。

```powershell
pwsh -NoProfile -File .\seed-data\scenarios\ms4018-quanta-operations-20261112-reviewed\run.ps1 -PreflightOnly
```

以下為建立**全新場次**時的規則；本次情境已完成，不可重新走正式建立。首次預期資料夾、Team 與五條郵件串均為 Create。這只是唯讀可行性，不是寫入許可。正式執行前須完成獨立實作審查，並向使用者列出每封實際 sender / To / Cc / subject、完整 Team owner/member 名單、General 與五頻道、Group/Site 副作用、OneDrive 檔案及執行碼 hash 的凍結清單，取得對該清單精確 SHA-256 fingerprint 的明示核准。

**在同一正式執行前立即重新產生清單，逐項與已核准清單比對，並確認 SHA-256 fingerprint 完全相同，然後再跑 GET-only preflight。** 內文、收件人、角色、tenant/client 身份、目標名稱、檔案或執行碼任何一項變更、fingerprint 不符、未取得核准或查詢失敗，一律停止；不能更新清單後沿用舊核准，也不能從任一 generated README 或 runner 存在推定允許寫入。生成器及 engine 不會代替操作員取得同意；沒有這個比對證據不得執行完整 runner。

只有該精確清單獲核准後才執行：

```powershell
pwsh -NoProfile -File .\seed-data\scenarios\ms4018-quanta-operations-20261112-reviewed\run.ps1
```

這會送出 **15 封真實內部郵件**。任一階段失敗即停；不自動重寄、不修復部分 Team、不刪除／改名、不補 owner/member。同日同課程不能靠改 purpose 避開 Team 碰撞；需要新日期時重新確認。

## 驗收與限制

先用 paged GET 比對宣告內容，再執行 `-PreflightOnly`；完成後應為 OneDrive Skip、Team Reuse、五頻道訊息 Skip、五郵件串 Skip，沒有 Create。不靠完整 runner 重跑來證明冪等性。保留本機 receipt；磁碟清單不是事後修復授權。

主 agent 必須親自用 Playwright 檢視 Admin 的 Teams 貼文及回覆、五條郵件串、五本 Excel 的 Tables／圖表／公式與數字。取得的 private URLs、token、proof / receipt 值不放 issue 或 commit。

若授權／索引不足，僅展示已有原始資料與離線驗算，明確記錄 UI / Copilot 受阻。資料檔案、Graph、介面、Copilot 四層分別記錄；沒有網站證據不可宣稱端到端完成。實際本次狀態以 tracking issue #5 的脫敏進度為準，不把預期結果當成已執行證據。
