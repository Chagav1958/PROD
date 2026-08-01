using System;
using System.Collections.Generic;
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

namespace Show_Abbreviations
{
    public class TabData
    {
        public string Header { get; set; } = "";
        public List<string> Headers { get; set; } = new();
        public List<string> Columns { get; set; } = new();
        public List<Dictionary<string, object>> Data { get; set; } = new();
    }

    public class TreeTabInfo
    {
        public DataGrid Grid { get; set; }
        public List<string[]> Items { get; set; } = new();
        public string Name { get; set; } = "";
    }

    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);

        private const int WM_NCHITTEST = 0x0084, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private List<TreeTabInfo> _trees = new();
        private List<TabData> _tabsData = new();
        private string _projectRoot;

        private string _searchQuery = "";
        private List<(int ti, object item)> _searchResults = new();
        private int _searchIdx = -1;

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
            LoadData();
            BuildTabs();
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

        private void LoadData()
        {
            string jp = Path.Combine(_projectRoot, "config", "abbreviations_data.json");
            if (!File.Exists(jp)) { Log("ERROR", "abbreviations_data.json not found"); return; }
            try
            {
                string json = File.ReadAllText(jp);
                _tabsData = JsonSerializer.Deserialize<List<TabData>>(json) ?? new List<TabData>();
                Log("INFO", $"Loaded {_tabsData.Count} tabs");
            }
            catch (Exception ex) { Log("ERROR", $"LoadData: {ex.Message}"); }
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
                        if (arg == "down") BtnSearchDown_Click(this, new RoutedEventArgs());
                        else if (arg == "up") BtnSearchUp_Click(this, new RoutedEventArgs());
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
                if (w <= 0 || h <= 0) { w = 900; h = 600; }
                IntPtr hRgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, hRgn, true);
                DeleteObject(hRgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
        }

        private void BuildTabs()
        {
            tabControl.Items.Clear();
            _trees.Clear();
            foreach (var tab in _tabsData)
            {
                var tabItem = new TabItem { Header = $"{tab.Header} ({tab.Data.Count})" };
                var grid = new DataGrid
                {
                    AutoGenerateColumns = false,
                    IsReadOnly = true,
                    HeadersVisibility = DataGridHeadersVisibility.Column,
                    RowHeaderWidth = 0,
                    AlternatingRowBackground = System.Windows.Media.Brushes.LightGray,
                    FontSize = 11,
                    VerticalScrollBarVisibility = ScrollBarVisibility.Visible,
                    HorizontalScrollBarVisibility = ScrollBarVisibility.Visible,
                    Background = System.Windows.Media.Brushes.Transparent,
                    RowBackground = System.Windows.Media.Brushes.White,
                    BorderBrush = System.Windows.Media.Brushes.Gray,
                    BorderThickness = new Thickness(1),
                    CanUserResizeRows = false,
                    GridLinesVisibility = DataGridGridLinesVisibility.None,
                    SelectionMode = DataGridSelectionMode.Single,
                    SelectionUnit = DataGridSelectionUnit.FullRow
                };
                foreach (int ci in tab.Headers.Select((h, i) => i))
                {
                    string h = tab.Headers[ci];
                    grid.Columns.Add(new DataGridTextColumn
                    {
                        Header = h,
                        Binding = new System.Windows.Data.Binding($"[{ci}]"),
                        Width = 120
                    });
                }
                var items = new List<string[]>();
                foreach (var row in tab.Data)
                {
                    items.Add(tab.Columns.Select(c => row.TryGetValue(c, out object v) ? v?.ToString() ?? "" : "").ToArray());
                }
                PopulateGrid(grid, items);
                tabItem.Content = grid;
                tabControl.Items.Add(tabItem);
                _trees.Add(new TreeTabInfo { Grid = grid, Items = items, Name = tab.Header });
            }
        }

        private void PopulateGrid(DataGrid grid, List<string[]> items)
        {
            grid.ItemsSource = null;
            grid.ItemsSource = items.Select(arr => arr.Select(s => s as object).ToArray()).ToList();
        }

        private void TxtSearch_TextChanged(object sender, TextChangedEventArgs e)
        {
            string q = txtSearch.Text.ToLower();
            _searchQuery = q;
            _searchResults.Clear();
            _searchIdx = -1;
            int total = 0;
            foreach (var ti in _trees)
            {
                if (string.IsNullOrEmpty(q))
                {
                    PopulateGrid(ti.Grid, ti.Items);
                    total += ti.Items.Count;
                }
                else
                {
                    var filtered = ti.Items.Where(r => r.Any(v => v.ToLower().Contains(q))).ToList();
                    PopulateGrid(ti.Grid, filtered);
                    total += filtered.Count;
                }
            }
            lblMatch.Text = total.ToString();
        }

        private void BtnSearchDown_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrEmpty(_searchQuery)) return;
            int ti = tabControl.SelectedIndex;
            if (ti < 0) ti = 0;
            if (_searchResults.Count == 0 || _searchIdx < 0)
            {
                _searchResults.Clear();
                _searchIdx = -1;
                for (int t = 0; t < _trees.Count; t++)
                {
                    var grid = _trees[t].Grid;
                    foreach (var item in grid.ItemsSource as System.Collections.IList)
                    {
                        var arr = item as object[];
                        if (arr != null && arr.Any(v => v?.ToString()?.ToLower().Contains(_searchQuery) == true))
                        {
                            _searchResults.Add((t, item));
                        }
                    }
                }
            }
            if (_searchResults.Count == 0) return;
            _searchIdx = (_searchIdx + 1) % _searchResults.Count;
            var hit = _searchResults[_searchIdx];
            tabControl.SelectedIndex = hit.ti;
            var tgtGrid = _trees[hit.ti].Grid;
            tgtGrid.SelectedItem = hit.item;
            tgtGrid.ScrollIntoView(hit.item);
            lblMatch.Text = $"{_searchIdx + 1}/{_searchResults.Count}";
        }

        private void BtnSearchUp_Click(object sender, RoutedEventArgs e)
        {
            if (string.IsNullOrEmpty(_searchQuery) || _searchResults.Count == 0) return;
            _searchIdx = (_searchIdx - 1 + _searchResults.Count) % _searchResults.Count;
            var hit = _searchResults[_searchIdx];
            tabControl.SelectedIndex = hit.ti;
            var tgtGrid = _trees[hit.ti].Grid;
            tgtGrid.SelectedItem = hit.item;
            tgtGrid.ScrollIntoView(hit.item);
            lblMatch.Text = $"{_searchIdx + 1}/{_searchResults.Count}";
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