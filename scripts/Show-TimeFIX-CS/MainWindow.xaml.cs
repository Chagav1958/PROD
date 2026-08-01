using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Show_TimeFIX
{
    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
        private const int WM_NCHITTEST = 0x0084, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private static string _logPath = Path.Combine(Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".", $"tech_journal_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        private static readonly object _logLock = new();
        private static bool _exitAfterAutoTest = false;
        private static List<string> _autoTestCommands = new();
        private static int _autoTestCmdIndex = 0;

        private string _projectRoot;
        private DateTime _currentWeekStart;

        public class CalendarEntry { public string Date { get; set; } = ""; public string Time { get; set; } = ""; public string Subject { get; set; } = ""; public string Duration { get; set; } = ""; public string Status { get; set; } = ""; }

        private ObservableCollection<CalendarEntry> _entries = new();

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {System.Reflection.Assembly.GetExecutingAssembly().Location}");
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
            _currentWeekStart = GetWeekStart(DateTime.Now);
            listView.ItemsSource = _entries;
            UpdatePeriodLabel();
            LoadCalendarData();
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg) { string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}"; try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { } }

        private DateTime GetWeekStart(DateTime dt)
        {
            int diff = (7 + (dt.DayOfWeek - DayOfWeek.Monday)) % 7;
            return dt.AddDays(-diff).Date;
        }

        private void UpdatePeriodLabel()
        {
            string end = _currentWeekStart.AddDays(6).ToString("dd.MM");
            txtPeriod.Text = $"{_currentWeekStart:dd.MM.yyyy} — {end}";
        }

        private void LoadCalendarData()
        {
            _entries.Clear();
            string calFile = Path.Combine(_projectRoot, "config", "calendar_data.json");
            if (!File.Exists(calFile))
                calFile = Path.Combine(_projectRoot, "calendar_data.json");
            if (!File.Exists(calFile))
            {
                _entries.Add(new CalendarEntry { Date = "Нет данных", Subject = $"Файл calendar_data.json не найден в {_projectRoot}", Status = "Ошибка" });
                Log("WARN", "Calendar data file not found");
                return;
            }
            try
            {
                string json = File.ReadAllText(calFile);
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;
                var arr = root.ValueKind == JsonValueKind.Array ? root : root.GetProperty("items");
                foreach (var item in arr.EnumerateArray())
                {
                    var entry = new CalendarEntry();
                    if (item.TryGetProperty("date", out var d)) entry.Date = d.GetString() ?? "";
                    if (item.TryGetProperty("time", out var t)) entry.Time = t.GetString() ?? "";
                    if (item.TryGetProperty("subject", out var s)) entry.Subject = s.GetString() ?? "";
                    if (item.TryGetProperty("duration", out var dur)) entry.Duration = dur.GetString() ?? "";
                    if (item.TryGetProperty("status", out var st)) entry.Status = st.GetString() ?? "";
                    _entries.Add(entry);
                }
                Log("INFO", $"Loaded {_entries.Count} calendar entries");
            }
            catch (Exception ex) { Log("ERROR", $"LoadCalendar: {ex.Message}"); _entries.Add(new CalendarEntry { Date = "Ошибка", Subject = ex.Message, Status = "Ошибка" }); }
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
                        if (arg == "sync") BtnSync_Click(null, null);
                        else if (arg == "apply") BtnApplyFix_Click(null, null);
                        else if (arg == "today") BtnToday_Click(null, null);
                        else if (arg == "prev") BtnPrev_Click(null, null);
                        else if (arg == "next") BtnNext_Click(null, null);
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
            else { Log("AUTOTEST", "All commands done"); if (_exitAfterAutoTest) { DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, e) => { t.Stop(); Close(); }; t.Start(); } }
        }

        private async void BtnSync_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "sync");
            string script = Path.Combine(_projectRoot, "scripts", "Show-TimeFIX-CS", "sync_outlook.ps1");
            if (!File.Exists(script))
                script = Path.Combine(_projectRoot, "scripts", "sync_outlook.ps1");
            if (!File.Exists(script))
            {
                MessageBox.Show($"Скрипт синхронизации не найден:\n{script}", "Ошибка", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell",
                    Arguments = $"-NoLogo -ExecutionPolicy Bypass -File \"{script}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using var proc = Process.Start(psi);
                if (proc != null) await proc.WaitForExitAsync();
                Log("INFO", $"Sync exit code: {proc?.ExitCode ?? -1}");
                LoadCalendarData();
            }
            catch (Exception ex) { Log("ERROR", $"Sync: {ex.Message}"); MessageBox.Show(ex.Message, "Ошибка", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        private void BtnApplyFix_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "apply_fix");
            if (listView.SelectedItem is CalendarEntry sel)
            {
                sel.Status = "FIXED";
                _entries.Remove(sel);
                _entries.Insert(0, sel);
                Log("INFO", $"Fixed: {sel.Subject}");
            }
            else
                MessageBox.Show("Выберите запись в списке", "Применить FIX", MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void BtnToday_Click(object sender, RoutedEventArgs e) { Log("CLICK", "today"); _currentWeekStart = GetWeekStart(DateTime.Now); UpdatePeriodLabel(); LoadCalendarData(); }
        private void BtnPrev_Click(object sender, RoutedEventArgs e) { Log("CLICK", "prev"); _currentWeekStart = _currentWeekStart.AddDays(-7); UpdatePeriodLabel(); LoadCalendarData(); }
        private void BtnNext_Click(object sender, RoutedEventArgs e) { Log("CLICK", "next"); _currentWeekStart = _currentWeekStart.AddDays(7); UpdatePeriodLabel(); LoadCalendarData(); }

        private void Window_Loaded(object sender, RoutedEventArgs e) { Log("INFO", "Window loaded"); ApplyRoundedRegion(); if (_autoTestCommands.Count > 0) { DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, ev) => { t.Stop(); RunAutoTestCommand(); }; t.Start(); } }
        private void Window_SizeChanged(object sender, SizeChangedEventArgs e) { ApplyRoundedRegion(); }
        protected override void OnSourceInitialized(EventArgs e) { base.OnSourceInitialized(e); if (PresentationSource.FromVisual(this) is HwndSource hs) hs.AddHook(WndProc); }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_NCHITTEST)
            {
                int x = (int)(lParam.ToInt64() & 0xFFFF), y = (int)((lParam.ToInt64() >> 16) & 0xFFFF);
                var p = PointFromScreen(new Point(x, y)); double w = ActualWidth, h = ActualHeight; int m = RESIZE_MARGIN;
                if (p.Y < 42 && !(p.X < m) && !(p.X > w - m) && !(p.Y < m)) { handled = true; return (IntPtr)HTCAPTION; }
                if (p.X < m && p.Y < m) { handled = true; return (IntPtr)HTTOPLEFT; }
                if (p.X > w - m && p.Y < m) { handled = true; return (IntPtr)HTTOPRIGHT; }
                if (p.X < m && p.Y > h - m) { handled = true; return (IntPtr)HTBOTTOMLEFT; }
                if (p.X > w - m && p.Y > h - m) { handled = true; return (IntPtr)HTBOTTOMRIGHT; }
                if (p.X < m) { handled = true; return (IntPtr)HTLEFT; }
                if (p.X > w - m) { handled = true; return (IntPtr)HTRIGHT; }
                if (p.Y < m) { handled = true; return (IntPtr)HTTOP; }
                if (p.Y > h - m) { handled = true; return (IntPtr)HTBOTTOM; }
            }
            return IntPtr.Zero;
        }

        private void ApplyRoundedRegion()
        {
            try
            {
                var hWnd = new WindowInteropHelper(this).Handle;
                if (hWnd == IntPtr.Zero) return;
                int w = (int)ActualWidth, h = (int)ActualHeight;
                if (w <= 0 || h <= 0) { w = 960; h = 640; }
                var rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, rgn, true); DeleteObject(rgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (e.ClickCount == 2) { ToggleMaximize(); return; } try { DragMove(); } catch { } }
        private void ToggleMaximize() { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; }
        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; Log("CLICK", "min"); }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); Log("CLICK", "max"); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Log("CLICK", "close"); Close(); }
    }
}