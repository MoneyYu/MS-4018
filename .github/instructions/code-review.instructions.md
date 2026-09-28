---
applyTo: "**"
---
# Code Review 指引

## 核心原則

⚠️ **非必要不修改** — 可以為了更好而修改，但不要吹毛求疵  
⚠️ **不要為了測試而測試** — 測試應該驗證業務邏輯，而非追求覆蓋率數字

## 審查重點
審查程式碼時，依序檢查以下面向：

1. **功能正確性** — 是否符合需求？邏輯是否正確？
2. **型別安全** — 避免 `any`，使用 interface，明確回傳型別
3. **錯誤處理** — API 回應是否遵循 `{ success, data/error }` 格式？
4. **一致性** — 是否遵循專案現有慣例？

## 專案特定檢查項目

### TypeScript
- 使用 interface 優先於 type alias
- 避免 `any`，用 `unknown` 取代
- API 函數需明確回傳型別

### Vue 元件
- 使用 `<script setup>` + Composition API
- Props 使用 `defineProps<T>()` 搭配 interface
- Composables 使用 `use*` 命名

### Backend (Hono)
- 統一錯誤格式: `{ success: false, error: { code, message } }`
- 受保護路由使用 `authMiddleware`
- 透過 `c.env.*` 存取 bindings

## 審查回饋格式
```
[類型] 檔案:行數 - 說明

類型：
- 🔴 必須修正 (blocking)
- 🟡 建議改進 (suggestion)
- 🟢 可選優化 (nitpick)
```
