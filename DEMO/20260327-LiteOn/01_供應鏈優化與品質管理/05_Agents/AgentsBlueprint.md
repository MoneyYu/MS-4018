# Copilot Chat Agents（無程式碼）— 設計稿：供應鏈品質管理

> **適用對象：** 光寶科技供應鏈與品質管理團隊
> **目標：** 讓學員理解 *Agent = 指令 + 知識來源 +（可選）行動*，用來把重複的問答與流程固化。

## Agent A：品質規範問答（LiteOn Quality Agent）
- **用途**：回答品質工程師（SQE）與供應鏈人員對『供應商品質管理政策』的常見問題，並給出引用來源段落。
- **知識來源**：SharePoint 文件庫（品質政策草案、IQC 檢驗規範、CAR 流程 SOP、供應商評分卡範本）
- **指令（Instructions）**：
  - 用繁體中文
  - 先給結論，再給依據（引用段落/章節/文件名稱）
  - 遇到不確定：說明缺口並建議要補哪些資料
  - 引用 SLA 時限時需標明等級（Critical/Major/Minor）
  - 不提供法律建議，必要時提醒諮詢法遵或品質長

## Agent B：供應商評級洞察（Supplier Insight Agent）
- **用途**：針對 /2025Q4_來料檢驗數據.xlsx 產出供應商品質洞察、風險分佈、建議改善行動。
- **知識來源**：OneDrive 或 SharePoint 的 Excel 檔案
- **指令**：
  - 先說明你做了哪些分析（篩選條件、計算方式）
  - 以條列輸出 Top 5 洞察 + 可能原因 + 建議行動
  - 標記紅色警示供應商（連續兩季不良率 > 3%）
  - 產出可直接貼進簡報的一段「高層摘要」(≤120 字)
  - 附引用來源（欄位名稱、篩選條件）

## Word Agent Mode（課堂 Demo 概念）
- **Word Agent**：在 Word 中以 Agent 方式固定『品質改善報告產生器』：
  - 輸入：會議紀錄 + 品質政策草案 + 來料檢驗數據摘要
  - 輸出：1 頁執行摘要 + 里程碑表 + 風險/緩解 + 「需要高層決策的 3 件事」
  - 操作：Copilot → Tools → Agent mode

## Excel Edit with Copilot（課堂 Demo 概念）
- **Excel Edit with Copilot**（原 Agent Mode）：在 Excel 中以 Edit with Copilot 模式固定『品質週報產生器』：
  - 開啟方式：Copilot → 看到「Let's edit together」歡迎訊息，或 Tools → Edit with Copilot
  - 輸入：最新來料檢驗數據表
  - 輸出：供應商 KPI 摘要表、不良率趨勢圖、高風險案件清單、異常樞紐分析

> *注意：不同租戶/版本 UI 可能顯示為「代理(Agent)」或「使用代理」等字樣。Edit with Copilot 為 2026 年 3 月更新的新功能，原名為 Agent Mode。*
