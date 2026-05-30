using System;
using System.Linq;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Dynamo.ViewModels;
using System.Windows.Threading;

namespace DynamoMCPListener
{
    [Autodesk.DesignScript.Runtime.IsVisibleInDynamoLibrary(false)]
    public class WebSocketClient : IDisposable
    {
        private const string BuildMarker = "WebSocketClient-2026-05-29-status-guard-v2";
        private ClientWebSocket _ws;
        private readonly Uri _serverUri;
        private readonly DynamoViewModel _vm;
        private readonly GraphHandler _handler;
        private readonly Dispatcher _uiDispatcher;
        private readonly string _sessionId;
        private CancellationTokenSource _cts;

        public event Action<bool> ConnectionStatusChanged;

        public WebSocketClient(DynamoViewModel vm, string sessionId)
        {
            _vm = vm;
            _sessionId = sessionId;
            _serverUri = new Uri(MCPConfig.WebSocketUrl);
            _handler = new GraphHandler(vm, sessionId);
            _uiDispatcher = Dispatcher.CurrentDispatcher;
            MCPLogger.Info($"[WS] Initialized marker={BuildMarker} session={_sessionId}");

            // 訂閱事件以監控 Start 節點狀態
            var workspace = _vm.Model.CurrentWorkspace;
            if (workspace != null)
            {
                workspace.NodeAdded += (n) => _ = ReportStatus();
                workspace.NodeRemoved += (n) => _ = ReportStatus();
            }
            else
            {
                MCPLogger.Warning($"[WS] CurrentWorkspace is null during initialization. marker={BuildMarker}");
            }
        }

        public async Task StartAsync()
        {
            _cts = new CancellationTokenSource();
            _ = Task.Run(() => ConnectLoop(_cts.Token));
        }

        private async Task ConnectLoop(CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                try
                {
                    MCPLogger.Info($"[WS] Attempting to connect to {_serverUri}");
                    _ws = new ClientWebSocket();
                    await _ws.ConnectAsync(_serverUri, token);
                    MCPLogger.Info("[WS] Connected successfully.");
                    ConnectionStatusChanged?.Invoke(true);

                    // 1. Handshake
                    await SendHandshake();

                    // 2. Receive Loop
                    await ReceiveLoop(token);
                }
                catch (Exception ex)
                {
                    if (!token.IsCancellationRequested)
                    {
                        MCPLogger.Warning($"[WS] Connection error: {ex.Message}. Retrying in 5s...");
                        await Task.Delay(5000, token);
                    }
                }
                finally
                {
                    ConnectionStatusChanged?.Invoke(false);
                    _ws?.Dispose();
                }
            }
        }

        private async Task SendHandshake()
        {
            var ws = _vm.Model.CurrentWorkspace;
            var handshake = new
            {
                action = "handshake",
                sessionId = _sessionId,
                fileName = ws?.FileName ?? "Home",
                processId = System.Diagnostics.Process.GetCurrentProcess().Id
            };
            await SendMessageAsync(JsonConvert.SerializeObject(handshake));
        }

        private async Task ReceiveLoop(CancellationToken token)
        {
            var buffer = new byte[1024 * 64]; // 64KB
            while (_ws.State == WebSocketState.Open && !token.IsCancellationRequested)
            {
                var result = await _ws.ReceiveAsync(new ArraySegment<byte>(buffer), token);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", token);
                }
                else
                {
                    string message = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    // Handle large messages split into Multiple frames
                    while (!result.EndOfMessage)
                    {
                        result = await _ws.ReceiveAsync(new ArraySegment<byte>(buffer), token);
                        message += Encoding.UTF8.GetString(buffer, 0, result.Count);
                    }

                    _ = Task.Run(() => ProcessMessage(message));
                }
                
                // 每接收一個訊息後，也順便回報當前狀態 (Mode B: 是否有 Start 節點)
                await ReportStatus();
            }
        }

        private async Task ProcessMessage(string json)
        {
            try
            {
                MCPLogger.Info($"[WS] Received command: {json.Substring(0, Math.Min(json.Length, 100))}...");
                MCPLogger.Info($"[WS] Dispatch marker={BuildMarker}");
                
                string response = "";

                // In WebSocket mode, the connection itself represents authorization
                // No need to check for StartMCPServer node

                // Ensure executing on UI Thread
                var dispatcher = ResolveDispatcher();
                if (dispatcher != null)
                {
                    await dispatcher.InvokeAsync(() =>
                    {
                        response = _handler.HandleCommand(json);
                    });
                }
                else
                {
                    MCPLogger.Warning($"[WS] Dispatcher unavailable, fallback to direct execution. marker={BuildMarker}");
                    response = _handler.HandleCommand(json);
                }

                await SendMessageAsync(response);
            }
            catch (Exception ex)
            {
                MCPLogger.Error($"[WS] Error processing message: {ex.Message}");
                // Try to send error back if possible
                try {
                     await SendMessageAsync($"{{\"error\": \"Processing error: {ex.Message}\"}}");
                } catch {}
            }
        }

        private Dispatcher ResolveDispatcher()
        {
            // Primary path in WPF host; may be null in some Dynamo/Revit embedding scenarios.
            if (_uiDispatcher != null)
            {
                return _uiDispatcher;
            }

            var appDispatcher = System.Windows.Application.Current?.Dispatcher;
            if (appDispatcher != null)
            {
                return appDispatcher;
            }

            try
            {
                var vmType = _vm.GetType();
                var uiDispatcherProp = vmType.GetProperty("UIDispatcher") ?? vmType.GetProperty("Dispatcher");
                var candidate = uiDispatcherProp?.GetValue(_vm);
                if (candidate is Dispatcher d)
                {
                    return d;
                }

                var nestedDispatcher = candidate?.GetType().GetProperty("Dispatcher")?.GetValue(candidate);
                if (nestedDispatcher is Dispatcher nd)
                {
                    return nd;
                }
            }
            catch (Exception ex)
            {
                MCPLogger.Warning($"[WS] ResolveDispatcher failed: {ex.Message}");
            }

            return null;
        }

        private async Task SendMessageAsync(string message)
        {
            if (_ws?.State != WebSocketState.Open) return;
            var bytes = Encoding.UTF8.GetBytes(message);
            await _ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
        }

        private async Task ReportStatus()
        {
            var status = new
            {
                action = "status_update",
                hasStartNode = CheckForStartNode()
            };
            await SendMessageAsync(JsonConvert.SerializeObject(status));
        }

        private bool CheckForStartNode()
        {
            // Deprecated: StartMCPServer nodes are no longer used.
            // Returning false as nodes are removed from workspace.
            return false;
        }

        public void Dispose()
        {
            _cts?.Cancel();
            _ws?.Dispose();
        }

        public async Task StopAsync()
        {
            Dispose();
        }
    }
}
