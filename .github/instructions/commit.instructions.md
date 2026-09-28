---
applyTo: "**"
---

# Commit Message 指引

## Conventional Commit 標準

遵循 [Conventional Commits](https://www.conventionalcommits.org/) 規範：

```
<type>(<scope>): <description>

[body]
```

### Type（必填，優先從清單選擇，可自行補充）

以下為**優先使用**的標準 Type 清單：

- `feat`: 新功能  
- `fix`: 修復 bug  
- `refactor`: 重構（不影響功能）  
- `docs`: 文件變更  
- `style`: 格式調整（不影響程式邏輯）  
- `test`: 測試相關  
- `chore`: 建置、工具、依賴更新  

**AI 應優先從上述清單中選擇 Type。  
若此次變更不屬於任何既有類型，AI 可以自行補充新的 Type，但必須保持語意清楚、簡潔、合理，並符合 Conventional Commits 精神。**

---

### Scope（必填，優先從清單選擇，可自行補充）

Scope 用於描述此次變更影響的模組或領域。

以下為**優先使用**的常見 Scope 清單：

- `api`
- `ui`
- `ci`
- `db`
- `auth`
- `invoice`
- `nlp`
- `billing`
- `parser`
- `config`

**AI 應優先從上述清單中選擇 Scope。  
若此次變更不屬於任何既有範圍，AI 可以自行補充新的 Scope。  

## 撰寫原則

- 描述「做了什麼」而不是「改了哪些檔案」
- description 必須簡潔、動詞開頭
- body 必須存在，說明動機、內容與影響
- 使用英文撰寫
- 避免模糊字詞（如「更新」、「調整」、「優化」），除非後面有具體描述
- 若新增 Type 或 Scope，需保持語意一致、可理解、可維護
- 若有多次修改，應為總結性的 commit message，而非每次修改都產生新的 commit message

### Type 判斷：參考 Git 歷史

產生 commit message 時，**必須先檢查 git diff 或已提交的歷史**，判斷此次變更的性質：

- 若相關功能**已在先前的 commit 中以 `feat` 提交**，後續對同一功能的修正應使用 `fix`，而非再次使用 `feat`
- 若所有變更（含新功能與修正）**尚未 commit、將一次性提交**，則以主要變更的性質決定 type（通常是 `feat`）
- 簡言之：**新功能用 `feat`，對已提交功能的修正用 `fix`**

## 範例

```
feat(ci): 新增 staging 自動部署流程

- 新增 GitHub Actions workflow
- 加入 Docker build 與推送流程
```

```
fix(invoice): 修正電子發票號碼格式化錯誤

台灣電子發票號碼現在會正確顯示為 XX-XXXXXXXX 格式
```

```
refactor(api): 重構發票解析模組

- 拆分 parser 與 validator
- 移除重複邏輯
```

```
perf(parser): 提升發票 OCR 後處理效能

- 新增快取策略
- 減少重複字串比對
```