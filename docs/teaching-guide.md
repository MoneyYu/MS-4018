# MS-4018-A 備課指南（講師用）

> 本文件位於**公開** repository，請勿寫入租用戶、帳號、憑證或私人學員資料；學生頁面見 [README](../README.md)。每次授課前以 [官方課程頁](https://learn.microsoft.com/en-us/training/courses/ms-4018) 與 [learning path](https://learn.microsoft.com/en-us/training/paths/draft-analyze-present-microsoft-365-copilot/) 核對。舊版材料的差異見 [版本說明](version-change-notes.md)。

## 課程概覽

**定位：** 一天的商務使用者課程，以 Microsoft 365 Copilot 在熟悉的 Word、PowerPoint、Excel、Teams、Outlook 與 Copilot Chat 中協助日常工作。適合已有 Microsoft 365 基礎操作經驗的學員。不是 Azure 資源部署課，也不是特定模型的 API 課；Terraform 與 Foundry 模型退役檢查不適用。課程頁標示 **Achievement Code**，不是本課的 Applied Skills 或考試。

**版本警示：** 2026 年的 [MS-4018-A](https://learn.microsoft.com/en-us/training/courses/ms-4018) 已明確排成七模組。請勿沿用舊 README 中依 app 分組的大型連結索引或未驗證影片當作教學大綱。`PPT/` 的 `_00` 為課前、`_01`–`_07` 對應模組 1–7、`_08` 為結語；備課應依模組 deck 的 speaker notes 安排 demo，而非把每張投影片都講完。

## 課程地圖：7 個模組

| 模組 | 學習重點 | 對應官方 Lab |
| --- | --- | --- |
| [M01 Get ready to work with Microsoft Copilot](https://learn.microsoft.com/en-us/training/modules/get-ready-work-microsoft-365-copilot/) | Work IQ、work/web grounding、EDP、四元素 prompt | Lab 00 設定（無獨立 M01 練習） |
| [M02 Unlock productivity and unleash creativity with AI powered chat](https://learn.microsoft.com/en-us/training/modules/unlock-productivity-unleash-creativity-ai-powered-chat/) | Chat、Search、Prompt Coach、Pages | Lab 01 Chat |
| [M03 Build effective presentations with AI](https://learn.microsoft.com/en-us/training/modules/present-copilot-microsoft-powerpoint/) | Idea Coach → 建立／修改簡報 → 講者準備 | Lab 02 PowerPoint |
| [M04 Draft impactful documents using AI](https://learn.microsoft.com/en-us/training/modules/draft-impactful-documents-using-ai/) | 參照來源起草、Rewrite、Writing Coach | Lab 03 Word |
| [M05 Make your meetings more productive with AI](https://learn.microsoft.com/en-us/training/modules/make-your-meetings-more-productive-ai/) | 會前／會中／會後、Facilitator、Recap | Lab 04 Teams |
| [M06 Uncover new data insights with AI](https://learn.microsoft.com/en-us/training/modules/uncover-new-data-insights-ai/) | Excel modes、公式／PivotTable、Python、Analyst | Lab 05 Excel |
| [M07 From inbox to impact: Improve your email workflows with AI](https://learn.microsoft.com/en-us/training/modules/from-inbox-impact-improve-your-email-workflows-ai/) | 收件匣整理、草擬與教練、會議後續 | 無編號 Outlook lab；可做講師引導練習 |

Lab 的唯一學員入口為 [官方 hosted index](https://microsoftlearning.github.io/MS-4018-Draft-analyze-present-Microsoft-365-Copilot/)；不要假定 M07 另有 Lab 06。

## 建議議程與時間分配

| 時段 | 內容 |
| --- | --- |
| 09:00–09:25 | 開場、授權與 Lab 00 確認、M01 開頭 |
| 09:25–10:15 | M01 與 prompt 的模糊／具體對比 |
| 10:15–10:30 | 休息 |
| 10:30–11:20 | M02＋Lab 01：Chat、Search、Pages |
| 11:20–12:10 | M03＋Lab 02：簡報故事、建立、檢查 |
| 12:10–13:00 | 午餐 |
| 13:00–13:50 | M04＋Lab 03：Word 起草與改善 |
| 13:50–14:45 | M05＋Lab 04：Teams 會議流程 |
| 14:45–15:00 | 休息 |
| 15:00–16:00 | M06＋Lab 05：Excel 結構化資料與分析 |
| 16:00–16:40 | M07：Outlook 互動示範（無編號 lab） |
| 16:40–17:00 | 跨 app 情境統整、Q&A、回饋 |

依班級熟悉度調整；Lab 若需較長時間，從影片或重複的 live demo 挪時間，保留人工核對與 Q&A。

## 貫穿全課的核心觀念

| 選擇 | 何時用 | 每次示範提醒 |
| --- | --- | --- |
| **Work grounding** | 內部檔案、會議、信件與聊天 | Copilot 尊重既有權限；找不到來源時先檢查帳號與檔案位置。 |
| **Web grounding** | 外部趨勢與公開資料 | 與內部資料分開比對來源、時效和可信度。 |
| **Chat / App / Agent** | 探索與彙整 / 已知輸出格式 / 多步驟專業任務 | 選合適入口，不要把一切都塞在單一 prompt。 |
| **Context / Goal / Source / Expectations** | 所有 prompt 的可操作框架 | 先提供任務背景，再要求具體成果、可信來源、對象與格式；回覆後繼續 refine。 |
| **EDP / sensitivity labels** | 分享或分析工作資料時 | [EDP](https://learn.microsoft.com/en-us/microsoft-365/copilot/enterprise-data-protection) 不等於自動批准資料分享；仍要檢查權限與標籤。 |

講師示範採用「模糊提問 → 加入文件／context → 指定 output → 驗證引用與事實 → 決定是否套用／寄送」循環。可使用 [現有 Demo 索引](demo-environment.md) 選一個情境串起全課；不要在學員 README 放置講師設定細節。

## 逐模組備課指南

### M01 — Get ready to work with Microsoft Copilot
**學習目標：** 解釋 Work IQ、應用程式 context、work/web grounding、權限與四元素 prompt。

**講解重點：** `_01` slides 5–10：相同 prompt 因來源和 app 不同而結果不同；Work IQ 串接工作訊號但不擴張權限。以 Context、Goal、Source、Expectations 示範好 prompt，不必為每個短 prompt 硬湊四要素。

**Demo / Lab：** 先顯示「幫我準備會議」的泛用回答，再指向有權存取的會議／檔案與輸出格式。Lab 00 檢查環境，M01 沒有獨立編號練習。

**常見問題 / 坑：** 「Copilot 能讀取我無權開啟的檔案嗎？」不能；先查共用權限、存放位置和目前登入身分。EDP 不表示生成內容免審核。

**重要連結：** [M01 module](https://learn.microsoft.com/en-us/training/modules/get-ready-work-microsoft-365-copilot/) · [資料與隱私](https://learn.microsoft.com/en-us/microsoft-365/copilot/microsoft-365-copilot-privacy)。

### M02 — Unlock productivity and unleash creativity with AI powered chat
**學習目標：** 區分 Search 與 Chat、work 與 web；使用 Prompt Coach、agents 和 Copilot Pages。

**講解重點：** `_02` slides 11–18：Search 用於找已知文件，Chat 適合統整／生成。Auto、Quick response、Think deeper 的選擇依任務深度；Pages 將一次性回應轉為可修改、可分享草稿。

**Demo / Lab：** Lab 01。對比「找這個檔案」和「歸納這些檔案」；用 `/` 指定來源，再從回覆建立 Page。

**常見問題 / 坑：** Prompt Coach 或 model selector 可能受授權、租用戶和應用程式入口影響，現場無法顯示時用投影片，不要承諾所有版本 UI 相同。

**重要連結：** [M02 module](https://learn.microsoft.com/en-us/training/modules/unlock-productivity-unleash-creativity-ai-powered-chat/) · [Copilot Chat](https://support.microsoft.com/en-us/microsoft-365-copilot/get-started-with-microsoft-365-copilot-chat) · [Copilot Pages](https://support.microsoft.com/en-us/microsoft-365-copilot/get-started-with-microsoft-365-copilot-pages)。

### M03 — Build effective presentations with AI
**學習目標：** 從故事規劃到建立簡報、修改內容／視覺、準備講者備註與演練。

**講解重點：** `_03` slides 7–17：Idea Coach 先釐清受眾和敘事，**不是**直接替你生投影片；將 narrative 交給 PowerPoint 後分段 refine，最後檢查資料、視覺品牌一致性與 speaker notes。

**Demo / Lab：** Lab 02。先讓 Idea Coach 追問，再以明確受眾和訊息建立簡報；對同一圖像比較泛用與具體 prompt，生成 notes 後只針對一張投影片改語氣。

**常見問題 / 坑：** 不應預期一次 prompt 產生可直接上台的簡報；翻譯後檢查圖中文字與排版，講者 notes 也需人工核對。

**重要連結：** [M03 module](https://learn.microsoft.com/en-us/training/modules/present-copilot-microsoft-powerpoint/) · [建立簡報](https://support.microsoft.com/en-us/powerpoint/copilot/create-a-new-presentation-with-copilot-in-powerpoint)。

### M04 — Draft impactful documents using AI
**學習目標：** 使用文件／信件／會議來源起草，針對特定段落改寫，並以 Writing Coach 改進全文。

**講解重點：** `_04` slides 9–17：有明確來源的草稿比空白 prompt 更具體。Auto Rewrite 處理局部內容，Writing Suggestions／Writing Coach 側重整體回饋；不是同一種修稿操作。

**Demo / Lab：** Lab 03。比較無參照和引用可存取檔案的初稿；改寫一段，再問文件摘要並點擊引用核對。

**常見問題 / 坑：** 本機未上傳的檔案不會自動成為 work grounding；不是每個回答都有引用，尤其是開放式建議。高風險內容送出前仍要人工審查。

**重要連結：** [M04 module](https://learn.microsoft.com/en-us/training/modules/draft-impactful-documents-using-ai/) · [起草文件](https://support.microsoft.com/en-us/word/copilot/draft-and-add-content-with-copilot-in-word)。

### M05 — Make your meetings more productive with AI
**學習目標：** 會前整理資訊，依需求選會中 Copilot 設定，使用 Facilitator 和會後 Recap。

**講解重點：** `_05` slides 12–19：會中 Copilot 不等於一定要錄影；Facilitator 可協助議程、計時、筆記與任務。Intelligent Recap 用來核對結論、待辦與逐字稿；不要把摘要當成會議正式決議。

**Demo / Lab：** Lab 04。事先備好**排程**會議，展示會前資訊、會中提問（例如「哪裡還沒共識？」）、Recap 的 tasks 和逐字稿，最後請學員核對負責人。

**常見問題 / 坑：** Facilitator 不支援 channel／臨時會議或 Teams 通話；發起人的邀請函內容可能無法直接由 Facilitator 讀取。轉錄、錄影、標籤及 retention 取決於租用戶政策；使用前先檢查授權與主辦者設定。

**重要連結：** [M05 module](https://learn.microsoft.com/en-us/training/modules/make-your-meetings-more-productive-ai/) · [Facilitator](https://support.microsoft.com/en-us/teams/copilot/facilitator-in-microsoft-teams-meetings)。

### M06 — Uncover new data insights with AI
**學習目標：** 整理表格、選 Excel modes，運用公式／PivotTable／進階分析，理解 Analyst 何時先於 Excel 使用。

**講解重點：** `_06` slides 13–18：多檔案先用 Analyst 比較和篩選，確定範圍再進 Excel。Chat only 做說明但不修改，Plan 先審步驟，Allow editing 才允許更動工作簿；Python 用於較深的預測與模型，不要求學員先學會寫 Python。

**Demo / Lab：** Lab 05。用已整理的表格分別詢問洞察、審查修改計畫、建立公式或 PivotTable；若環境可用，再示範 forecast 並檢查基礎假設。

**常見問題 / 坑：** 非結構化資料也許能回答簡單問題，但表格功能需要較乾淨的資料；Excel 的計算及預測不能直接當財務結論。舊「Python 分析」支援頁已退役，不引用舊連結。

**重要連結：** [M06 module](https://learn.microsoft.com/en-us/training/modules/uncover-new-data-insights-ai/) · [Excel 起步](https://support.microsoft.com/en-us/excel/copilot/get-started-with-copilot-in-excel)。

### M07 — From inbox to impact: Improve your email workflows with AI
**學習目標：** 整理收件匣、摘要討論串、草擬並審閱郵件，將需要討論的主題轉為會議與追蹤。

**講解重點：** `_07` slides 8–15：以「triage → summarize → draft → coach → schedule／follow-up」教學，而非逐一念功能。Coaching by Copilot 用於寄信前快速修正，Writing Coach 適合較深入的審閱；送信是人的決定。

**Demo / Lab：** 沒有編號 Outlook lab。以預先準備的討論串示範摘要、關鍵決策追問、草稿與語氣調整，再檢查收件者、附件、時間與承諾；不以真人信件資料示範。

**常見問題 / 坑：** 草稿不是已寄出；外部帳號與租用戶設定可能限制功能。把討論串轉會議前先核對參與者和議程；不要替學員點擊傳送。

**重要連結：** [M07 module](https://learn.microsoft.com/en-us/training/modules/from-inbox-impact-improve-your-email-workflows-ai/) · [Outlook 草擬](https://support.microsoft.com/en-us/outlook/copilot-pages/draft-an-email-message-with-copilot-in-outlook)。

## 預期學員問題 Q&A

- **「這門課有證照或 Applied Skills 嗎？」** 官方課程頁顯示 Achievement Code；未列本課專屬考試或 Applied Skills。不要將其他 AI 商務證照自動宣稱為本課資格。
- **「Copilot 會看到不該看的資料嗎？」** 它以登入使用者既有權限為界，但錯誤分享設定仍是風險；先治理權限，並檢查輸出和 sensitivity labels。
- **「資料沒有出現在 Copilot，怎麼辦？」** 先檢查目前登入帳號、授權、OneDrive／SharePoint 的檔案位置、共用權限、會議轉錄與租用戶設定；不要直接改用公開 web prompt 貼入內部資料。
- **「為什麼 Lab 沒有 Outlook？」** 目前官方 [Lab index](https://microsoftlearning.github.io/MS-4018-Draft-analyze-present-Microsoft-365-Copilot/) 只到 Excel；M07 改用講師引導的安全情境練習。

## 課前準備清單（前 1–2 天）

- [ ] 確認官方課程、7 個模組與 Lab repo 未改版，重新驗證 README 和影片連結。
- [ ] 向主辦方取得**本梯次** Date、Course ID、Survey URL、Skillable Training key；現有 survey 在匿名驗證導向 Fault 頁，請先與主辦方確認再交給學員。
- [ ] 用示範帳號確認 Microsoft 365 Copilot 授權、預備 app 功能、資料權限、已排程 Teams 會議與可用 transcription；有功能或配額限制時備妥事先錄製／截圖替代展示。
- [ ] 依 [Demo 索引](demo-environment.md) 選一組情境，逐份確認可公開性；不要把真實個資或憑證帶入 prompt。
- [ ] 預跑 Lab 00–05，檢查學員登入、儲存與 PowerPoint／Word／Excel 初始資料；M07 不要承諾不存在的 Outlook lab。
- [ ] 每模組準備一個失敗／模糊的 prompt、一個改進後 prompt，以及核對來源的步驟。

## 講師小技巧

- 每一段先問「你想交付什麼？」再選 Chat、App 或 Agent，讓工具選擇依情境而非功能名稱。
- 功能或租用戶能力不一致時，用已準備的畫面解釋決策和審查方式；不要在課堂中更動管理政策來追求相同 UI。
- 每次 live demo 預留可見的人工驗證步驟：引用、數字、圖表軸、收件者、參與者、隱私標籤；Copilot 的回覆是草稿而非權威事實。
- 時間不足時略過重複的影片或第二個情境，保留 M01 基礎框架和 M07 沒有 lab 的說明。

## 參考

[Course MS-4018-A](https://learn.microsoft.com/en-us/training/courses/ms-4018) · [Learning path](https://learn.microsoft.com/en-us/training/paths/draft-analyze-present-microsoft-365-copilot/) · [Lab index](https://microsoftlearning.github.io/MS-4018-Draft-analyze-present-Microsoft-365-Copilot/) · [Demo 索引](demo-environment.md) · [版本說明](version-change-notes.md)
