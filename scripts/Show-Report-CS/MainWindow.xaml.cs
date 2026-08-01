using System;
using System.Collections.Generic;
using System.Diagnostics;
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
using System.Windows.Threading;

namespace Show_Report
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

        public class FileEntry { public string File { get; set; } = ""; public string Ext { get; set; } = ""; public string Size { get; set; } = ""; }

        private string _taskName;
        private string _projectRoot;
        private string _taskPath;
        private List<FileEntry> _changedFiles = new();
        private List<FileEntry> _structureFiles = new();
        private string _releaseRoot = @"C:\AIS\1 Release";
        private string _layoutFile;

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {System.Reflection.Assembly.GetExecutingAssembly().Location}");
            Log("INFO", $"Args: {string.Join(" | ", Environment.GetCommandLineArgs())}");
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
            _layoutFile = Path.Combine(_projectRoot, "config", "report_layout.json");
            var args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
                if (!args[i].StartsWith("--")) _taskName = args[i];
            if (!string.IsNullOrEmpty(_taskName)) FindTask();
            if (_taskPath != null) ScanTask();
            BuildTabs();
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg) { string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}"; try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { } }

        private void FindTask()
        {
            if (string.IsNullOrEmpty(_taskName)) return;
            string dir = Path.Combine(_releaseRoot, _taskName);
            if (Directory.Exists(dir)) { _taskPath = dir; return; }
            if (Directory.Exists(_releaseRoot))
                _taskPath = Directory.GetDirectories(_releaseRoot)
                    .Where(d => Path.GetFileName(d).StartsWith(_taskName) || Path.GetFileName(d) == _taskName)
                    .OrderByDescending(d => Directory.GetCreationTime(d))
                    .FirstOrDefault();
        }

        private void ScanTask()
        {
            if (string.IsNullOrEmpty(_taskPath)) return;
            foreach (string f in Directory.GetFiles(_taskPath, "*", SearchOption.AllDirectories))
            {
                string rel = Path.GetRelativePath(_taskPath, f);
                string ext = Path.GetExtension(f);
                var fi = new FileInfo(f);
                var entry = new FileEntry { File = rel, Ext = ext, Size = FormatSize(fi.Length) };
                _structureFiles.Add(entry);
                if (ext == ".sr?" || f.EndsWith(".sr?")) _changedFiles.Add(entry);
            }
            Log("INFO", $"Scanned {_structureFiles.Count} files, changed: {_changedFiles.Count}");
        }

        private string FormatSize(long bytes) => bytes < 1024 ? $"{bytes} B" : bytes < 1024 * 1024 ? $"{bytes / 1024.0:F1} KB" : $"{bytes / 1024.0 / 1024.0:F2} MB";

        private void BuildTabs()
        {
            tabControl.Items.Clear();
            if (string.IsNullOrEmpty(_taskPath))
            {
                var tb = new TextBlock { Text = $"Задача '{_taskName}' не найдена в {_releaseRoot}", FontSize = 10, Foreground = System.Windows.Media.Brushes.Red };
                var ti = new TabItem { Header = "Ошибка" }; ti.Content = tb; tabControl.Items.Add(ti);
                return;
            }
            AddTab("Изменённые объекты", _changedFiles);
            AddTab("Структура задачи", _structureFiles);
            RestoreGeometry();
        }

        private void AddTab(string header, List<FileEntry> items)
        {
            var ti = new TabItem { Header = $"{header} ({items.Count})" };
            if (items.Count == 0)
            {
                ti.Content = new TextBlock { Text = "Нет данных", FontSize = 10, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(10) };
            }
            else
            {
                var dg = new DataGrid
                {
                    AutoGenerateColumns = false, IsReadOnly = true, RowHeaderWidth = 0,
                    AlternatingRowBackground = System.Windows.Media.Brushes.LightGray,
                    FontSize = 11, VerticalScrollBarVisibility = ScrollBarVisibility.Visible,
                    Background = System.Windows.Media.Brushes.Transparent,
                    RowBackground = System.Windows.Media.Brushes.White,
                    BorderBrush = System.Windows.Media.Brushes.Gray, BorderThickness = new Thickness(1),
                    CanUserResizeRows = false, GridLinesVisibility = DataGridGridLinesVisibility.None,
                    SelectionMode = DataGridSelectionMode.Single, SelectionUnit = DataGridSelectionUnit.FullRow
                };
                dg.Columns.Add(new DataGridTextColumn { Header = "Файл", Binding = new System.Windows.Data.Binding("File"), Width = 500 });
                dg.Columns.Add(new DataGridTextColumn { Header = "Тип", Binding = new System.Windows.Data.Binding("Ext"), Width = 60 });
                dg.Columns.Add(new DataGridTextColumn { Header = "Размер", Binding = new System.Windows.Data.Binding("Size"), Width = 100 });
                dg.ItemsSource = items;
                ti.Content = dg;
            }
            tabControl.Items.Add(ti);
        }

        private void RestoreGeometry()
        {
            if (!File.Exists(_layoutFile)) return;
            try
            {
                var json = File.ReadAllText(_layoutFile);
                using var doc = JsonDocument.Parse(json);
                var r = doc.RootElement;
                if (r.TryGetProperty("Width", out var w) && w.GetInt32() >= 400 && r.TryGetProperty("Height", out var h) && h.GetInt32() >= 300)
                {
                    Width = w.GetInt32(); Height = h.GetInt32();
                    if (r.TryGetProperty("Left", out var l) && r.TryGetProperty("Top", out var t))
                    { WindowStartupLocation = WindowStartupLocation.Manual; Left = l.GetInt32(); Top = t.GetInt32(); }
                }
            }
            catch { }
        }

        private void SaveGeometry()
        {
            try
            {
                var lay = new { Width = (int)Width, Height = (int)Height, Left = (int)Left, Top = (int)Top };
                File.WriteAllText(_layoutFile, JsonSerializer.Serialize(lay));
            }
            catch { }
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
                        if (arg == "archive") BtnArchive_Click(this, new RoutedEventArgs());
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
                if (_exitAfterAutoTest) { DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, e) => { t.Stop(); Close(); }; t.Start(); }
            }
        }

        private void Window_Loaded(object sender, RoutedEventArgs e) { Log("INFO", "Window loaded"); ApplyRoundedRegion(); if (_autoTestCommands.Count > 0) { DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, ev) => { t.Stop(); RunAutoTestCommand(); }; t.Start(); } }
        private void Window_SizeChanged(object sender, SizeChangedEventArgs e) { ApplyRoundedRegion(); Log("INFO", $"SizeChanged: {ActualWidth}x{ActualHeight}"); }
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

        private async void BtnArchive_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "archive");
            if (string.IsNullOrEmpty(_taskPath)) return;
            string ts = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            string dest = Path.Combine(_projectRoot, "archives", "REPORT", $"{_taskName}_{ts}");
            try
            {
                Directory.CreateDirectory(dest);
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell",
                    Arguments = $"-NoLogo -Command \"Copy-Item '{_taskPath}\\*' -Destination '{dest}' -Recurse -Force\"",
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using var proc = Process.Start(psi);
                if (proc != null) await proc.WaitForExitAsync();
                Log("INFO", $"Archive created: {dest}");
                MessageBox.Show($"Архив создан:\n{dest}", "Архив", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex) { Log("ERROR", $"Archive: {ex.Message}"); MessageBox.Show(ex.Message, "Ошибка", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (e.ClickCount == 2) { ToggleMaximize(); return; } try { DragMove(); } catch (Exception ex) { Log("ERROR", $"DragMove: {ex.Message}"); } }
        private void ToggleMaximize() { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; Log("INFO", $"Maximized: {WindowState == WindowState.Maximized}"); }
        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; Log("CLICK", "min"); }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); Log("CLICK", "max"); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { SaveGeometry(); Log("CLICK", "close"); Close(); }
        private void BtnCancel_Click(object sender, RoutedEventArgs e) { Log("CLICK", "cancel"); Close(); }
        private void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e) { SaveGeometry(); }
    }
}