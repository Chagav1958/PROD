using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Show_LLMs
{
    public class ModelEntry
    {
        public string Provider { get; set; } = "";
        public string Model { get; set; } = "";
        public string Api { get; set; } = "";
        public string Status { get; set; } = "";
    }

    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);

        private const int WM_NCHITTEST = 0x0084, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private List<ModelEntry> _models = new();
        private Dictionary<string, string> _results = new();
        private string _projectRoot;

        private static readonly HttpClient _http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };

        private static string _logPath = Path.Combine(Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".", $"tech_journal_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        private static readonly object _logLock = new();
        private static bool _exitAfterAutoTest = false;
        private static List<string> _autoTestCommands = new();
        private static int _autoTestCmdIndex = 0;

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {System.Reflection.Assembly.GetExecutingAssembly().Location}");
            Log("INFO", $"Args: {string.Join(" | ", Environment.GetCommandLineArgs())}");
            _projectRoot = GetProjectRoot();
            LoadConfig();
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { }
        }

        private string GetProjectRoot()
        {
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            if (File.Exists(Path.Combine(exeDir, "..\\..\\..\\opencode.jsonc"))) return Path.GetFullPath(Path.Combine(exeDir, "..\\..\\..\\"));
            if (File.Exists(Path.Combine(exeDir, "..\\opencode.jsonc"))) return Path.GetFullPath(Path.Combine(exeDir, "..\\"));
            return Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
        }

        private void LoadConfig()
        {
            foreach (string fn in new[] { "opencode.jsonc", "opencode.json" })
            {
                string fp = Path.Combine(_projectRoot, fn);
                if (!File.Exists(fp)) continue;
                try
                {
                    string txt = File.ReadAllText(fp);
                    txt = Regex.Replace(txt, "//.*", "");
                    using JsonDocument doc = JsonDocument.Parse(txt);
                    if (doc.RootElement.TryGetProperty("providers", out JsonElement provs))
                    {
                        foreach (var prov in provs.EnumerateObject())
                        {
                            string api = prov.Value.TryGetProperty("api", out JsonElement a) ? a.GetString() ?? "" : "";
                            if (prov.Value.TryGetProperty("models", out JsonElement models))
                            {
                                foreach (var m in models.EnumerateArray())
                                {
                                    _models.Add(new ModelEntry { Provider = prov.Name, Model = m.GetString() ?? "", Api = api });
                                }
                            }
                        }
                    }
                }
                catch (Exception ex) { Log("ERROR", $"Config load: {ex.Message}"); }
                break;
            }
            Log("INFO", $"Loaded {_models.Count} models");
            BindData();
        }

        private void ParseAutoTestArgs()
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
                if (args[i] == "--autotest" && i + 1 < args.Length)
                {
                    string file = args[i + 1];
                    if (File.Exists(file)) { _autoTestCommands = File.ReadAllLines(file).ToList(); _exitAfterAutoTest = true; Log("AUTOTEST", $"Loaded {_autoTestCommands.Count} commands"); }
                }
        }

        private void RunAutoTestCommand()
        {
            if (_autoTestCmdIndex >= _autoTestCommands.Count) return;
            string line = _autoTestCommands[_autoTestCmdIndex++].Trim();
            if (string.IsNullOrEmpty(line)) { RunAutoTestCommand(); return; }
            Log("AUTOTEST", $"CMD[{_autoTestCmdIndex - 1}]: {line}");
            var parts = line.Split(' ', 3);
            string cmd = parts[0].ToLower(), arg = parts.Length > 1 ? parts[1] : "";
            try
            {
                switch (cmd)
                {
                    case "close": Close(); break;
                    case "click":
                        if (arg == "test") BtnTest_Click(this, new RoutedEventArgs());
                        else if (arg == "close") BtnClose_Click(this, new RoutedEventArgs());
                        Log("AUTOTEST", $"click: {arg}"); break;
                    case "wait": Thread.Sleep(int.Parse(arg)); break;
                    case "log": Log("AUTOTEST", arg); break;
                }
            }
            catch (Exception ex) { Log("ERROR", $"CMD failed: {ex.Message}"); }
            if (_autoTestCmdIndex < _autoTestCommands.Count)
            {
                DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
                t.Tick += (s, e) => { t.Stop(); RunAutoTestCommand(); }; t.Start();
            }
            else
            {
                Log("AUTOTEST", "All commands done");
                if (_exitAfterAutoTest) { DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
                    t.Tick += (s, e) => { t.Stop(); Close(); }; t.Start(); }
            }
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            Log("INFO", "Window loaded");
            ApplyRoundedRegion();
            if (_autoTestCommands.Count > 0) { DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, ev) => { t.Stop(); RunAutoTestCommand(); }; t.Start(); }
        }

        private void Window_SizeChanged(object sender, SizeChangedEventArgs e) { ApplyRoundedRegion(); Log("INFO", $"SizeChanged: {ActualWidth}x{ActualHeight}"); }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            HwndSource source = PresentationSource.FromVisual(this) as HwndSource;
            if (source != null) source.AddHook(WndProc);
        }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_NCHITTEST)
            {
                int x = (int)(lParam.ToInt64() & 0xFFFF), y = (int)((lParam.ToInt64() >> 16) & 0xFFFF);
                Point p = PointFromScreen(new Point(x, y));
                double w = ActualWidth, h = ActualHeight; int m = RESIZE_MARGIN;
                bool onLeft = p.X < m, onRight = p.X > w - m, onTop = p.Y < m, onBottom = p.Y > h - m;
                if (p.Y < 42 && !onTop && !onLeft && !onRight) { handled = true; return (IntPtr)HTCAPTION; }
                if (onTop && onLeft) { handled = true; return (IntPtr)HTTOPLEFT; }
                if (onTop && onRight) { handled = true; return (IntPtr)HTTOPRIGHT; }
                if (onBottom && onLeft) { handled = true; return (IntPtr)HTBOTTOMLEFT; }
                if (onBottom && onRight) { handled = true; return (IntPtr)HTBOTTOMRIGHT; }
                if (onLeft) { handled = true; return (IntPtr)HTLEFT; }
                if (onRight) { handled = true; return (IntPtr)HTRIGHT; }
                if (onTop) { handled = true; return (IntPtr)HTTOP; }
                if (onBottom) { handled = true; return (IntPtr)HTBOTTOM; }
            }
            return IntPtr.Zero;
        }

        private void ApplyRoundedRegion()
        {
            try
            {
                IntPtr hWnd = new WindowInteropHelper(this).Handle;
                if (hWnd == IntPtr.Zero) return;
                int w = (int)ActualWidth, h = (int)ActualHeight;
                if (w <= 0 || h <= 0) { w = 960; h = 640; }
                IntPtr hRgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, hRgn, true);
                DeleteObject(hRgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
        }

        private void BindData()
        {
            var items = _models.Select(m => new ModelEntry
            {
                Provider = m.Provider,
                Model = m.Model,
                Api = string.IsNullOrEmpty(m.Api) ? "-" : m.Api,
                Status = _results.TryGetValue($"{m.Provider}/{m.Model}", out string s) && !string.IsNullOrEmpty(s) ? s : "-"
            }).ToList();
            dgModels.ItemsSource = null;
            dgModels.ItemsSource = items;
            int ok = _results.Count(v => v.Value == "OK");
            lblStatus.Text = $"{_models.Count} моделей | {ok} OK";
        }

        private async void BtnTest_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "test");
            btnTest.IsEnabled = false;
            _results.Clear();
            BindData();
            await Task.Run(() => DoTestAll());
            CacheResults();
            btnTest.IsEnabled = true;
            Log("INFO", "Test all done");
        }

        private void DoTestAll()
        {
            int i = 0;
            foreach (var m in _models)
            {
                string key = $"{m.Provider}/{m.Model}";
                bool ok = TestOne(m);
                _results[key] = ok ? "OK" : "FAIL";
                int idx = i;
                Dispatcher.Invoke(() => { BindData(); });
                i++;
            }
        }

        private bool TestOne(ModelEntry m)
        {
            string api = m.Api;
            string model = m.Model;
            if (string.IsNullOrEmpty(api)) return false;
            try
            {
                string url = api.TrimEnd('/');
                if (api.ToLower().Contains("ollama")) url += "/api/tags";
                else if (api.ToLower().Contains("openai") || api.ToLower().Contains("router") || api.ToLower().Contains("anthropic")) url += "/models";
                var resp = _http.GetAsync(url).Result;
                return resp.IsSuccessStatusCode;
            }
            catch { return false; }
        }

        private void CacheResults()
        {
            try
            {
                string cache = Path.Combine(_projectRoot, "temp", "llm_test_results.json");
                string json = JsonSerializer.Serialize(_results, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(cache, json);
            }
            catch (Exception ex) { Log("ERROR", $"Cache: {ex.Message}"); }
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2) { ToggleMaximize(); return; }
            try { DragMove(); } catch (Exception ex) { Log("ERROR", $"DragMove: {ex.Message}"); }
        }

        private void ToggleMaximize() { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; Log("INFO", $"Maximized: {WindowState == WindowState.Maximized}"); }
        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; Log("CLICK", "min"); }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); Log("CLICK", "max"); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Log("CLICK", "close"); Close(); }
        private void BtnCancel_Click(object sender, RoutedEventArgs e) { Log("CLICK", "cancel"); Close(); }
    }
}