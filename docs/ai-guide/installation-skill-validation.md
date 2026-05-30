# Autodesk Dynamo MCP 安裝 Skill 驗證手冊

本文件用來回答兩個問題：

1. 安裝 Skill 是否有效。
2. Skill 有效後，是否等於跨版本支援已完成。

---

## A. 驗證目標

### A1. Skill 有效的定義

同時滿足以下三項才算有效：

1. 可觸發：安裝任務能被正確導向到安裝 Skill。
2. 可完成：依 Skill 流程可完成部署與最小驗證。
3. 可重複：不同版本情境可重現成功結果。

### A2. 跨版本支援完成的定義

「Skill 有效」不等於「跨版本支援永久完成」。

跨版本支援完成，至少需滿足：

1. Revit 2020-2027 的核心冒煙持續可重現。
2. 關鍵版本（至少 2024、2027）進階冒煙可重現。
3. 每次核心變更（C# / deploy.ps1 / 版本映射）後有回歸機制。

---

## B. 測試方式（建議一次跑完）

## B1. 路由測試（可觸發）

用以下提示詞測 5 次，確認都導向：

- `.skills/autodesk-dynamo-mcp-installation/SKILL.md`

測試提示詞範例：

1. 安裝 Autodesk Dynamo MCP 到 Revit 2027。
2. 幫我依本機已安裝版本部署 Autodesk Dynamo MCP。
3. 我要做多版本 Revit 的 Autodesk Dynamo MCP 安裝。
4. 先做偵測安裝模式。
5. 只部署 Dynamo 4.0。

判定：5/5 正確路由為 PASS。

## B2. 功能測試（可完成）

至少執行兩種情境：

1. 偵測安裝模式：`./deploy.ps1`
2. 指定版本模式：`./deploy.ps1 -TargetDynamoVersions 4.0`

每種情境都做以下驗收：

1. Revit + Dynamo 開啟後，`BIM Assistant -> Connect to MCP Server`。
2. `get_server_stats.active_sessions > 0`
3. `analyze_workspace`
4. `execute_dynamo_instructions`（建立 1 個 Code Block）
5. 再 `analyze_workspace`，確認 `nodeCount` 增加。

判定：兩種情境皆通過為 PASS。

## B3. 重複測試（可重複）

從不同版本中至少抽 3 個版本重跑 B2（建議 2023 / 2024 / 2027）。

判定：

1. 成功率 >= 95%
2. 無新增未分類錯誤

---

## C. 驗證記錄模板

每次測試記錄以下欄位：

1. 日期
2. 模式（偵測 / 指定）
3. Revit 版本
4. Dynamo 版本鍵
5. active_sessions
6. 第一次 analyze nodeCount
7. execute 結果（status）
8. 第二次 analyze nodeCount
9. 結論（PASS / FAIL）
10. 備註（例如 2027 需檢查 AppData 27.0）

---

## D. 最終判定規則

### D1. Skill 是否有效

符合 A1 三項且 B1-B3 通過，即可判定「安裝 Skill 有效」。

### D2. 是否完成跨版本支援

若僅「Skill 有效」，只能判定：

- 已建立可用的跨版本安裝與驗證流程。

要判定「跨版本支援完成」，還需要：

1. 全版本驗證結果最新且可重現。
2. 進階冒煙（尤其 2025-2027 的 Python 鏈路）補齊。
3. 後續變更有固定回歸節點（至少基準版 + 最新版）。

---

## E. 建議執行節奏

1. 先跑 B1-B2，確認 Skill 已可用。
2. 再跑 B3，確認跨版本重複性。
3. 若要對外宣告支援完成，再補進階冒煙與回歸節奏證據。
