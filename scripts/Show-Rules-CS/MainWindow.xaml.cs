using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace Show_Rules
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
        private string _rulesDir;

        public class RuleFile { public string Name { get; set; } = ""; public string Content { get; set; } = ""; public string Category { get; set; } = ""; }

        private List<RuleFile> _allRules = new();
        private ObservableCollection<RuleFile> _filteredRules = new();

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {System.Reflection.Assembly.GetExecutingAssembly().Location}");
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
            _rulesDir = Path.Combine(_projectRoot, "config", "rules");
            if (!Directory.Exists(_rulesDir)) _rulesDir = Path.Combine(_projectRoot, ".opencode");
            if (!Directory.Exists(_rulesDir)) _rulesDir = Path.Combine(_projectRoot, "rules");
            Log("INFO", $"Rules dir: {_rulesDir}");
            LoadRules();
            BuildTabs("");
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg) { string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}"; try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { } }

        private void LoadRules()
        {
            _allRules.Clear();
            if (!Directory.Exists(_rulesDir))
            {
                Log("WARN", $"Rules dir not found: {_rulesDir}");
                _allRules.Add(new RuleFile { Name = "Нет правил", Content = $"Директория не найдена: {_rulesDir}", Category = "Ошибка" });
                return;
            }
            foreach (string f in Directory.GetFiles(_rulesDir, "*.mdc"))
            {
                string cat = "Основные";
                string name = Path.GetFileNameWithoutExtension(f);
                if (name.Contains('-'))
                {
                    var parts = name.Split('-', 2);
                    cat = parts[0];
                }
                string content = File.ReadAllText(f);
                _allRules.Add(new RuleFile { Name = name, Content = content, Category = cat });
                Log("INFO", $"Loaded rule: {name} ({cat})");
            }
            if (_allRules.Count == 0)
                _allRules.Add(new RuleFile { Name = "Нет правил", Content = $"Файлы .mdc не найдены в {_rulesDir}", Category = "Ошибка" });
        }

        private void BuildTabs(string filter)
        {
            tabControl.Items.Clear();
            _filteredRules.Clear();
            var groups = _allRules.Where(r => string.IsNullOrEmpty(filter) || r.Name.IndexOf(filter, StringComparison.OrdinalIgnoreCase) >= 0 || r.Content.IndexOf(filter, StringComparison.OrdinalIgnoreCase) >= 0).GroupBy(r => r.Category);

            foreach (var g in groups)
            {
                var ti = new TabItem { Header = $"{g.Key} ({g.Count()})" };
                var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Visible };
                var sp = new StackPanel { Margin = new Thickness(4) };
                foreach (var rule in g)
                {
                    var border = new Border
                    {
                        BorderBrush = Brushes.Gray,
                        BorderThickness = new Thickness(1),
                        CornerRadius = new CornerRadius(6),
                        Background = Brushes.White,
                        Margin = new Thickness(0, 0, 0, 6)
                    };
                    var innerSp = new StackPanel { Margin = new Thickness(6) };
                    var tbHeader = new TextBlock { Text = rule.Name, FontWeight = FontWeights.Bold, FontSize = 12, Foreground = Brushes.Navy };
                    var tbContent = new TextBlock { Text = rule.Content, FontSize = 10, TextWrapping = TextWrapping.Wrap, MaxHeight = 200 };
                    innerSp.Children.Add(tbHeader);
                    innerSp.Children.Add(tbContent);
                    border.Child = innerSp;
                    sp.Children.Add(border);
                }
                scroll.Content = sp;
                ti.Content = scroll;
                tabControl.Items.Add(ti);
            }
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
                        if (arg == "refresh") BtnRefresh_Click(null, null);
                        Log("AUTOTEST", $"click: {arg}"); break;
                    case "type": txtSearch.Text = arg; TxtSearch_TextChanged(null, null); break;
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

        private void TxtSearch_TextChanged(object sender, TextChangedEventArgs e) { Log("SEARCH", txtSearch.Text); BuildTabs(txtSearch.Text); }
        private void BtnClear_Click(object sender, RoutedEventArgs e) { txtSearch.Clear(); }
        private void BtnRefresh_Click(object sender, RoutedEventArgs e) { Log("CLICK", "refresh"); LoadRules(); BuildTabs(txtSearch.Text); }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (e.ClickCount == 2) { ToggleMaximize(); return; } try { DragMove(); } catch { } }
        private void ToggleMaximize() { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; }
        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; Log("CLICK", "min"); }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); Log("CLICK", "max"); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Log("CLICK", "close"); Close(); }
    }
}