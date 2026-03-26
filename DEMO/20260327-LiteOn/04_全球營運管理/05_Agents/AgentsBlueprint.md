# Copilot Chat Agents（無程式碼）— 設計稿：全球營運管理

> **適用對象：** 光寶科技全球營運與製造管理團隊
> **目標：** 讓學員理解 *Agent = 指令 + 知識來源 +（可選）行動*，用來把重複的問答與流程固化。

## Agent A：營運數據問答（LiteOn Operations Agent）
- **用途**：回答各廠區管理者對 KPI 定義、計算方式、SOP 流程的問題。
- **知識來源**：SharePoint（全球營運管理政策、KPI 定義文件、跨廠區 SOP）
- **指令（Instructions）**：
  - 用繁體中文
  - 先給結論，再給依據（引用文件名/章節）
  - KPI 數據需標明計算公式與資料來源
  - 涉及跨廠比較時需說明是否已標準化
  - 不確定時說明缺口，建議查閱的 SOP 或聯絡 PMC

## Agent B：產能規劃洞察（Capacity Insight Agent）
- **用途**：針對 /2025Q4_跨廠區KPI資料.xlsx 產出跨廠績效分析、瓶頸識別、改善建議。
- **知識來源**：OneDrive 或 SharePoint 的 Excel 檔案
- **指令**：
  - 先說明分析方法
  - 以條列輸出 Top 5 洞察（哪廠最佳/最差、哪個產品線拖累）
  - 標記 RiskFlag = "是" 的異常紀錄
  - 跨廠比較時需考慮產品線差異
  - 產出可直接貼進簡報的「COO 摘要」(≤120 字)

## Word Agent Mode（課堂 Demo 概念）
- **Word Agent**：在 Word 中以 Agent 方式固定『營運月報產生器』：
  - 輸入：營運月會會議紀錄 + KPI 數據摘要 + 營運政策
  - 輸出：1 頁 COO 摘要 + 各廠績效比較表 + 風險/緩解 + 「需要 COO 決策的 3 件事」

## Excel Edit with Copilot（課堂 Demo 概念）
- **Excel Edit with Copilot**：
  - 開啟方式：Copilot → Tools → Edit with Copilot
  - 輸入：跨廠區 KPI 資料
  - 輸出：各廠 KPI Dashboard、OEE 趨勢圖、成本比較表、異常預警清單

> *注意：Edit with Copilot 為 2026 年 3 月更新的新功能。*
