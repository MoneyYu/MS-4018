# MS-4018 講師 Demo 索引

> 講師備課用途；此檔位於**公開** repository，並非存取控制邊界。示範前請自行確認檔案的分享權限、內容與可公開程度。學員課程連結請見 [README](../README.md)。

本課以 Microsoft 365 Copilot、Copilot Chat、Word、PowerPoint、Teams、Excel、Outlook 和 agents 的工作流程為主；不使用 Azure 資源。沒有 Terraform、Foundry model deployment、`apply/destroy` 步驟。講師可選用既有 `DEMO/` 材料預先準備可存取的檔案與會議，而不是在課中從零建立環境。

| 既有目錄 | 內容與用途 | 起點 |
| --- | --- | --- |
| [`DEMO/20260115-MEGABANK/`](../DEMO/20260115-MEGABANK/) | 單一情境：文件草擬、資料分析、會議／簡報與 agent 範例。 | [`MS-4018_Full_LiveDemo_Runbook_兆豐銀行.md`](../DEMO/20260115-MEGABANK/MS-4018_Full_LiveDemo_Runbook_兆豐銀行.md) |
| [`DEMO/20260327-LiteOn/`](../DEMO/20260327-LiteOn/) | 四組情境：供應鏈品質、ESG 碳盤查、新產品策略、全球營運；各有 story、docs、data、prompts、agents 等。 | [`00_Readme.txt`](../DEMO/20260327-LiteOn/00_Readme.txt) |
| [`DEMO/20260929-Ford/`](../DEMO/20260929-Ford/) | 一條虛構的福特汽車業務故事：Teams 五個 channel、Outlook 郵件串、Excel 五本資料表。簡體中文資料、繁體中文講師手冊。 | [`MS-4018_LiveDemo_Runbook_Ford.md`](../DEMO/20260929-Ford/MS-4018_LiveDemo_Runbook_Ford.md) |

Ford Demo 由 [`seed-data/packs/ms4018-ford-auto/pack.yaml`](../seed-data/packs/ms4018-ford-auto/pack.yaml) 產生；依 [`seed-data/README.md`](../seed-data/README.md) 使用 `uv` generator，先 `-PreflightOnly` 唯讀驗證現有 tenant 帳號，再決定是否執行。不得建立使用者或改寫共用身份；所有數字均為模擬，不是 Ford 真實業績。

## 課前檢查

1. 選**一個**適合本次班級的情境；不要把不同情境的數字與結論混用。檢查示範檔案、名稱與聯絡資料是否允許在課堂使用，避免把敏感內容帶進 Copilot 或公開畫面。
2. 將示範所需檔案放在示範帳號**有權存取**的 OneDrive 或 SharePoint，並確認 Microsoft 365 Copilot 授權與 Teams／Outlook 功能可用；本機路徑不會自動成為 Copilot 可用的 work context。
3. 預先準備 Chat grounding、Word 草稿、PowerPoint 簡報、Excel 工作表、Teams **已排程**會議與 Outlook 討論串。會議的 transcription、Facilitator 與 recap 取決於授權、租用戶政策及主辦者設定；不能保證每個租用戶都可演示。
4. 先測一次「模糊 prompt → 指定來源與期望 → 人工核對」流程。預備靜態結果作為課堂網路或功能不可用時的備案，避免宣稱 Copilot 會產出完全相同文字。
5. `PPT/` 是講師本機投影片，不進 repository；不要把投影片 speaker notes、問卷參數或 Skillable key 放在此文件。

Lab 為另一路徑：依官方 [MS-4018 Lab index](https://microsoftlearning.github.io/MS-4018-Draft-analyze-present-Microsoft-365-Copilot/) 操作。Lab 00 是設定，Lab 01–05 分別對應 Chat、PowerPoint、Word、Teams、Excel；現行 lab repo **沒有** Outlook 練習。講師節奏與常見問題見 [備課指南](teaching-guide.md)。
