# Copilot Chat Agents（無程式碼）— 設計稿：新產品開發與市場策略

> **適用對象：** 光寶科技產品開發與技術行銷團隊
> **目標：** 讓學員理解 *Agent = 指令 + 知識來源 +（可選）行動*，用來把重複的問答與流程固化。

## Agent A：技術規格問答（LiteOn Product Spec Agent）
- **用途**：回答 RD、業務、客戶對 GaN 電源產品技術規格、認證要求、Phase-Gate 流程的問題。
- **知識來源**：SharePoint（新產品開發流程規範、產品規格書、Gate Review 記錄、安規認證清單）
- **指令（Instructions）**：
  - 用繁體中文
  - 先給結論，再給依據（引用文件名/章節）
  - 技術參數需標明單位與條件（如效率 @100% load, 25°C）
  - 涉及客戶機密規格時提醒：「此為內部資訊，對外回覆前需經 PM 審核」
  - 不確定時說明缺口，建議查閱的規格文件或聯絡窗口

## Agent B：市場洞察（Market Insight Agent）
- **用途**：針對 /2026_AI伺服器電源市場競爭分析.xlsx 產出市場洞察、競品比較、定價建議。
- **知識來源**：OneDrive 或 SharePoint 的 Excel 檔案
- **指令**：
  - 先說明分析方法
  - 以條列輸出 Top 5 洞察 + 競爭態勢 + 建議行動
  - 標記異常數據（如價格異常低的產品）
  - 產出可直接貼進簡報的「市場定位摘要」(≤120 字)
  - 附引用來源（欄位名、篩選條件）

## Word Agent Mode（課堂 Demo 概念）
- **Word Agent**：在 Word 中以 Agent 方式固定『上市計畫摘要產生器』：
  - 輸入：Gate Review 會議紀錄 + 競爭分析數據 + 產品規格書
  - 輸出：1 頁執行摘要 + 競爭定位表 + 風險/緩解 + 「需要高層決策的 3 件事」

## Excel Edit with Copilot（課堂 Demo 概念）
- **Excel Edit with Copilot**：
  - 開啟方式：Copilot → Tools → Edit with Copilot
  - 輸入：市場競爭分析資料
  - 輸出：效率/價格矩陣、市場趨勢圖、競品監控儀表板、異常價格標記

> *注意：Edit with Copilot 為 2026 年 3 月更新的新功能。*
