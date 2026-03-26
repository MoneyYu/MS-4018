# /// script
# requires-python = ">=3.10"
# dependencies = ["python-docx", "openpyxl"]
# ///
"""
光寶科技 MS-4018 Demo 範例檔案產生器
產生 4 個場景的 Word (.docx) 和 Excel (.xlsx) 範例檔案
"""
import os
import random
from datetime import datetime, timedelta
from docx import Document
from docx.shared import Pt
from openpyxl import Workbook
from openpyxl.worksheet.table import Table, TableStyleInfo
from openpyxl.styles import Font, PatternFill, Alignment

BASE = os.path.dirname(os.path.abspath(__file__))
random.seed(42)

# ============================================================
# Helper functions
# ============================================================

def make_doc(path, title, subtitle, sections):
    """Create a .docx with Title + Heading1 sections."""
    doc = Document()
    style = doc.styles['Title']
    style.font.size = Pt(18)
    doc.add_paragraph(title, style='Title')
    doc.add_paragraph(subtitle, style='Normal')
    for heading, paragraphs in sections:
        doc.add_paragraph(heading, style='Heading 1')
        for p in paragraphs:
            doc.add_paragraph(p, style='Normal')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    doc.save(path)
    print(f"  ✓ {os.path.basename(path)}")


def make_excel(path, sheets_config):
    """Create .xlsx with named tables. sheets_config = [(sheet_name, headers, rows)]"""
    wb = Workbook()
    for idx, (sheet_name, headers, rows) in enumerate(sheets_config):
        if idx == 0:
            ws = wb.active
            ws.title = sheet_name
        else:
            ws = wb.create_sheet(sheet_name)
        # Write headers
        for col, h in enumerate(headers, 1):
            cell = ws.cell(row=1, column=col, value=h)
            cell.font = Font(bold=True)
            cell.fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
            cell.font = Font(bold=True, color="FFFFFF")
            cell.alignment = Alignment(horizontal="center")
        # Write data
        for r_idx, row in enumerate(rows, 2):
            for c_idx, val in enumerate(row, 1):
                ws.cell(row=r_idx, column=c_idx, value=val)
        # Create Table
        end_col = chr(64 + len(headers)) if len(headers) <= 26 else "Z"
        end_row = len(rows) + 1
        table_ref = f"A1:{end_col}{end_row}"
        safe_name = sheet_name.replace(" ", "_").replace("/", "_")[:20]
        table = Table(displayName=f"Table_{safe_name}_{idx}", ref=table_ref)
        table.tableStyleInfo = TableStyleInfo(
            name="TableStyleMedium2", showFirstColumn=False,
            showLastColumn=False, showRowStripes=True, showColumnStripes=False
        )
        ws.add_table(table)
        # Auto-width columns
        for col_idx, h in enumerate(headers, 1):
            max_len = len(str(h))
            for row in rows[:20]:
                val = row[col_idx - 1] if col_idx - 1 < len(row) else ""
                max_len = max(max_len, len(str(val)))
            ws.column_dimensions[chr(64 + col_idx)].width = min(max_len + 4, 30)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wb.save(path)
    print(f"  ✓ {os.path.basename(path)}")


def rand_date(start, end):
    delta = end - start
    return (start + timedelta(days=random.randint(0, delta.days))).strftime("%Y-%m-%d")


# ============================================================
# SCENARIO 1: 供應鏈優化與品質管理
# ============================================================
def gen_scenario1():
    print("\n[場景 1] 供應鏈優化與品質管理")
    base = os.path.join(BASE, "01_供應鏈優化與品質管理")

    # --- Doc 1: 政策草案 ---
    make_doc(
        os.path.join(base, "02_Docs", "光寶_供應商品質管理政策草案_v0.9.docx"),
        "光寶科技｜供應商品質管理與來料檢驗政策（草案 v0.9）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("1. 目的與範圍", [
                "本政策用於規範光寶科技所有事業群之供應商來料檢驗、品質異常處理與持續改善流程。",
                "適用範圍：電源供應器、LED 元件、光儲存模組、影像感測模組等所有產品線之原物料與零組件採購。",
                "本政策依據 ISO 9001:2015 與 IATF 16949（車用產品線）之要求制定，並配合客戶特殊要求（CSR）執行。",
            ]),
            ("2. 角色與責任", [
                "品質工程（SQE）：執行來料檢驗、發出 CAR（Corrective Action Request）、追蹤改善成效。",
                "供應鏈管理（SCM）：供應商開發與評鑑、交期管理、備援供應商規劃。",
                "研發工程（RD）：規格確認、替代料驗證、工程變更通知（ECN）配合。",
                "製造工程（ME）：產線品質回饋、不良品分析（8D/5Why）、製程改善。",
                "法遵與稽核：供應商社會責任稽核、有害物質管理（RoHS/REACH）合規確認。",
            ]),
            ("3. 服務等級與回應時限（SLA）", [
                "Critical 等級（停線風險）：供應商需於 4 小時內回覆初步分析，24 小時內提出臨時對策，7 天內完成 8D 報告。",
                "Major 等級（批退/良率低於標準）：供應商需於 24 小時內回覆，5 個工作天內提出改善計畫。",
                "Minor 等級（偶發性異常）：供應商需於 48 小時內回覆，10 個工作天內完成改善。",
                "若供應商未於規定時限內回覆，將自動升級至下一等級，並列入季度考核扣分。",
            ]),
            ("4. 來料檢驗標準與抽樣計畫", [
                "抽樣計畫依 MIL-STD-1916 或客戶指定標準執行，AQL 依產品風險等級設定（Critical: 0.065, Major: 0.25, Minor: 1.0）。",
                "新供應商首批交貨採全檢（Full Inspection），連續三批合格後轉正常抽檢。",
                "外觀、尺寸、電氣特性、可靠度測試項目依《IQC 檢驗規範》執行。",
                "檢驗紀錄需保留至少 7 年（車用產品線為 15 年），並定期上傳至品質管理系統。",
            ]),
            ("5. 常見風險與緩解措施", [
                "風險：供應商品質數據造假、抽樣不具代表性、跨廠區檢驗標準不一致。",
                "風險：單一供應商依賴度過高（占比 > 60%），斷鏈風險大。",
                "風險：有害物質超標未及時發現，導致整批出貨召回。",
                "緩解：建立供應商評分卡（Scorecard），每季公布並與採購策略連動。",
                "緩解：推動雙源策略，關鍵料件至少維持 2 家合格供應商。",
                "緩解：建立 Copilot Agent 供品質規範快速查詢，減少人為判斷誤差。",
            ]),
        ]
    )

    # --- Doc 2: 會議紀錄 ---
    make_doc(
        os.path.join(base, "02_Docs", "會議紀錄_來料品質改善檢討_2026-03-20.docx"),
        "會議紀錄｜來料品質改善檢討會議（2026/03/20）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("會議資訊", [
                "日期：2026/03/20（四）14:00–15:30",
                "地點：光寶科技內湖總部 8F 會議室 B",
                "與會：品質工程（SQE）、供應鏈管理（SCM）、研發工程（RD）、製造工程（ME）、廠區品保代表（泰國/中國）",
                "主題：2025 Q4 來料品質異常檢討與 2026 Q1 改善目標設定",
            ]),
            ("討論要點", [
                "1) 2025 Q4 來料不良率整體為 2.8%，較 Q3（2.1%）上升 0.7 個百分點，主要集中於電容與連接器品類。",
                "2) 供應商「鴻碩精密」連續兩季不良率偏高（Q3: 4.2%、Q4: 6.8%），已發出 2 次 CAR 但改善成效不彰。",
                "3) 泰國廠反映「瑞昱電子」交貨的 IC 批次間一致性不足，導致產線調機時間增加約 15%。",
                "4) 新導入供應商「聯穎光電」首批 LED 晶粒良率達 99.2%，表現優異，建議加速擴大採購比重。",
                "5) 車用產品線客戶（某歐系車廠）要求 2026 Q2 起提供完整追溯報告，需加強批次追蹤機制。",
                "6) 有害物質檢測方面，Q4 有 1 件 REACH SVHC 新增物質預警，已通知供應商提供更新的材料聲明書。",
            ]),
            ("決策", [
                "- 對「鴻碩精密」啟動『紅色警示』機制：限期 60 天改善，若 Q1 不良率仍 > 3% 則啟動替代供應商切換流程。",
                "- 建立來料品質即時儀表板：以 Excel Copilot 每週自動產出趨勢分析與異常標記。",
                "- 跨廠區檢驗標準對齊：由品質主管統一修訂《IQC 檢驗規範 v3.0》，Q1 內完成。",
                "- 試辦：以 Copilot Chat 建立品質規範問答 Agent，降低新進 SQE 查閱規範的時間成本。",
            ]),
            ("擬辦事項", [
                "A1：SQE 主管（張育誠）— 3/27 前完成供應商評分卡 Q4 更新，標記紅色警示供應商。",
                "A2：SCM（林佳蓉）— 3/31 前盤點備援供應商清單，並啟動「鴻碩精密」替代源評估。",
                "A3：RD（陳柏翰）— 4/5 前完成「瑞昱電子」IC 規格公差分析，提出建議收緊範圍。",
                "A4：ME（王素芬）— 4/5 前彙整泰國/中國兩廠 Q4 來料異常案例，統一編碼格式。",
                "A5：你 — 4/7 前完成高層提案文件（含 KPI、改善方案、風險與資源需求），並產出簡報初稿。",
            ]),
        ]
    )

    # --- Doc 3: 高層提案初稿 ---
    make_doc(
        os.path.join(base, "02_Docs", "高層提案_供應鏈品質提升與風險控管_初稿.docx"),
        "光寶科技｜2026 Q1 供應鏈品質提升與來料風險控管提案（初稿）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("執行摘要（Draft）", [
                "本提案聚焦於供應商來料品質改善與供應鏈韌性強化。",
                "目標：將來料不良率從 2.8% 降至 1.5% 以下、縮短 CAR 結案天數至 10 天內、關鍵料件雙源比例提升至 80%。",
            ]),
            ("現況與問題", [
                "- 2025 Q4 來料不良率 2.8%，高於年度目標 2.0%，主因集中於電容與連接器品類。",
                "- 特定供應商（鴻碩精密）連續兩季不良率偏高，CAR 改善率僅 60%，遠低於 90% 目標。",
                "- 泰國廠與中國廠的 IQC 檢驗標準存在差異，導致同一料號在不同廠區判定結果不一致。",
                "- 單一供應商依賴度偏高：前三大供應商合計占比 72%，斷鏈風險顯著。",
                "- 品質資料分散於各廠區系統，難以即時比對與追蹤趨勢。",
            ]),
            ("建議方案（Draft）", [
                "1) 導入供應商分級管理（A/B/C/D）：依評分卡結果調整採購配額與稽核頻率。",
                "2) 建立統一品質數據平台：透過 SharePoint + Excel Copilot 產出跨廠區即時儀表板。",
                "3) 推動關鍵料件雙源策略：Q1 內完成 5 項關鍵料件的第二供應商認證。",
                "4) 使用 Copilot Chat 建立品質規範問答 Agent：加速新進人員上手與跨廠區規範對齊。",
                "5) Teams/Outlook 串聯：CAR 發出後自動追蹤進度，逾期自動升級通知。",
            ]),
            ("里程碑（Draft）", [
                "- W1：完成供應商評分卡 Q4 更新與紅色警示標記",
                "- W2：統一《IQC 檢驗規範 v3.0》並發布至各廠區",
                "- W3：啟動鴻碩精密替代源評估與認證",
                "- W4：上線品質規範問答 Agent（試辦）",
                "- W5：品質數據即時儀表板上線（MVP）",
                "- W6：首次跨廠區品質月會（使用新格式）",
                "- W7：關鍵料件雙源認證完成（第一批 3 項）",
                "- W8：Q1 結案報告與 Q2 目標設定",
            ]),
        ]
    )

    # --- Excel: 來料檢驗數據 ---
    suppliers = [
        ("SUP-001", "鴻碩精密"), ("SUP-002", "瑞昱電子"), ("SUP-003", "聯穎光電"),
        ("SUP-004", "台達零組件"), ("SUP-005", "國巨電子"), ("SUP-006", "華新科技"),
        ("SUP-007", "乾坤科技"), ("SUP-008", "禾伸堂"), ("SUP-009", "奇力新電子"),
        ("SUP-010", "大毅科技"), ("SUP-011", "信昌電陶"), ("SUP-012", "立隆電子"),
    ]
    parts = [
        ("PN-CAP-001", "MLCC 電容 0402"), ("PN-CAP-002", "鋁質電解電容 100μF"),
        ("PN-CON-001", "板對板連接器 0.4mm"), ("PN-CON-002", "FPC 連接器 24P"),
        ("PN-IC-001", "電源管理 IC PWM"), ("PN-IC-002", "LED 驅動 IC"),
        ("PN-LED-001", "LED 晶粒 3030"), ("PN-LED-002", "背光 LED 模組"),
        ("PN-RES-001", "厚膜電阻 0603"), ("PN-TRF-001", "變壓器 EE16"),
        ("PN-FET-001", "GaN FET 650V"), ("PN-IND-001", "功率電感 10μH"),
    ]
    defect_types = ["尺寸超差", "外觀瑕疵", "電氣特性異常", "焊接不良", "鍍層剝落",
                     "批次間一致性不足", "標示錯誤", "包裝受損", "異物混入", "材料成分超標"]
    risk_levels = ["High", "Medium", "Low"]

    start_d = datetime(2025, 10, 1)
    end_d = datetime(2025, 12, 31)
    rows = []
    for i in range(1, 201):
        sup = random.choice(suppliers)
        part = random.choice(parts)
        lot_size = random.choice([500, 1000, 2000, 3000, 5000, 10000])
        sample_size = max(20, lot_size // 50)

        # --- Intentional anomalies ---
        if sup[0] == "SUP-001":  # 鴻碩精密: consistently high defect
            defect_count = random.randint(8, 35)
        elif sup[0] == "SUP-002" and "IC" in part[0]:  # 瑞昱 IC: batch inconsistency
            defect_count = random.choice([0, 0, 1, 12, 15, 18])  # bimodal
        elif sup[0] == "SUP-003":  # 聯穎光電: very good
            defect_count = random.randint(0, 1)
        else:
            defect_count = random.randint(0, 6)

        defect_rate = round(defect_count / sample_size * 100, 2)
        if defect_rate > 5:
            risk = "High"
        elif defect_rate > 2:
            risk = "Medium"
        else:
            risk = "Low"

        defect_type = random.choice(defect_types) if defect_count > 0 else "無"
        notes = ""
        if sup[0] == "SUP-001" and defect_rate > 5:
            notes = "已發出 CAR，待供應商回覆"
        elif sup[0] == "SUP-002" and defect_count > 10:
            notes = "批次間變異大，建議收緊規格"

        rows.append((
            f"IQC-2025{i:04d}",
            rand_date(start_d, end_d),
            sup[0], sup[1],
            part[0], part[1],
            lot_size, sample_size, defect_count,
            defect_type, defect_rate, risk, notes
        ))

    kpi_rows = [
        ("來料不良率", "≤ 2.0%", "確保原物料品質，降低產線重工成本"),
        ("CAR 結案天數", "≤ 10 天", "縮短異常處理週期，減少停線風險"),
        ("供應商稽核通過率", "≥ 90%", "確保供應商持續符合品質標準"),
        ("關鍵料件雙源比例", "≥ 80%", "降低單一供應商斷鏈風險"),
        ("高風險案件 SLA 達成率", "≥ 95%", "確保 Critical 等級問題在時限內處理"),
    ]

    headers = ["InspectionID", "Date", "SupplierCode", "SupplierName", "PartNumber",
               "PartName", "LotSize", "SampleSize", "DefectCount", "DefectType",
               "DefectRate_Pct", "RiskLevel", "InspectorNotes"]
    kpi_headers = ["KPI", "Target", "重要性說明"]

    make_excel(
        os.path.join(base, "03_Data", "2025Q4_來料檢驗數據.xlsx"),
        [("InspectionData", headers, rows), ("KPI_Targets", kpi_headers, kpi_rows)]
    )


# ============================================================
# SCENARIO 2: ESG 永續發展與碳盤查
# ============================================================
def gen_scenario2():
    print("\n[場景 2] ESG 永續發展與碳盤查")
    base = os.path.join(BASE, "02_ESG永續發展與碳盤查")

    # --- Doc 1: ESG 政策草案 ---
    make_doc(
        os.path.join(base, "02_Docs", "光寶_ESG永續管理政策草案_v0.9.docx"),
        "光寶科技｜ESG 永續管理與碳排放管理政策（草案 v0.9）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("1. 目的與範圍", [
                "本政策旨在規範光寶科技集團之環境、社會與治理（ESG）管理框架，以及溫室氣體盤查與減排推動流程。",
                "適用範圍：台灣（內湖、新竹）、中國（常州、廣州）、泰國（曼谷）及墨西哥（蒙特雷）所有營運據點。",
                "本政策依據 GRI Standards、TCFD 建議、ISO 14064-1、SBTi 框架制定。",
            ]),
            ("2. 治理架構與角色", [
                "ESG 委員會（Board Level）：每季審查 ESG 策略與風險，由獨立董事擔任主席。",
                "永續發展辦公室：統籌碳盤查、ESG 報告編制、利害關係人溝通。",
                "各廠區 EHS 主管：執行現場環境數據蒐集、能源管理與法規遵循。",
                "供應鏈管理（SCM）：推動供應商 ESG 評鑑與碳揭露要求。",
                "財務與投資人關係：ESG 評級回應、永續金融工具（綠色債券）規劃。",
            ]),
            ("3. 碳盤查方法論", [
                "範疇一（Scope 1）：自有設施直接排放，包括鍋爐、公務車、備用發電機、製程逸散。",
                "範疇二（Scope 2）：外購電力、蒸汽之間接排放，依市場基準法（Market-based）計算。",
                "範疇三（Scope 3）：價值鏈排放，重點類別為「購入商品與服務」、「上游運輸」、「員工通勤」。",
                "數據品質要求：優先使用實測值（Tier 1），次使用供應商提供（Tier 2），最後使用產業係數（Tier 3）。",
                "盤查週期：每年一次完整盤查，每季一次進度追蹤。驗證由第三方認證機構執行。",
            ]),
            ("4. 減排目標與路徑", [
                "短期（2026）：範疇 1+2 排放量較 2020 基準年減少 30%。",
                "中期（2030）：範疇 1+2 減少 50%，範疇 3 減少 25%（SBTi 1.5°C 路徑）。",
                "長期（2050）：全集團碳中和（Net Zero）。",
                "主要減排手段：再生能源採購（PPA/REC）、製程節能改善、物流路線優化、供應商低碳轉型。",
            ]),
            ("5. 風險與合規", [
                "風險：各廠區碳排數據蒐集延遲或品質不一，影響年度報告時程。",
                "風險：歐盟 CBAM（碳邊境調整機制）對出口產品產生成本衝擊。",
                "風險：供應商碳揭露配合度不足，影響範疇三數據完整性。",
                "緩解：建立統一碳數據平台，每月自動匯總各廠數據。",
                "緩解：導入 Copilot Agent 供 ESG 法規快速查詢與合規檢核。",
                "緩解：將供應商碳揭露納入評分卡考核項目。",
            ]),
        ]
    )

    # --- Doc 2: 會議紀錄 ---
    make_doc(
        os.path.join(base, "02_Docs", "會議紀錄_ESG委員會季度檢討_2026-03-15.docx"),
        "會議紀錄｜ESG 委員會 2026 Q1 季度檢討（2026/03/15）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("會議資訊", [
                "日期：2026/03/15（六）10:00–12:00",
                "地點：光寶科技內湖總部 12F 董事會議室",
                "與會：ESG 委員會委員、永續發展辦公室、各廠區 EHS 主管（視訊）、財務長、投資人關係主管",
                "主題：2025 年度 ESG 報告初稿審查與 2026 減排進度追蹤",
            ]),
            ("討論要點", [
                "1) 2025 年度範疇 1+2 碳排總量 45,200 tCO2e，較 2024（48,800）減少 7.4%，但距 2026 目標（42,000）仍有 7.6% 缺口。",
                "2) 常州廠 Q4 碳排異常飆升 40%（從 3,200 → 4,480 tCO2e），主因為備用發電機因限電政策大量啟用。",
                "3) 泰國廠已完成太陽能屋頂安裝，預計 2026 年可貢獻 1,200 MWh 再生能源，減排約 600 tCO2e。",
                "4) 範疇三數據蒐集率僅 62%，主要瓶頸在中小型供應商缺乏碳盤查能力。",
                "5) MSCI ESG 評級維持 A 級，惟 CDP 問卷回覆品質需提升（2025 得分 B，目標 A-）。",
                "6) 歐盟 CBAM 過渡期報告已提交，正式課稅階段預估年增成本約 USD 1.2M，需提早佈局低碳供應鏈。",
            ]),
            ("決策", [
                "- 常州廠限電備援方案：優先評估儲能設備投資，減少對柴油發電機的依賴。",
                "- 範疇三改善：Q1 內舉辦供應商碳揭露說明會，並提供免費碳足跡計算工具。",
                "- ESG 報告編制流程：導入 Word Copilot 加速初稿撰寫與多語言翻譯。",
                "- 每月碳排數據自動化：使用 Excel Copilot 建立跨廠區碳排趨勢儀表板。",
            ]),
            ("擬辦事項", [
                "A1：永續辦公室（李美玲）— 3/25 前完成 2025 ESG 報告初稿第二版。",
                "A2：常州廠 EHS（趙偉國）— 3/31 前提供限電期間碳排增量的詳細分析與對策。",
                "A3：SCM（黃淑芬）— 4/10 前完成前 50 大供應商碳揭露狀態調查。",
                "A4：財務（陳家豪）— 4/15 前完成 CBAM 成本影響評估報告。",
                "A5：你 — 4/7 前完成董事會 ESG 策略簡報（含碳排趨勢、減排路徑、投資建議）。",
            ]),
        ]
    )

    # --- Doc 3: 高層提案初稿 ---
    make_doc(
        os.path.join(base, "02_Docs", "高層提案_ESG年度報告與碳減排策略_初稿.docx"),
        "光寶科技｜2025 年度 ESG 報告暨 2026 碳減排策略提案（初稿）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("執行摘要（Draft）", [
                "本提案彙整 2025 年度 ESG 執行成果，並提出 2026 年度碳減排強化策略。",
                "目標：2026 年範疇 1+2 減至 42,000 tCO2e 以下、範疇三數據蒐集率提升至 85%、CDP 評分提升至 A-。",
            ]),
            ("現況與成果", [
                "- 2025 年範疇 1+2 碳排 45,200 tCO2e，較 2020 基準年減少 18.8%，目標 30% 仍有缺口。",
                "- 再生能源使用率 28%（目標 35%），主因為中國廠區 REC 取得困難。",
                "- 供應商 ESG 評鑑覆蓋率 78%，但碳揭露回覆率僅 62%。",
                "- 常州廠 Q4 碳排異常飆升 40%，暴露備用電力方案的碳排風險。",
            ]),
            ("建議方案（Draft）", [
                "1) 加速再生能源佈局：台灣廠簽訂 PPA、泰國廠擴大太陽能、中國廠評估綠電直購。",
                "2) 常州廠儲能投資方案：評估 2 MWh 鋰離子儲能系統替代柴油發電機。",
                "3) 供應商碳揭露加速計畫：舉辦說明會 + 提供免費碳足跡計算工具 + 納入評分權重。",
                "4) ESG 報告數位化：Word Copilot 加速報告撰寫、Excel Copilot 自動化碳排分析。",
                "5) Copilot Agent 建置：ESG 法規問答 Agent + 碳排數據洞察 Agent，提升跨部門溝通效率。",
            ]),
            ("里程碑（Draft）", [
                "- W1：完成 2025 ESG 報告定稿並送第三方驗證",
                "- W2：常州廠儲能方案可行性分析完成",
                "- W3：供應商碳揭露說明會舉辦",
                "- W4：碳排數據即時儀表板上線",
                "- W5：上線 ESG 法規問答 Agent（試辦）",
                "- W6：PPA/REC 採購談判啟動",
                "- W7：CDP 問卷 2026 回覆策略擬定",
                "- W8：Q1 碳排進度報告與目標校正",
            ]),
        ]
    )

    # --- Excel: 碳排放數據 ---
    factories = [
        ("內湖總部", "台灣"), ("新竹廠", "台灣"), ("常州廠", "中國"),
        ("廣州廠", "中國"), ("曼谷廠", "泰國"), ("蒙特雷廠", "墨西哥"),
    ]
    scopes = ["Scope 1", "Scope 2", "Scope 3"]
    categories_s1 = ["鍋爐燃料", "公務車輛", "備用發電機", "製程逸散", "冷媒逸散"]
    categories_s2 = ["外購電力", "外購蒸汽"]
    categories_s3 = ["購入商品與服務", "上游運輸", "員工通勤", "商務旅行", "廢棄物處理"]
    sources_map = {
        "鍋爐燃料": "天然氣燃燒", "公務車輛": "汽油/柴油", "備用發電機": "柴油發電",
        "製程逸散": "焊接作業", "冷媒逸散": "空調系統", "外購電力": "電力公司",
        "外購蒸汽": "蒸汽供應商", "購入商品與服務": "供應商碳足跡",
        "上游運輸": "貨運物流", "員工通勤": "員工交通", "商務旅行": "航空/鐵路",
        "廢棄物處理": "焚化/掩埋"
    }
    verification_statuses = ["已驗證", "已驗證", "已驗證", "待驗證", "自評"]

    rows = []
    for i in range(1, 201):
        factory, country = random.choice(factories)
        quarter = random.choice(["Q1", "Q2", "Q3", "Q4"])
        scope = random.choices(scopes, weights=[30, 40, 30])[0]

        if scope == "Scope 1":
            category = random.choice(categories_s1)
        elif scope == "Scope 2":
            category = random.choice(categories_s2)
        else:
            category = random.choice(categories_s3)

        source = sources_map[category]

        # Base emission with anomalies
        if scope == "Scope 1":
            base_val = random.uniform(20, 300)
        elif scope == "Scope 2":
            base_val = random.uniform(150, 800)
        else:
            base_val = random.uniform(50, 500)

        # --- Intentional anomalies ---
        if factory == "常州廠" and quarter == "Q4" and category == "備用發電機":
            base_val = random.uniform(800, 1200)  # Abnormal spike
        if factory == "常州廠" and quarter == "Q4" and scope == "Scope 2":
            base_val *= 1.4  # Power restriction → more purchased power
        if factory == "曼谷廠" and scope == "Scope 2" and quarter in ["Q3", "Q4"]:
            base_val *= 0.7  # Solar panels installed

        co2e = round(base_val, 2)
        verification = random.choice(verification_statuses)

        rows.append((
            f"EM-2025{i:04d}", 2025, quarter, factory, country,
            scope, category, source, co2e, "tCO2e",
            "實測值" if verification == "已驗證" else "估算值",
            verification
        ))

    kpi_rows = [
        ("範疇 1+2 年度碳排", "≤ 42,000 tCO2e", "2026 年度減碳目標（較 2020 基準年 -30%）"),
        ("再生能源使用率", "≥ 35%", "降低範疇二排放，提升能源轉型進度"),
        ("範疇三數據蒐集率", "≥ 85%", "強化價值鏈碳揭露完整度"),
        ("CDP 評分", "A-", "提升國際 ESG 評級與投資人信心"),
        ("供應商碳揭露回覆率", "≥ 80%", "確保供應鏈碳數據透明度"),
    ]

    headers = ["RecordID", "Year", "Quarter", "Factory", "Country", "Scope",
               "Category", "EmissionSource", "CO2e_Tonnes", "Unit", "DataSource", "VerificationStatus"]
    kpi_headers = ["KPI", "Target", "重要性說明"]

    make_excel(
        os.path.join(base, "03_Data", "2025_各廠區碳排放數據.xlsx"),
        [("EmissionData", headers, rows), ("KPI_Targets", kpi_headers, kpi_rows)]
    )


# ============================================================
# SCENARIO 3: 新產品開發與市場策略
# ============================================================
def gen_scenario3():
    print("\n[場景 3] 新產品開發與市場策略")
    base = os.path.join(BASE, "03_新產品開發與市場策略")

    # --- Doc 1: 新產品流程規範 ---
    make_doc(
        os.path.join(base, "02_Docs", "光寶_新產品開發流程規範_v1.0.docx"),
        "光寶科技｜新產品開發流程規範（v1.0）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("1. 目的與範圍", [
                "本規範用於定義光寶科技新產品開發（NPD）之 Phase-Gate 流程，確保從概念到量產的每個階段都有明確的審查標準與決策機制。",
                "適用範圍：電源供應器（PSU）、LED 照明、光儲存模組、影像感測模組及新興事業（車用/醫療）之所有新產品專案。",
            ]),
            ("2. Phase-Gate 流程概述", [
                "Phase 0 — 概念與市場評估：市場機會分析、技術可行性初評、投資報酬率（ROI）概估。",
                "Phase 1 — 規格定義與設計：客戶規格確認（Spec-in）、初步設計與模擬、關鍵料件選型。",
                "Phase 2 — 原型驗證（EVT/DVT）：工程驗證測試、設計驗證測試、安規認證送測。",
                "Phase 3 — 試產驗證（PVT）：產線試跑、製程穩定性驗證、量產準備度評估。",
                "Phase 4 — 量產與上市：正式量產、客戶出貨、售後支援體系建立。",
                "每個 Phase 結束前需通過 Gate Review（跨部門審查），由 NPD 委員會決議是否進入下一階段。",
            ]),
            ("3. Gate Review 審查要點", [
                "技術面：規格達成率、測試通過率、專利佈局狀況。",
                "市場面：目標客戶進度、競品動態、定價策略可行性。",
                "財務面：開發費用實際 vs 預算、量產成本概估、BEP（損益兩平）分析。",
                "品質面：DFM（可製造性設計）檢核、FMEA 分析完成度。",
                "時程面：里程碑達成率、風險項目與備案。",
            ]),
            ("4. 跨部門協作機制", [
                "專案經理（PM）負責統籌進度、成本與跨部門溝通。",
                "RD 與 ME 於 Phase 1 即需同步進行 DFM/DFA（可製造/可組裝）評估。",
                "業務/市場需於 Phase 0 提供客戶需求文件（RFQ/RFP），並持續更新市場情報。",
                "採購需於 Phase 1 完成關鍵料件供應商確認與報價。",
                "使用 Teams 作為專案協作平台，搭配 Copilot 進行會議回顧與擬辦事項追蹤。",
            ]),
            ("5. 風險管理", [
                "風險：客戶規格頻繁變更導致設計反覆，時程延誤。",
                "風險：關鍵料件（如 GaN 元件）交期不穩定，全球缺料風險。",
                "風險：新技術（GaN/SiC）良率尚未穩定，量產成本高於預期。",
                "緩解：建立規格變更管理流程（ECR/ECN），設定凍結時間點。",
                "緩解：關鍵料件採雙源策略，並建立安全庫存。",
                "緩解：提前進行量產爬坡計畫，預留良率學習曲線。",
            ]),
        ]
    )

    # --- Doc 2: 會議紀錄 ---
    make_doc(
        os.path.join(base, "02_Docs", "會議紀錄_AI伺服器電源產品審查_2026-03-18.docx"),
        "會議紀錄｜AI 伺服器電源供應器 Gate 1 Review（2026/03/18）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("會議資訊", [
                "日期：2026/03/18（三）09:00–11:00",
                "地點：光寶科技新竹研發中心 3F NPD 會議室",
                "與會：NPD 委員會、電源 RD、技術行銷、業務、採購、品質、ME",
                "主題：2000W AI 伺服器電源供應器（GaN 技術）Phase 0 → Phase 1 Gate Review",
            ]),
            ("討論要點", [
                "1) 2026 全球 AI 伺服器電源市場預估 USD 8.5B，年成長率 28%，光寶目標搶佔 5% 市佔（≈ USD 425M）。",
                "2) 目前主要競爭者 Delta（台達）已發表 3000W GaN PSU，Murata 與 Vicor 也有 2000W 級產品佈局。",
                "3) RD 報告 GaN FET 650V 元件效率達 97.5%（目標 98%），尚需優化散熱設計與 EMI 對策。",
                "4) 業務回饋：某美系雲端大廠（Tier-1 客戶）已發出 RFQ，要求 2026 Q4 送樣，2027 Q1 開始量產出貨。",
                "5) 採購評估：GaN FET 目前僅 2 家合格供應商（GaN Systems、英飛凌），報價較 Si MOSFET 高 3.5 倍。",
                "6) 定價初估：目標售價 USD 280–320/台（競品 Delta: USD 350, Murata: USD 310）。",
            ]),
            ("決策", [
                "- 同意進入 Phase 1（規格定義與設計），開發代碼：PSU-GaN-2K。",
                "- RD 需於 4/15 前完成散熱與 EMI 改善方案，效率目標上修至 98%。",
                "- 業務與技術行銷 4 月初提交完整市場攻擊策略與目標客戶優先順序。",
                "- 採購立即啟動第三供應商（Navitas）評估，降低 GaN 料件成本風險。",
                "- 使用 Copilot 加速市場競爭分析報告與客戶提案文件產出。",
            ]),
            ("擬辦事項", [
                "A1：RD 主管（吳建宏）— 4/15 前完成散熱方案初步設計與 EMI 模擬。",
                "A2：技術行銷（鄭雅馨）— 4/10 前更新競爭分析報告與定價策略建議。",
                "A3：業務（劉俊偉）— 4/10 前確認 Tier-1 客戶 RFQ 規格與時程。",
                "A4：採購（蔡宜庭）— 4/20 前完成 Navitas GaN FET 初步評估與報價。",
                "A5：你 — 4/12 前完成高層上市計畫簡報（含市場分析、技術亮點、競爭定位），並準備客戶提案版本。",
            ]),
        ]
    )

    # --- Doc 3: 高層提案初稿 ---
    make_doc(
        os.path.join(base, "02_Docs", "高層提案_GaN電源供應器上市計畫_初稿.docx"),
        "光寶科技｜2000W AI 伺服器 GaN 電源供應器上市計畫（初稿）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("執行摘要（Draft）", [
                "本提案為光寶科技 2000W AI 伺服器電源供應器（採用 GaN 技術）之上市計畫。",
                "目標：2026 Q4 送樣、2027 Q1 量產，首年營收目標 USD 85M，搶佔 AI 伺服器電源 2% 市佔。",
            ]),
            ("市場機會與競爭分析", [
                "- 2026 全球 AI 伺服器電源市場 USD 8.5B，受惠於大型語言模型（LLM）訓練需求爆發。",
                "- 主要競爭者：台達（3000W, GaN, USD 350）、Murata（2000W, SiC, USD 310）、Vicor（FPA, USD 340）。",
                "- 光寶優勢：已具備 GaN 驅動技術、與客戶長期合作關係、成本控制能力。",
                "- 光寶劣勢：GaN 電源產品尚無量產實績，品牌在 AI 伺服器領域知名度待建立。",
                "- 客戶痛點：能源效率（PUE）是資料中心最大成本，高效率電源可直接降低 TCO。",
            ]),
            ("技術亮點與產品規格（Draft）", [
                "1) GaN FET 650V 開關元件，較傳統 Si MOSFET 效率提升 2–3%，體積縮小 40%。",
                "2) 目標效率 ≥ 98%（80 Plus Titanium 認證），功率密度 ≥ 100W/in³。",
                "3) 支援 48V DC 或 AC-DC 雙模式輸入，相容下一代機架架構。",
                "4) 數位控制（PMBus 2.0）：可遠端監控效率、溫度、負載，支援預測性維護。",
                "5) 散熱設計挑戰：GaN 高頻切換產生集中熱點，需優化散熱片與風道設計。",
            ]),
            ("上市時程與里程碑（Draft）", [
                "- M1（2026/04）：Phase 1 規格凍結、關鍵料件選型確認",
                "- M2（2026/06）：EVT 原型完成、效率/安規預測試",
                "- M3（2026/08）：DVT 完成、安規認證送測（UL/IEC/CCC）",
                "- M4（2026/10）：Tier-1 客戶送樣、設計評審",
                "- M5（2026/12）：PVT 試產啟動",
                "- M6（2027/02）：量產爬坡、首批出貨",
                "- M7（2027/04）：CES/OCP 展會行銷推廣",
                "- M8（2027/06）：首年目標 50K 台出貨達成檢核",
            ]),
        ]
    )

    # --- Excel: 市場競爭分析 ---
    competitors = [
        ("台達電子", ["DPS-3000GB", "DPS-2000GB", "DPS-1600GB"]),
        ("Murata", ["D1U86P-W-2000", "D1U54P-W-1600"]),
        ("Vicor", ["FPA-2000", "FPA-1600", "DCM-3623"]),
        ("力博特", ["LP-2000-GaN", "LP-1600-Si"]),
        ("康舒科技", ["CSP-2000A", "CSP-1600A", "CSP-1200A"]),
        ("全漢企業", ["FSP-2000G", "FSP-1600G"]),
        ("群光電能", ["GPS-2000", "GPS-1600"]),
        ("明緯企業", ["RSP-2000", "RSP-1600", "RSP-1200"]),
    ]
    technologies = ["GaN", "SiC", "Si MOSFET", "GaN+SiC Hybrid"]
    segments = ["AI 伺服器", "通用伺服器", "邊緣運算", "電信設備", "資料中心基礎設施"]
    regions = ["北美", "歐洲", "亞太", "中國", "全球"]
    certifications = ["80+ Titanium", "80+ Platinum", "80+ Gold", "80+ Bronze"]

    rows = []
    comp_id = 1
    for company, models in competitors:
        for model in models:
            wattage = int(model.split("-")[-1].replace("GB", "").replace("Si", "").replace("GaN", "").replace("A", "").replace("G", "").replace("W-", "")) if any(c.isdigit() for c in model.split("-")[-1]) else random.choice([1200, 1600, 2000])
            try:
                wattage = int(''.join(filter(str.isdigit, model.split("-")[-1])))
                if wattage < 100:
                    wattage *= 100
            except:
                wattage = random.choice([1200, 1600, 2000])

            tech = random.choice(technologies)
            if "GaN" in model:
                tech = "GaN"
            elif "Si" in model:
                tech = "Si MOSFET"

            efficiency = round(random.uniform(93.0, 98.5), 1)
            if tech == "GaN":
                efficiency = round(random.uniform(96.5, 98.5), 1)

            price = round(random.uniform(180, 400), 0)
            # Delta is premium
            if company == "台達電子":
                price = round(random.uniform(300, 400), 0)
            # Anomaly: one competitor with suspiciously low price
            if company == "力博特" and "GaN" in model:
                price = 165.0  # Abnormally low for GaN

            market_share = round(random.uniform(0.5, 18.0), 1)
            if company == "台達電子":
                market_share = round(random.uniform(15.0, 22.0), 1)

            cert = random.choice(certifications)
            if efficiency >= 96:
                cert = "80+ Titanium"
            elif efficiency >= 94:
                cert = "80+ Platinum"

            segment = random.choice(segments)
            launch = rand_date(datetime(2024, 1, 1), datetime(2026, 6, 30))
            region = random.choice(regions)

            rows.append((
                f"COMP-{comp_id:03d}", company, model, wattage, tech,
                efficiency, price, market_share, cert, segment, launch, region
            ))
            comp_id += 1

    # Add Lite-On's own planned product for comparison
    rows.append(("COMP-100", "光寶科技（規劃中）", "PSU-GaN-2K", 2000, "GaN",
                 98.0, 295.0, 0.0, "80+ Titanium", "AI 伺服器", "2027-02-01", "全球"))

    kpi_rows = [
        ("首年營收", "≥ USD 85M", "確認市場接受度與營收成長動能"),
        ("首年出貨量", "≥ 50,000 台", "驗證量產能力與供應鏈準備度"),
        ("產品效率", "≥ 98%", "達到 80+ Titanium 認證標準"),
        ("量產良率", "≥ 95%", "確保量產成本可控"),
        ("客戶設計導入（Design Win）", "≥ 3 家 Tier-1 客戶", "建立 AI 伺服器領域市場信譽"),
    ]

    headers = ["CompetitorID", "CompanyName", "ProductModel", "Wattage_W", "Technology",
               "Efficiency_Pct", "Price_USD", "MarketShare_Pct", "Certification",
               "TargetSegment", "LaunchDate", "Region"]
    kpi_headers = ["KPI", "Target", "重要性說明"]

    make_excel(
        os.path.join(base, "03_Data", "2026_AI伺服器電源市場競爭分析.xlsx"),
        [("CompetitorData", headers, rows), ("KPI_Targets", kpi_headers, kpi_rows)]
    )


# ============================================================
# SCENARIO 4: 全球營運管理
# ============================================================
def gen_scenario4():
    print("\n[場景 4] 全球營運管理")
    base = os.path.join(BASE, "04_全球營運管理")

    # --- Doc 1: 營運政策 ---
    make_doc(
        os.path.join(base, "02_Docs", "光寶_全球營運管理政策與SOP_v1.0.docx"),
        "光寶科技｜全球營運管理政策與標準作業程序（v1.0）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("1. 目的與範圍", [
                "本政策用於規範光寶科技全球各營運據點之生產管理、效率衡量與持續改善機制。",
                "適用範圍：台灣（內湖/新竹）、中國（常州/廣州）、泰國（曼谷）、墨西哥（蒙特雷）所有製造廠區。",
            ]),
            ("2. 關鍵績效指標（KPI）定義", [
                "OEE（Overall Equipment Effectiveness）= 稼動率 × 性能效率 × 良率，目標 ≥ 85%。",
                "良率（Yield Rate）：最終產品良率，目標依產品線設定（電源 ≥ 98%、LED ≥ 99%）。",
                "交期達成率（On-Time Delivery, OTD）：以客戶要求日為基準，目標 ≥ 95%。",
                "人均產出（Output per Capita）：每工時產出台數/模組數，作為跨廠比較基準。",
                "產能利用率（Utilization Rate）：實際產量 / 設計產能，目標 ≥ 80%。",
                "單位製造成本（Unit Manufacturing Cost）：含直接材料、直接人工與製造費用，每季檢討降本目標。",
            ]),
            ("3. 跨廠區標準化作業", [
                "所有廠區使用統一的 MES（製造執行系統）與 ERP（SAP S/4HANA）。",
                "生產排程由中央 PMC（生產管制中心）統一規劃，各廠區執行。",
                "品質標準依 ISO 9001 / IATF 16949（車用線）統一規範，各廠區 IQC/IPQC/FQC 流程一致。",
                "每月第一週舉行跨區域營運月會，由各廠區主管輪流報告 KPI 與改善進度。",
            ]),
            ("4. 成本優化策略", [
                "推動生產線自動化與智慧製造（AOI、自動插件機、協作機器人），降低人工依賴。",
                "人力部署彈性化：淡季跨線/跨廠區調配，旺季引入彈性人力。",
                "能源管理：各廠區設置能源管理系統（EMS），追蹤用電/用水/用氣數據。",
                "物流優化：依訂單區域就近生產出貨，縮短交期並降低運輸成本。",
            ]),
            ("5. 風險與緩解", [
                "風險：各廠區 KPI 定義與計算方式存在微差，導致跨廠比較失真。",
                "風險：特定廠區人力流動率高（> 15%/年），影響產線穩定性與品質。",
                "風險：單一廠區承接過高比例訂單，地緣政治與天災風險集中。",
                "緩解：統一 KPI 計算引擎（ERP 報表模組），並搭配 Excel Copilot 自動校驗。",
                "緩解：建立營運數據 Agent，提供跨廠區即時 KPI 比較與異常預警。",
                "緩解：訂單分配納入風險權重，避免單一廠區占比超過 40%。",
            ]),
        ]
    )

    # --- Doc 2: 會議紀錄 ---
    make_doc(
        os.path.join(base, "02_Docs", "會議紀錄_跨區域營運月會_2026-03-10.docx"),
        "會議紀錄｜全球跨區域營運月會（2026/03/10）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("會議資訊", [
                "日期：2026/03/10（二）09:00–11:00（各時區同步視訊）",
                "與會：全球營運長（COO）、各廠區廠長、PMC、HR、財務",
                "主題：2025 Q4 營運績效回顧與 2026 Q1 目標設定",
            ]),
            ("討論要點", [
                "1) 2025 Q4 整體 OEE 為 81.3%，較 Q3（83.5%）下降 2.2 個百分點，主因為蒙特雷廠新線調機影響。",
                "2) 蒙特雷廠 OEE 僅 52%（全集團最低），原因：新引入的車用電源產線良率僅 88%，停機調整頻繁。",
                "3) 常州廠 OEE 表現最佳（91%），生產效率持續領先，但人均產出較 Q3 下降 5%（因新進員工培訓期）。",
                "4) 泰國曼谷廠交期達成率降至 89%（目標 95%），主因為海運延誤與倉儲管理瓶頸。",
                "5) 新竹廠已完成 SMT 線自動化升級，Q1 預期人均產出提升 20%。",
                "6) 全球人力成本較去年同期增加 8.5%，其中蒙特雷廠增幅最高（+15%），需檢討人力配置策略。",
            ]),
            ("決策", [
                "- 蒙特雷廠車用線指派台灣資深 ME 支援調機，目標 Q1 良率提升至 95%。",
                "- 泰國廠物流改善：評估改為空運高優先訂單 + 優化倉儲揀貨流程。",
                "- 全球 KPI 儀表板 2.0：導入 Excel Copilot Edit with Copilot 模式，自動整理各廠資料並產出趨勢圖。",
                "- 成本優化專案：Q1 各廠需提出至少 3 項降本方案，總目標降低 2% 單位製造成本。",
            ]),
            ("擬辦事項", [
                "A1：蒙特雷廠長（Carlos G.）— 3/20 前提出車用線良率改善計畫與支援需求。",
                "A2：泰國廠長（Somchai P.）— 3/25 前完成物流瓶頸分析與改善方案。",
                "A3：PMC（楊志強）— 3/31 前完成 Q1 訂單分配方案（含風險權重調整）。",
                "A4：HR（孫曉雯）— 3/31 前提出全球人力成本優化方案（含自動化投資 ROI 評估）。",
                "A5：你 — 4/5 前完成全球營運效率提升報告與高層簡報（含各廠 KPI 比較、成本優化方案、投資建議）。",
            ]),
        ]
    )

    # --- Doc 3: 高層提案初稿 ---
    make_doc(
        os.path.join(base, "02_Docs", "高層提案_全球營運效率提升方案_初稿.docx"),
        "光寶科技｜2026 Q1 全球營運效率提升與成本優化提案（初稿）",
        "（本文件為課程 Demo 用虛構內容，可自由修改。）",
        [
            ("執行摘要（Draft）", [
                "本提案針對光寶科技全球 6 個製造據點之 2025 Q4 營運績效進行分析，並提出 2026 年效率提升與成本優化策略。",
                "目標：全球 OEE 提升至 85%、交期達成率 ≥ 95%、單位製造成本降低 2%。",
            ]),
            ("現況與問題", [
                "- 整體 OEE 81.3%，低於 85% 目標。蒙特雷廠新車用線拖累整體表現（OEE 52%）。",
                "- 泰國廠交期問題影響重要客戶的滿意度，已收到 2 封正式客訴信。",
                "- 人力成本年增 8.5%，蒙特雷廠增幅 15% 最為嚴峻。",
                "- 各廠區 KPI 報告格式不一，每月整理花費過多人工時間。",
                "- 常州廠雖效率領先，但新進人員培訓期影響 Q4 人均產出表現。",
            ]),
            ("建議方案（Draft）", [
                "1) 蒙特雷廠車用線強化：派遣台灣 ME 支援 + 導入 SPC（統計製程管制）即時監控。",
                "2) 泰國廠物流再造：高優先訂單空運 + WMS（倉儲管理系統）升級 + 物流追蹤整合。",
                "3) 全球 KPI 自動化：Excel Copilot 建立統一格式儀表板，自動計算各廠 OEE/良率/OTD。",
                "4) 成本優化：新竹 SMT 自動化經驗複製至其他廠區，優先投資 ROI > 18 個月回收之專案。",
                "5) Copilot 營運助理 Agent：串聯 SharePoint 營運數據，提供即時 KPI 問答與異常預警。",
            ]),
            ("里程碑（Draft）", [
                "- W1：完成各廠 Q4 KPI 深度分析報告",
                "- W2：蒙特雷廠 ME 支援到位，調機計畫啟動",
                "- W3：泰國廠物流改善方案確認並開始執行",
                "- W4：全球 KPI 儀表板 2.0 上線（Excel Copilot + Edit with Copilot）",
                "- W5：各廠 Q1 降本方案提交與審查",
                "- W6：上線營運數據 Agent（試辦）",
                "- W7：新竹 SMT 自動化經驗分享會（跨廠區）",
                "- W8：Q1 結案報告與 Q2 目標設定",
            ]),
        ]
    )

    # --- Excel: 跨廠區 KPI 資料 ---
    factories = [
        ("內湖總部", "台灣", "亞太"), ("新竹廠", "台灣", "亞太"),
        ("常州廠", "中國", "亞太"), ("廣州廠", "中國", "亞太"),
        ("曼谷廠", "泰國", "亞太"), ("蒙特雷廠", "墨西哥", "美洲"),
    ]
    product_lines = ["電源供應器", "LED 模組", "光儲存", "影像感測", "車用電子"]
    months = ["2025-10", "2025-11", "2025-12"]

    rows = []
    rec_id = 1
    for month in months:
        for factory, country, region in factories:
            for pl in random.sample(product_lines, k=random.randint(2, 4)):
                # Base values
                oee = round(random.uniform(78, 92), 1)
                yield_rate = round(random.uniform(95, 99.5), 1)
                otd = round(random.uniform(88, 99), 1)
                output_per_cap = round(random.uniform(15, 45), 1)
                labor_cost = round(random.uniform(8000, 25000), 0)
                util_rate = round(random.uniform(70, 95), 1)

                # --- Intentional anomalies ---
                if factory == "蒙特雷廠" and pl == "車用電子":
                    oee = round(random.uniform(48, 58), 1)  # Very low OEE
                    yield_rate = round(random.uniform(85, 90), 1)  # Low yield
                    labor_cost = round(random.uniform(22000, 30000), 0)  # High cost
                if factory == "常州廠":
                    oee = round(random.uniform(88, 93), 1)  # Best OEE
                    output_per_cap = round(random.uniform(38, 48), 1)
                    if month == "2025-12":
                        output_per_cap *= 0.95  # Slight dip due to new hires
                if factory == "曼谷廠":
                    otd = round(random.uniform(82, 92), 1)  # Low OTD
                if factory == "蒙特雷廠":
                    labor_cost = round(labor_cost * 1.15, 0)  # 15% higher

                risk_flag = "是" if (oee < 75 or yield_rate < 92 or otd < 90) else "否"
                rows.append((
                    f"KPI-{rec_id:04d}", month, factory, country, region, pl,
                    oee, yield_rate, otd, output_per_cap, labor_cost, util_rate, risk_flag
                ))
                rec_id += 1

    kpi_rows = [
        ("全球平均 OEE", "≥ 85%", "衡量設備綜合效率，為產能規劃基準"),
        ("產品良率", "≥ 98%（電源）/ ≥ 99%（LED）", "確保品質水準，降低重工與客訴"),
        ("交期達成率 (OTD)", "≥ 95%", "維護客戶信賴度與訂單取得能力"),
        ("單位製造成本降幅", "≥ -2% YoY", "持續推動成本競爭力"),
        ("產能利用率", "≥ 80%", "避免產能閒置造成固定成本攤提過高"),
    ]

    headers = ["RecordID", "Month", "Factory", "Country", "Region", "ProductLine",
               "OEE_Pct", "YieldRate_Pct", "OnTimeDelivery_Pct", "OutputPerCapita",
               "LaborCost_USD", "UtilizationRate_Pct", "RiskFlag"]
    kpi_headers = ["KPI", "Target", "重要性說明"]

    make_excel(
        os.path.join(base, "03_Data", "2025Q4_跨廠區KPI資料.xlsx"),
        [("FactoryKPI", headers, rows), ("KPI_Targets", kpi_headers, kpi_rows)]
    )


# ============================================================
# Main
# ============================================================
if __name__ == "__main__":
    print("=" * 60)
    print("光寶科技 MS-4018 Demo 範例檔案產生器")
    print("=" * 60)
    gen_scenario1()
    gen_scenario2()
    gen_scenario3()
    gen_scenario4()
    print("\n" + "=" * 60)
    print("全部完成！共產生 16 個檔案（4 場景 × 4 檔案）")
    print("=" * 60)
