---
applyTo: "**/*.{test,spec}.ts"
---
# 測試指引

## 測試哲學
**優先級: 業務邏輯 > 錯誤處理 > 邊緣案例 > 無障礙**

⚠️ **不要為了測試而測試** — 測試應該驗證業務邏輯，而非追求覆蓋率數字

## 測試範圍
✅ **測試**: 
- Utils (如 [invoice.test.ts](src/shared/src/__tests__/invoice.test.ts))
- Composables
- API routes

❌ **不測試**: 
- ARIA 屬性
- CSS
- Vue Router 行為
- Cloudflare Workers runtime

## 目標覆蓋率
- 業務邏輯: 80%+
- UI 元件: 50-60%
- 工具函數: 90%+

## 測試檔案命名
- 單元測試: `*.test.ts`
- 測試資料夾: `__tests__/`
