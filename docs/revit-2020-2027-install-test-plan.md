# Revit 2020-2027 安裝與測試實作計畫

> 版本：v1.1（Token 節省版）
> 目的：將 AutodeskDynamo_MCP 的安裝、部署、連線與驗證流程，整理成可逐版本執行的標準計畫，並提供未來不同使用者可直接複用的快速安裝指引。

## 0. 執行狀態

- 狀態：執行中
- 起始方式：先建立 Revit 2020-2027 逐版測試結果模板，再依版本逐一填寫
- 基準版本：Revit 2024
- 結果模板：[`docs/revit-2020-2027-test-results-template.md`](docs/revit-2020-2027-test-results-template.md)

## 1. 計畫目標

1. 建立一套可重複的 Dynamo MCP 安裝與部署流程。
2. 驗證 Revit 2020-2027 各版本的可安裝性、可連線性與核心功能可用性。
3. 釐清哪些版本屬於正式支援、條件支援或僅觀察性測試。
4. 為後續維護建立版本矩陣、風險清單與回退策略。

## 2. 現況基線

依目前倉庫文件，已確認的穩定基線如下：

- 核心橋接流程為 `bridge/node/index.js` → `bridge/python/server.py` → `DynamoViewExtension`。
- Revit 2020-2027 已完成核心冒煙驗證（`analyze -> clear -> execute -> analyze`）。
- Revit 2024 已完成進階冒煙（2點1線、Python Script 鏈路），可作為回歸基準版本。
- `domain/python_script_automation.md` 已標示 Revit 2025 需要特別注意 CPython3。
- `domain/startup_checklist.md` 與 `domain/troubleshooting.md` 已定義連線檢查、幽靈連線與多實例衝突的處理流程。

## 3. 支援邊界與假設

在沒有實機完整矩陣前，先採保守假設：

- Revit 2020-2027 不先預設全部完全支援。
- 若某版本無法載入 ViewExtension、無法建立連線或 Python 注入失敗，先記錄為「條件不滿足」而非立刻視為環境故障。
- Revit 2025 之後需額外驗證 Python 引擎與 Python Script 節點顯示行為。
- 外掛節點與 Custom Node 以 GUID 建立為主，不以名稱搜尋成功與否作為唯一判準。

### 3.1 多版本策略決策（全矩陣 vs 偵測安裝）

為避免預設所有使用者都有完整 2020-2027 環境，先做模式選擇：

1. 全矩陣模式：適用維護者、發版前回歸、跨版本相容性驗證。
2. 偵測安裝模式：適用一般使用者，只針對本機已安裝 Revit 版本部署與測試。

建議預設採「偵測安裝模式」，只在以下情況改用全矩陣：

1. 修改 C# ViewExtension 核心行為。
2. 修改 `deploy.ps1` 版本映射策略。
3. 發版前需要完整相容性報告。

## 4. 共用安裝流程

### 4.1 前置準備

1. 確認 Windows 環境可正常執行 PowerShell。
2. 確認 Python、Node.js 與 .NET SDK 環境可用：
	- Revit 2020-2026：至少可用 .NET 8 SDK。
	- Revit 2027（Dynamo 4.x）：需安裝 .NET 10 SDK。
3. 確認 Revit 與對應 Dynamo 版本已安裝。
4. 確認目標機器有可用的 Dynamo 套件部署路徑。

### 4.2 部署步驟

1. 編輯 `mcp_config.template.jsonc`。
2. 依需要調整 `server.port` 與 `auto_deployment.target_dynamo_versions`。
3. 執行 `./deploy.ps1`。
4. 驗證 `mcp_config.json` 是否已生成或更新。
5. 驗證 C# ViewExtension 與相關檔案是否已部署到目標 Dynamo 路徑。

### 4.3 啟動順序

1. 啟動 Revit 或 Dynamo Sandbox。
2. 由 Dynamo 內的 `BIM Assistant` 連線至 MCP Server。
3. 啟動 Python MCP Server：`python bridge/python/server.py`。
4. 由 AI Client 透過 Node bridge 連入。

### 4.4 手動啟動流程（目前建議）

目前自動開啟 Revit / Dynamo 的腳本尚在調整，不建議納入正式流程。跨版本測試請採用手動步驟：

1. 手動啟動目標版本 Revit。
2. 手動開啟 Dynamo。
3. 在 Dynamo 內確認 `BIM Assistant` 已顯示。
4. 手動點擊 `Connect to MCP Server`。
5. 以 `get_server_stats` 檢查 `active_sessions > 0` 後再執行測試指令。

### 4.5 一頁式快速安裝指引（給未來不同使用者）

以下流程可作為預設 SOP，優先追求「快速可用」與「低 token 成本」。

1. 判斷目標 Revit 版本（只需確認年份）。
2. 執行部署：`./deploy.ps1 -TargetDynamoVersions <版本>`。
3. 手動開啟 Revit + Dynamo。
4. 在 Dynamo 點 `BIM Assistant` → `Connect to MCP Server`。
5. 跑三步最小驗證：
	- `analyze_workspace`
	- `execute_dynamo_instructions`（建立一個 Code Block）
	- 再 `analyze_workspace`（確認 `nodeCount` 增加）

版本映射（部署時用）：

| Revit | Dynamo | 部署目標鍵 |
|---|---|---|
| 2020 | 2.3.0.5885 | 2.3 |
| 2021 | 2.6.1.8786 | 2.6 |
| 2022 | 2.10.1.3976 | 2.10 |
| 2023 | 2.13.1.3887 | 2.13 |
| 2024 | 2.19.3.6394 | 2.19 |
| 2025 | 3.0.3.7597 | 3.0 |
| 2026 | 3.4.1.7055 | 3.4 |
| 2027 | 4.0.2.3852 | 4.0（實際 AppData 路徑可能為 27.0） |

關鍵提醒：

1. Revit 2027 實際載入路徑以 `%AppData%\\Dynamo\\Dynamo Revit\\27.0` 為主，不要只看 `4.0` 資料夾。
2. 重新部署 DLL 前，先關閉 Revit / Dynamo，避免檔案鎖定。
3. Dynamo UI 已開啟不代表連線成功，請以 `active_sessions > 0` 作為唯一準則。

### 4.6 低 Token 互動模板（建議）

為避免每次安裝都重跑長篇診斷，建議使用以下最短互動模板：

1. `目標版本：Revit <年份>`
2. `狀態：Revit 已開啟 / Dynamo 已開啟 / 已點 Connect`
3. `需求：請直接執行核心冒煙並回報 PASS/FAIL`

當回報失敗時再補充：

1. `最後錯誤訊息`
2. `是否剛重新部署`
3. `是否已重開 Dynamo`

此模板可大幅減少來回詢問與上下文重建成本。

## 5. 逐版本測試矩陣

這次不採代表版本抽樣，而是要對 Revit 2020-2027 逐版測試，逐一註記限制與測試結果。建議先以 Revit 2024 當作基準版本，再往前驗證舊版、往後驗證新版。

### 5.1 測試原則

1. 每一版都要執行相同的安裝、連線與核心功能測試。
2. 每一版都要記錄限制，不能只記錄成功與失敗。
3. 每一版都要標註是否需要 CPython3、是否有已知外掛缺口、是否有幽靈連線或 Session 風險。
4. 若某版不完全可用，也要明確寫出失敗點與回退方式，避免後續誤判為可正式支援。

### 5.2 版本矩陣

| Revit 版本 | 測試定位 | 預期/限制重點 | 測試結果 | 備註 |
|---|---|---|---|---|
| 2020 | 舊版驗證 | 需確認 ViewExtension、Dynamo 與 MCP 連線是否相容 | 已通過（核心冒煙） | 已驗證 analyze 與 Code Block 建立 |
| 2021 | 舊版驗證 | 需確認舊版節點名稱與外掛相容性 | 已通過（核心冒煙） | 已驗證 analyze 與 Code Block 建立 |
| 2022 | 舊版驗證 | 需確認部署路徑與連線流程是否一致 | 已通過（核心冒煙） | 已驗證 analyze 與 Code Block 建立 |
| 2023 | 過渡驗證 | 對應 Dynamo 2.13.1.3887，需確認是否仍能沿用 2024 基準流程 | 已通過（核心冒煙） | Revit 2023 已驗證 analyze → clear → execute Code Block → analyze（nodeCount=1） |
| 2024 | 基準版本 | 作為主要對照點，先確認全流程可用 | 已通過（核心/進階/ Python 冒煙） | 已驗證 Code Block、2點1線、Python Script 鏈路 |
| 2025 | 新版驗證 | 對應 Dynamo 3.0.3.7597，需特別確認 CPython3 與 Python Script 行為 | 已通過（核心冒煙） | 已驗證 analyze → clear → execute Code Block → analyze（nodeCount=1） |
| 2026 | 新版驗證 | 對應 Dynamo 3.4.1.7055，需確認 API 行為、節點建立與連線穩定性 | 已通過（核心冒煙） | 已驗證 analyze → clear → execute Code Block → analyze（nodeCount=1） |
| 2027 | 最新版驗證 | 對應 Dynamo 4.0.2.3852，需確認是否延續 2025+ 的 Python 與 API 規則 | 已通過（核心冒煙） | 已驗證 analyze → clear → execute Code Block → analyze（nodeCount=1）；Revit 2027 實際載入路徑為 AppData 27.0（非 4.0） |

### 5.3 每版記錄格式

每個 Revit 版本測完後，都用同一格式回填：

1. 安裝狀態：成功 / 失敗。
2. ViewExtension 載入狀態：成功 / 失敗。
3. `analyze_workspace`：成功 / 失敗。
4. `search_nodes`：成功 / 失敗。
5. `execute_dynamo_instructions`：成功 / 失敗。
6. Python Script：成功 / 失敗。
7. 外掛節點 GUID 建立：成功 / 失敗。
8. 限制說明：例如 CPython3、節點名稱差異、連線失敗、幽靈連線。
9. 回退方式：例如重連、改用 GUID、改用 Code Block、重新部署。

若實測過程發現某一版與基準版差異很大，應立刻在表格中補上限制說明，不等全部版本跑完才回填。

## 6. 測試項目

### 6.1 安裝驗證

每個版本都要確認：

1. Revit 可正常啟動。
2. Dynamo 可正常開啟。
3. ViewExtension 已載入。
4. `BIM Assistant` 可顯示連線狀態。

### 6.2 連線驗證

依 `domain/startup_checklist.md` 的順序執行：

1. `analyze_workspace` 回傳成功。
2. 回應包含 `sessionId`、`nodeCount`、`workspaceName`。
3. 重新開啟 Dynamo 後，確認 Session 變化可正確識別。
4. 模擬幽靈連線情境，驗證重新連線流程有效。

### 6.3 核心功能驗證

每個版本固定測：

1. `search_nodes` 是否可搜尋內建節點。
2. `execute_dynamo_instructions` 是否可建立 Code Block。
3. 原生節點建立與連線是否正常。
4. Python Script 節點是否可建立、寫入代碼並顯示於 UI。
5. 外掛節點是否可依 GUID 建立。

### 6.4 Python 驗證

特別針對 Revit 2025-2027：

1. 驗證是否需要 CPython3。
2. 驗證 Python Script 節點內部名稱是否影響建立成功率。
3. 驗證代碼注入後 UI 是否同步顯示。

## 7. 失敗回收流程

若測試失敗，依下列順序處理：

1. 先判斷是否為連線失敗。
2. 若畫面與 `nodeCount` 不一致，判定為幽靈連線。
3. 若節點已建立但不可見，重新執行 `BIM Assistant` 斷線與重連。
4. 若 Python 失敗，對照 `domain/python_script_automation.md`。
5. 若外掛節點失敗，改用 GUID 建立，並參照 `memory-bank/lessons/node-creation-guid.md`。

## 8. 記錄欄位

每次測試至少記錄以下欄位：

1. Revit 版本。
2. Dynamo 版本。
3. Python 引擎。
4. ViewExtension 是否載入。
5. `analyze_workspace` 結果。
6. 是否出現幽靈連線。
7. Python Script 是否成功。
8. 外掛節點是否成功。
9. 修復後是否恢復正常。

## 9. 產出物

完成本計畫後，應輸出三份結果：

1. Revit 2020-2027 版本支援矩陣。
2. 安裝與測試紀錄表。
3. 問題與回退策略摘要。

## 10. 建議下一步

1. 先選一個基準版本做完整冒煙測試。
2. 再決定是逐版測試，還是以代表版本建立支援矩陣。
3. 若需要，我可以下一步直接把這份計畫拆成逐步執行清單與測試表格。

## 11. 本輪錯誤彙整與防再發（已驗證）

以下為 Revit 2024（Dynamo 2.19）實測曾出現的錯誤、根因與修正方式。後續測 Revit 2020-2027 時，請直接沿用本節流程。

### 11.1 錯誤：`analyze_workspace` 回 `Processing error: NullReference`

1. 現象：連線看似成功，但 `get_graph_status` / `analyze_workspace` 立即失敗。
2. 根因：`GraphHandler` 對非 action 訊息與 `CurrentWorkspace` 空值缺少完整防呆。
3. 修正：
	- 非 action 的 `status/sessionId` 訊息先短路處理。
	- 所有 workspace 讀取路徑加入 null guard。
4. 防再發：
	- 每版先跑一次 `analyze_workspace`（空白畫布也要可回傳）。
	- 若失敗，先看 `DynamoMCP.log` 是否在 `get_graph_status` 崩潰。

### 11.2 錯誤：`execute_dynamo_instructions` 回 `Missing action`

1. 現象：MCP 連線正常，但執行節點建立指令被拒絕。
2. 根因：`execute_dynamo_instructions` 傳送的是 legacy payload（`nodes/connectors`），不一定含 `action`。
3. 修正：`GraphHandler` 增加 backward compatibility，遇到 `nodes/connectors` 視為可執行 payload。
4. 防再發：
	- 跨版本測試時，維持工具層仍以 `execute_dynamo_instructions` 為主，不要手動改 payload 協定。

### 11.3 錯誤：`Partial failure` + WPF `CollectionView` 例外

1. 現象：回傳 `Partial failure`，但畫布節點可能部分建立，結果不一致。
2. 根因：命令在非 UI 執行緒觸發，WPF 集合更新拋出 `NotSupportedException`。
3. 修正：
	- `WebSocketClient` 改為固定使用 UI Dispatcher 執行 `HandleCommand`。
	- 避免使用直接執行 fallback 去修改 Dynamo UI 綁定集合。
4. 防再發：
	- 若 log 出現 `Dispatcher unavailable`，直接視為阻斷問題，先修再測。
	- 不要用「節點看起來有出現」判定成功，必須以 API 回傳 `status=ok` + `analyze_workspace` 驗證。

### 11.4 錯誤：修補後仍無效（實際載入舊 DLL）

1. 現象：程式已改，但日誌行為與錯誤訊息沒變。
2. 根因：Revit 尚未關閉，DLL 被鎖定，實際仍載入舊版套件。
3. 修正：關閉 Revit 後重新 `deploy.ps1`，再重新開啟 Revit + Dynamo。
4. 防再發：
	- 規則：只要改 C# 外掛就先關 Revit 再部署。
	- 規則：部署後先看版本標記日誌，再跑功能測試。

### 11.5 跨版本標準前置檢核（每版必做）

1. 關閉 Revit。
2. 部署目標版本：`./deploy.ps1 -TargetDynamoVersions <version>`。
3. 開啟 Revit + Dynamo。
4. 跑核心冒煙：
	- `analyze_workspace`（應成功）
	- `execute_dynamo_instructions` 建一個 Code Block（應 `status=ok`）
	- 再 `analyze_workspace`（`nodeCount` 應增加）
5. 跑進階冒煙：
	- 2 點 1 線（`nodeCount=3`, `connectorCount=2`）
	- Python Script 鏈路（Number/CodeBlock -> Python Script -> Watch）
6. 每版保存證據：
	- `DynamoMCP.log` 尾段
	- 三段測試回傳 JSON
	- 版本矩陣回填結果