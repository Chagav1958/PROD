using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Show_ProgressState
{
    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);

        private const int WM_NCHITTEST = 0x0084, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private string _stateFile;
        private string _prevHash = "";
        private DispatcherTimer _pollTimer;
        private bool _useAutotestTimer = false;
        private int _autotestTick = 0;

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
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            string projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
            _stateFile = Path.Combine(projectRoot, "temp", "progress_state.json");
            Log("INFO", $"State file: {_stateFile}");
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { }
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
            StartPolling();
        }

        private void Window_SizeChanged(object sender, SizeChangedEventArgs e) { ApplyRoundedRegion(); Log("INFO", $"SizeChanged: {ActualWidth}x{ActualHeight}"); }
        private void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e) { StopPolling(); }

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
                if (w <= 0 || h <= 0) { w = 460; h = 280; }
                IntPtr hRgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, hRgn, true);
                DeleteObject(hRgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
        }

        private void StartPolling()
        {
            _pollTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            _pollTimer.Tick += (s, e) => Poll();
            _pollTimer.Start();
        }

        private void StopPolling() { if (_pollTimer != null) { _pollTimer.Stop(); _pollTimer = null; } }

        private void Poll()
        {
            if (!File.Exists(_stateFile))
            {
                lblStatus.Text = "Ожидание запуска задач...";
                return;
            }
            try
            {
                string json = File.ReadAllText(_stateFile);
                using JsonDocument doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                string h = $"{root.GetProperty("task_num").GetInt32()}|{root.GetProperty("step_pct").GetInt32()}|{root.GetProperty("done").GetBoolean()}|{root.GetProperty("task_name").GetString()}";
                if (h == _prevHash) return;
                _prevHash = h;

                if (root.GetProperty("done").GetBoolean())
                {
                    lblStatus.Text = "✅ Все задачи выполнены!";
                    pbOverall.Value = 100;
                    pbStep.Value = 100;
                    lblTimestamp.Text = $"Последнее обновление: {root.GetProperty("timestamp").GetString()}";
                    StopPolling();
                    DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(4000) };
                    t.Tick += (s, ev) => { t.Stop(); Close(); };
                    t.Start();
                    return;
                }

                int total = root.GetProperty("task_total").GetInt32();
                int num = root.GetProperty("task_num").GetInt32();
                int overall = total > 0 ? (int)((double)num / total * 100) : 0;
                pbOverall.Value = overall;
                lblTask.Text = $"Задача: {num} из {total} — {root.GetProperty("task_name").GetString()}";

                int stepPct = root.GetProperty("step_pct").GetInt32();
                pbStep.Value = stepPct;

                string step = root.GetProperty("step").GetString() ?? "";
                string status = root.GetProperty("status").GetString() ?? "";
                var parts = new List<string>();
                if (!string.IsNullOrEmpty(step)) parts.Add($"Шаг: {step}");
                if (!string.IsNullOrEmpty(status)) parts.Add($"Статус: {status}");
                lblStatus.Text = string.Join(" | ", parts);
                lblTimestamp.Text = $"Обновлено: {root.GetProperty("timestamp").GetString()}";
            }
            catch
            {
                lblStatus.Text = "Ошибка чтения данных...";
            }
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
    }
}