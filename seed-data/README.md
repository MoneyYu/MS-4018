# Microsoft 365 Customer Pack demo seeder

此目錄同時保存 MS-4018 Ford 與 MS-4022 Product Support 情境。**絕對不建立任何新使用者**：角色只引用已存在、啟用的 tenant 帳號，執行前先由 Phase 0.5 唯讀驗證；Ford 不執行 Phase 1（不更動使用者職稱或部門）。本次為虛構資料，並非客戶真實業績。

## 快速開始：Ford（2026-09-29）

下列是從專案根目錄**首次產生全新情境**的命令示例（本機 Python 套件走指定內部 registry；不得把 secret 放進 pack）。本次 WorkshopB 目錄已存在且已灌入，**不要原樣重跑或覆寫**；換客戶時須改用新的 pack、日期與輸出目錄：

```powershell
$env:UV_INDEX_URL = 'https://packagefeedproxy.microsoft.io/pypi/simple/'
uv run --no-project .\seed-data\generator\build_scenario.py --pack .\seed-data\packs\ms4018-ford-auto-workshop-b\pack.yaml --date 20260929 --output .\seed-data\scenarios\ms4018-ford-auto-workshop-b-20260929
```

原 `ms4018-ford-auto-20260929` 已在租戶留下五本 Excel 及 Alex 寄出的第一封郵件（admin 在 Inbox 收到 CC）；回覆因跨信箱 `conversationId` 不同而失敗，**絕不可正式重跑原情境**。加法備案 `WorkshopB` 已完成正式灌入：另一個 OneDrive 資料夾有五本 Excel，五條 Outlook 郵件串已寄出，Team `20260929-MS-4018` 有五個業務頻道與訊息。完整重跑後的唯讀 preflight 顯示資料夾與五條郵件串 `Skip`、Team `Reuse`、五個頻道訊息 `Skip`，沒有待建立項目；瀏覽器亦已核對頻道貼文、郵件與五本活頁簿。若情境資料夾已有檔案，generator **拒絕覆寫**。`config.json` 與 `onedrive-receipt.json` 僅留在本機忽略版，不可把設定檔、receipt 或 access token 傳給其他人或提交。

```powershell
Set-Location .\seed-data\scenarios\ms4018-ford-auto-workshop-b-20260929
pwsh -File .\run.ps1 -PreflightOnly
```

Ford 只 seed OneDrive（五本 Excel）、Outlook（五條 threads）與 Teams（一個 Team／五個 channel）；沒有 Calendar 或 Meeting chats。Teams 側邊欄若只顯示 General，從 Team 的「See all channels」查看其餘頻道，必要時按「Show」顯示在側邊欄。Preflight 先核對 app token 的 tenant、client、選用階段所需 roles、既有帳號與目標資料夾；OneDrive 建立時遇同名資料夾即停止，不會覆寫。第一次完整上傳後，在資料夾建立 `.ms4018-seed-proof.json`，並於本機忽略版 `onedrive-receipt.json` 記錄隨機驗證值、folder ID 和檔案修訂資訊；重跑只在兩份證明及每個檔案都相符時跳過上傳。**請保留本機 receipt**；遺失、內容變更或半途失敗時不修補舊資料夾，改用新目的名稱。已完成的 WorkshopB 不需再正式執行；驗證過的重跑會跳過郵件與頻道訊息，但 Team reuse 仍可能執行具冪等性的 migration/member POST，並非完全零寫入。錯誤即停，保存錯誤與唯讀狀態供租戶管理員研判；不能靠刪除、改名或以名稱查得的 ID 補權限。講師步驟見 [`DEMO/20260929-Ford/`](../DEMO/20260929-Ford/)。

## 換客戶：建立 Customer Pack

複製 [`packs/ms4018-ford-auto/pack.yaml`](packs/ms4018-ford-auto/pack.yaml) 的**欄位結構**到新檔，改寫 `customer`、`roles`、Teams／Outlook 故事與 `workbooks` 表格數據；Team 名稱固定為 `<YYYYMMDD>-<course.code>`（本次 `20260929-MS-4018`），OneDrive 資料夾仍由 `course.code`、中立 `course.purpose`、日期組成，郵件首封主旨仍必須唯一。完整資料形狀見 [`generator/pack.schema.json`](generator/pack.schema.json)。同一課程同一天的另一情境**不能靠改 purpose 取得不同 Team 名稱**；preflight 發現碰撞就停止，不自行加尾碼、刪除或改名，須另選場次日期。`workbooks` 可用顯式 `rows`，或 `generate` 的 `seed`、`dimensions`、`periods`、`min`、`max`、`overrides` 生成可重現的資料，再用 `formulas` 插入公式欄，`chart` 增加圖表。每本 workbook 用 Excel Table 命名，方便 Copilot in Excel 指定範圍。

Generator 依 pack 宣告輸出與執行必要 phase：Ford 為 0→0.5→2→3→4；MS-4022 為 0→0.5→7。不指定的 surface 不建立；每個 role 必有 UPN 且 preflight 查 `accountEnabled`；禁止建立帳號／將客戶名稱寫進持久身份。任一唯讀查詢失敗或資源不明確時停止，不會將錯誤解讀為「不存在」。

## MS-4022 Product Support（保留舊情境與舊 engine）

此工具會將官方 lab 的 Products 範例資料上傳到日期化的私人 Microsoft 365 Group site，並建立一份 `Support Cases` 清單，供 Product Support 宣告式代理程式作為 SharePoint knowledge source 與 connector tool 的資料來源。

文件與清單各自對應不同的教學重點：文件回答政策與規格類問題（knowledge grounding），清單提供可查詢的營運資料（connector tool）。

## 安全邊界

- 只使用 Microsoft Graph app-only client-credentials flow；不使用租用戶 access key。
- `config.json`、`onedrive-receipt.json` 與下載的 `source/`、`Products.zip` 皆被 [.gitignore](../.gitignore) 排除，不能提交。
- 新情境由 [`packs/ms4022-productsupport/pack.yaml`](packs/ms4022-productsupport/pack.yaml) 產生在另一個**日期化**目錄；原 `scenarios/ms4022-productsupport/` 的資料與 `legacy/ms4022-engine/` 保留，但舊 runner 已停用正式執行，避免誤接不相容的新 engine；請改用日期化情境。對既有 Group 唯讀核對 owners/members；缺少即停止，不補權限。
- 此工具會建立 M365 Group，因此不適合以 `Sites.Selected` 縮限權限；請在專屬 demo tenant 或受控的測試範圍內執行。

## 必要條件

1. 安裝 PowerShell 7，並可連線至 Microsoft Graph。
2. 建立一個 Microsoft Entra app registration，採用 **Microsoft Graph application permissions**，不是 SharePoint API permissions。
3. 由租用戶管理員授與下列 permissions 的 admin consent：

| Permission | 程式需要的 Graph 操作 |
| --- | --- |
| `Group.ReadWrite.All` | 查詢或建立 Microsoft 365 Group，並設定 owner / member。 |
| `User.Read.All` | 由 `roles.Admin.upn` 與 `roles.DemoUser.upn` 解析 owner / member 的 Entra user ID。 |
| `Sites.Read.All` | 輪詢 `GET /groups/{id}/sites/root` 直到 group 的 SharePoint site 可用。 |
| `Sites.Manage.All` | 在已建立的 site 建立 `Products` document library 與 `Support Cases` 清單，並新增清單項目。 |
| `Files.ReadWrite.All` | 將 lab 的 Products 檔案上傳至 document library drive。 |

`GET /groups/{id}/sites/root` 的 app-only 最小權限是 `Sites.Read.All`。[官方 Graph site 文件](https://learn.microsoft.com/en-us/graph/api/site-get?view=graph-rest-1.0) 也列出這個 group site 路徑。以上權限對應的程式證據分別在 [Invoke-SeedSharePoint.ps1](legacy/ms4022-engine/Invoke-SeedSharePoint.ps1) 的 `/groups`、`/users`、`/sites/.../lists` 與 `/drives/.../content` 呼叫。權限或租用戶原則拒絕時，runner 會停止並保留 Graph 錯誤，請勿改以使用者帳密繞過。

## 設定

從 scenario 目錄建立僅限本機的設定檔：

```powershell
Set-Location .\seed-data\scenarios\ms4022-productsupport-20260929
Copy-Item .\config.json.example .\config.json
```

在 `config.json` 填入：

| 欄位 | 說明 |
| --- | --- |
| `tenantId` | 目標租用戶的 GUID。 |
| `clientId` | app registration 的 Application (client) ID。 |
| `clientSecret` | 該 app 的本機 secret value。不得提交或貼入文件。 |
| `roles.Admin.upn` | 將成為 demo group owner 的現有使用者 UPN。 |
| `roles.DemoUser.upn` | 將成為 demo group member、以自己 credentials 測試 SharePoint knowledge 與 connector 的現有使用者 UPN。 |
| `filesSourceDir` | 相對於 scenario root 的 Products 資料夾；runner 會由它推導 `Products.zip` 的下載位置。 |

## 執行

先用 `uv run --no-project` 的 generator 從 pack 產生日期化情境（用法同上，替換 `--pack`／`--output`）；再執行連線但**僅唯讀**的 preflight：

```powershell
pwsh -File .\run.ps1 -PreflightOnly
```

確認 alias、Products 文件庫、所有既有角色的啟用狀態及 owner/member 完整性後，才可能執行正式建立。**本次未對 MS-4022 情境執行線上寫入**：

```powershell
pwsh -File .\run.ps1
```

第一次正式執行才從 MicrosoftLearning 官方 lab repository 下載 `Products.zip`、解壓至 `filesSourceDir`；必須確認 **9 份**來源檔案齊全（含另行下載的 roadmap），否則在 Graph 寫入前停止。之後才建立 private group site 與 `Products` 文件庫並上傳檔案。若需不同版本，下載到新的日期化 scenario 目錄；**不要刪除或覆寫原檔**。重用已有 group 時，owner/member 缺少就中止，不會自動補授權。

## 完成條件

在 SharePoint 確認下列結果後，再進行 Copilot Studio lab：

1. 網站名稱為 `MS-4022 - Product support - <yyyyMMdd>`。
2. 有命名為 `Products` 的文件庫，且含 Products 範例檔案。
3. `roles.Admin.upn` 對該私人 site 具有 owner 存取權。
4. `roles.DemoUser.upn` 對該私人 site 具有 member 存取權。
5. 有名為 `Support Cases` 的清單，且含範例案件資料列。

Graph 建立的文件庫與清單不會自動出現在站台左側導覽。若希望上課時一眼可見，請在站台手動編輯導覽，加入 `/Products` 與 `/Lists/Support Cases` 兩個連結；這一步無法用目前的 Graph-only 權限自動完成。

接續的 Copilot Studio 設定與驗證步驟位於 [../docs/demo-environment.md](../docs/demo-environment.md)。
