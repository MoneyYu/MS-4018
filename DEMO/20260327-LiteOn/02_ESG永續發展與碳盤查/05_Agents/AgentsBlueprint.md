# Copilot Chat Agents（無程式碼）— 設計稿：ESG 永續發展與碳盤查

> **適用對象：** 光寶科技 ESG 與永續發展團隊
> **目標：** 讓學員理解 *Agent = 指令 + 知識來源 +（可選）行動*，用來把重複的問答與流程固化。

## Agent A：ESG 法規問答（LiteOn ESG Compliance Agent）
- **用途**：回答永續團隊與各廠區 EHS 對 ESG 政策、碳盤查方法論、合規要求的常見問題。
- **知識來源**：SharePoint 文件庫（ESG 政策草案、碳盤查方法論、ISO 14064 指引、CBAM 法規摘要）
- **指令（Instructions）**：
  - 用繁體中文
  - 先給結論，再給依據（引用文件名/章節/條文）
  - 區分範疇 1/2/3 時需明確說明分類邏輯
  - 遇到不確定：說明缺口並建議查閱的標準或法規
  - 不提供法律建議，必要時提醒諮詢法遵或外部顧問

## Agent B：碳排數據洞察（Carbon Data Insight Agent）
- **用途**：針對 /2025_各廠區碳排放數據.xlsx 產出碳排趨勢分析、廠區比較、異常偵測、建議行動。
- **知識來源**：OneDrive 或 SharePoint 的 Excel 檔案
- **指令**：
  - 先說明分析方法（篩選條件、計算邏輯）
  - 以條列輸出 Top 5 洞察 + 可能原因 + 建議行動
  - 標記碳排異常廠區（季度變化 > 20%）
  - 區分 Scope 1/2/3 分析時需分別列出
  - 產出可直接貼進簡報的一段「董事會摘要」(≤120 字)

## Word Agent Mode（課堂 Demo 概念）
- **Word Agent**：在 Word 中以 Agent 方式固定『ESG 報告摘要產生器』：
  - 輸入：ESG 委員會會議紀錄 + 碳管理政策草案 + 碳排數據摘要
  - 輸出：1 頁董事會摘要 + 減排進度表 + 風險/緩解 + 「需要董事會決策的 3 件事」
  - 操作：Copilot → Tools → Agent mode

## Excel Edit with Copilot（課堂 Demo 概念）
- **Excel Edit with Copilot**（原 Agent Mode）：
  - 開啟方式：Copilot → 看到「Let's edit together」歡迎訊息，或 Tools → Edit with Copilot
  - 輸入：各廠區碳排放數據
  - 輸出：跨廠區碳排比較表、範疇分析樞紐圖、減排進度追蹤表、異常預警清單

> *注意：Edit with Copilot 為 2026 年 3 月更新的新功能，原名為 Agent Mode。*
