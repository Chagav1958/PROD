using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace Show_OpStatus
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
        private string _statusFilePath;

        public class StatusEntry
        {
            public string ObjectName { get; set; } = "";
            public string Status { get; set; } = "";
            public string Comment { get; set; } = "";
            public string Timestamp { get; set; } = "";
            public List<StatusEntry> Children { get; set; } = new();
        }

        private ObservableCollection<StatusEntry> _entries = new();

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {System.Reflection.Assembly.GetExecutingAssembly().Location}");
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
            _statusFilePath = Path.Combine(_projectRoot, "config", "operation_status.json");
            if (!File.Exists(_statusFilePath))
            {
                _statusFilePath = Path.Combine(_projectRoot, "operation_status.json");
                if (!File.Exists(_statusFilePath))
                    _statusFilePath = null;
            }
            Log("INFO", $"Status file: {_statusFilePath ?? "NOT FOUND"}");
            LoadStatus();
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg) { string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}"; try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { } }

        private void LoadStatus()
        {
            _entries.Clear();
            treeView.Items.Clear();
            if (_statusFilePath == null || !File.Exists(_statusFilePath))
            {
                txtStatus.Text = "Файл статуса не найден";
                return;
            }
            try
            {
                string json = File.ReadAllText(_statusFilePath);
                using var doc = JsonDocument.Parse(json);
                ParseJson(doc.RootElement, null);
                txtStatus.Text = $"Объектов: {_entries.Count}";
                BuildTree();
                Log("INFO", $"Loaded {_entries.Count} entries");
            }
            catch (Exception ex) { Log("ERROR", $"LoadStatus: {ex.Message}"); txtStatus.Text = $"Ошибка загрузки: {ex.Message}"; }
        }

        private void ParseJson(JsonElement el, StatusEntry parent)
        {
            if (el.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in el.EnumerateArray()) ParseJson(item, parent);
            }
            else if (el.ValueKind == JsonValueKind.Object)
            {
                var entry = new StatusEntry();
                if (el.TryGetProperty("name", out var n)) entry.ObjectName = n.GetString() ?? "";
                if (el.TryGetProperty("status", out var s)) entry.Status = s.GetString() ?? "";
                if (el.TryGetProperty("comment", out var c)) entry.Comment = c.GetString() ?? "";
                if (el.TryGetProperty("timestamp", out var t)) entry.Timestamp = t.GetString() ?? "";
                if (parent != null) parent.Children.Add(entry);
                else _entries.Add(entry);
                foreach (var prop in el.EnumerateObject())
                {
                    if (prop.Name == "children" || prop.Name == "objects" || prop.Name == "items")
                        ParseJson(prop.Value, entry);
                }
            }
        }

        private void BuildTree()
        {
            treeView.Items.Clear();
            foreach (var entry in _entries)
            {
                var item = CreateTreeItem(entry);
                treeView.Items.Add(item);
            }
        }

        private TreeViewItem CreateTreeItem(StatusEntry entry)
        {
            var viewItem = new TreeViewItem();
            var sp = new StackPanel { Orientation = Orientation.Horizontal };
            var tb1 = new TextBlock { Text = entry.ObjectName, FontWeight = FontWeights.Bold, FontSize = 11 };
            var tb2 = new TextBlock { Text = $" [{entry.Status}]", FontSize = 10, Foreground = GetStatusColor(entry.Status) };
            sp.Children.Add(tb1); sp.Children.Add(tb2);
            viewItem.Header = sp;
            foreach (var child in entry.Children)
                viewItem.Items.Add(CreateTreeItem(child));
            viewItem.IsExpanded = true;
            viewItem.Selected += (s, e) => txtDetails.Text = $"{entry.ObjectName}: {entry.Status} | {entry.Comment} | {entry.Timestamp}";
            return viewItem;
        }

        private Brush GetStatusColor(string status) => status?.ToLower() switch
        {
            "ok" or "done" or "fixed" => Brushes.Green,
            "fix" or "wip" => Brushes.OrangeRed,
            "error" or "fail" => Brushes.Red,
            "skip" => Brushes.Gray,
            _ => Brushes.Black
        };

        private void SaveStatus()
        {
            if (_statusFilePath == null) return;
            try
            {
                var list = new List<object>();
                foreach (var entry in _entries) list.Add(SerializeEntry(entry));
                string json = JsonSerializer.Serialize(list, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_statusFilePath, json);
                Log("INFO", "Status saved");
            }
            catch (Exception ex) { Log("ERROR", $"SaveStatus: {ex.Message}"); }
        }

        private object SerializeEntry(StatusEntry entry)
        {
            var dict = new Dictionary<string, object> { ["name"] = entry.ObjectName, ["status"] = entry.Status, ["comment"] = entry.Comment, ["timestamp"] = entry.Timestamp };
            if (entry.Children.Count > 0)
            {
                var children = new List<object>();
                foreach (var c in entry.Children) children.Add(SerializeEntry(c));
                dict["children"] = children;
            }
            return dict;
        }

        private void UpdateSelectedStatus(string newStatus)
        {
            if (treeView.SelectedItem is TreeViewItem sel && sel.Header is StackPanel sp && sp.Children[0] is TextBlock tb)
            {
                string name = tb.Text;
                var entry = FindEntry(_entries, name);
                if (entry != null)
                {
                    entry.Status = newStatus;
                    entry.Timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                    if (sp.Children.Count > 1 && sp.Children[1] is TextBlock tb2)
                    {
                        tb2.Text = $" [{newStatus}]";
                        tb2.Foreground = GetStatusColor(newStatus);
                    }
                    SaveStatus();
                    Log("INFO", $"Status updated: {name} -> {newStatus}");
                }
            }
            else { MessageBox.Show("Выберите объект в дереве", "Статус", MessageBoxButton.OK, MessageBoxImage.Information); }
        }

        private StatusEntry FindEntry(IEnumerable<StatusEntry> entries, string name)
        {
            foreach (var e in entries)
            {
                if (e.ObjectName == name) return e;
                var found = FindEntry(e.Children, name);
                if (found != null) return found;
            }
            return null;
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
                        if (arg == "fix") BtnFIX_Click(null, null);
                        else if (arg == "fixed") BtnFIXED_Click(null, null);
                        else if (arg == "edit") BtnEDIT_Click(null, null);
                        else if (arg == "refresh") BtnRefresh_Click(null, null);
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

        private void BtnRefresh_Click(object sender, RoutedEventArgs e) { Log("CLICK", "refresh"); LoadStatus(); }
        private void BtnFIX_Click(object sender, RoutedEventArgs e) { Log("CLICK", "fix"); UpdateSelectedStatus("FIX"); }
        private void BtnFIXED_Click(object sender, RoutedEventArgs e) { Log("CLICK", "fixed"); UpdateSelectedStatus("FIXED"); }
        private void BtnEDIT_Click(object sender, RoutedEventArgs e) { Log("CLICK", "edit"); UpdateSelectedStatus("EDIT"); }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (e.ClickCount == 2) { ToggleMaximize(); return; } try { DragMove(); } catch { } }
        private void ToggleMaximize() { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; }
        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; Log("CLICK", "min"); }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); Log("CLICK", "max"); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Log("CLICK", "close"); Close(); }
        private void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e) { }
    }
}