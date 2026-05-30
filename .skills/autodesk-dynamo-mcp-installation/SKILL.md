---
name: autodesk-dynamo-mcp-installation
description: 專門處理 Autodesk Dynamo MCP 在多版本 Revit 的安裝、部署與最小驗證。當使用者要求「安裝 Autodesk Dynamo MCP」、「跨版本部署」、「依本機偵測版本安裝」、「建立快速安裝流程」時使用。
---

# Autodesk Dynamo MCP Installation Skill

將「安裝 Autodesk Dynamo MCP 到多版本 Revit」流程標準化，支援兩種情境：

1. 偵測安裝模式（預設）：只部署本機已安裝版本。
2. 全矩陣模式（維護者）：逐版驗證 2020-2027。

## 何時使用

符合任一條件就啟用本 Skill：

1. 使用者要把 Autodesk Dynamo MCP 安裝到某個或多個 Revit 版本。
2. 使用者不確定自己的 Revit/Dynamo 版本對應。
3. 需要最低 token 成本的安裝與驗證流程。
4. 要輸出可重複執行的安裝 SOP。

## 輸入最小集合

先收斂到最少必要資訊：

1. 目標模式：偵測安裝 / 全矩陣。
2. 目標版本：
   - 偵測安裝：可省略，直接用 `./deploy.ps1`。
   - 指定版本：例如 `4.0`（Revit 2027）。
3. 當前狀態：Revit/Dynamo 是否已開啟。

## 標準步驟

### Step 1: 環境前置檢查

1. 確認 PowerShell 可執行。
2. 確認 SDK：
   - Revit 2020-2026：.NET 8 SDK。
   - Revit 2027：.NET 10 SDK（可與 .NET 8 並存）。
3. 若要重部署 DLL，先關閉 Revit / Dynamo，避免檔案鎖定。

### Step 2: 執行部署

```powershell
# 偵測安裝模式（預設）
./deploy.ps1

# 指定版本部署（範例：Dynamo 4.0 / Revit 2027）
./deploy.ps1 -TargetDynamoVersions 4.0
```

### Step 3: 手動啟動與連線（正式建議流程）

1. 手動開啟目標 Revit。
2. 手動開啟 Dynamo。
3. 點 `BIM Assistant` → `Connect to MCP Server`。
4. 以 `get_server_stats` 確認 `active_sessions > 0`。

### Step 4: 最小可用驗證（必做）

依序執行：

1. `analyze_workspace`
2. `execute_dynamo_instructions`（建立 1 個 Code Block）
3. 再次 `analyze_workspace`（確認 `nodeCount` 增加）

## 版本映射（部署鍵）

| Revit | Dynamo | 部署鍵 |
|---|---|---|
| 2020 | 2.3.0.5885 | 2.3 |
| 2021 | 2.6.1.8786 | 2.6 |
| 2022 | 2.10.1.3976 | 2.10 |
| 2023 | 2.13.1.3887 | 2.13 |
| 2024 | 2.19.3.6394 | 2.19 |
| 2025 | 3.0.3.7597 | 3.0 |
| 2026 | 3.4.1.7055 | 3.4 |
| 2027 | 4.0.2.3852 | 4.0（AppData 常見為 27.0） |

## 驗收條件

安裝任務完成必須同時滿足：

1. `get_server_stats.active_sessions > 0`
2. `execute_dynamo_instructions` 回傳 `status=ok`
3. 第二次 `analyze_workspace` 的 `nodeCount` 比第一次增加

## 常見失敗與對策

1. 看得到 UI 但沒有連線：以 `active_sessions` 為唯一判準，不看 UI 文案。
2. 2027 看似失敗：優先檢查 `%AppData%\\Dynamo\\Dynamo Revit\\27.0`。
3. 重部署後無效果：通常是 Revit 未關閉導致 DLL 被鎖定。

## 產出格式（回報模板）

回報時使用固定欄位，降低來回成本：

1. 模式：偵測安裝 / 全矩陣
2. 版本：Revit 年份 + Dynamo 版本鍵
3. 部署：成功 / 失敗
4. 連線：`active_sessions` 數值
5. 冒煙：`analyze -> execute -> analyze` 結果
6. 風險或限制：若有

## 參考文件

1. `docs/revit-2020-2027-install-test-plan.md`
2. `domain/startup_checklist.md`
3. `domain/troubleshooting.md`
4. `README.md`

---

Skill 版本：1.0  
最後更新：2026-05-29
