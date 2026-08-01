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

namespace Show_TaskPlanGUI
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
        private string _taskPlanDir;

        public class ScriptItem { public string Name { get; set; } = ""; public string Description { get; set; } = ""; public string ScriptPath { get; set; } = ""; }

        private ObservableCollection<ScriptItem> _scripts = new();

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {System.Reflection.Assembly.GetExecutingAssembly().Location}");
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
            _taskPlanDir = Path.Combine(_projectRoot, "scripts", "Show-TaskPlan-CS");
            if (!Directory.Exists(_taskPlanDir)) _taskPlanDir = exeDir;
            BuildTabs();
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg) { string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}"; try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { } }

        private void BuildTabs()
        {
            tabControl.Items.Clear();
            AddScriptsTab();
            AddFilesTab();
        }

        private void AddScriptsTab()
        {
            _scripts.Clear();
            if (Directory.Exists(_taskPlanDir))
            {
                foreach (string f in Directory.GetFiles(_taskPlanDir, "*.ps1"))
                {
                    _scripts.Add(new ScriptItem { Name = Path.GetFileNameWithoutExtension(f), ScriptPath = f, Description = "PowerShell скрипт" });
                }
            }
            if (_scripts.Count == 0)
            {
                var ti = new TabItem { Header = "Скрипты" };
                ti.Content = new TextBlock { Text = "Скрипты не найдены", FontSize = 10, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(10) };
                tabControl.Items.Add(ti);
                return;
            }
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
            dg.Columns.Add(new DataGridTextColumn { Header = "Скрипт", Binding = new System.Windows.Data.Binding("Name"), Width = 200 });
            dg.Columns.Add(new DataGridTextColumn { Header = "Описание", Binding = new System.Windows.Data.Binding("Description"), Width = new System.Windows.Controls.DataGridLength(1, System.Windows.Controls.DataGridLengthUnitType.Star) });
            dg.ItemsSource = _scripts;
            var ti2 = new TabItem { Header = $"Скрипты ({_scripts.Count})" };
            ti2.Content = dg;
            tabControl.Items.Add(ti2);
        }

        private void AddFilesTab()
        {
            var files = new List<string>();
            if (Directory.Exists(_taskPlanDir))
                files.AddRange(Directory.GetFiles(_taskPlanDir).Select(f => new FileInfo(f).Name));
            if (files.Count == 0)
            {
                var ti = new TabItem { Header = "Файлы" };
                ti.Content = new TextBlock { Text = "Нет файлов", FontSize = 10, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(10) };
                tabControl.Items.Add(ti);
                return;
            }
            var lb = new ListBox { FontSize = 11, Background = System.Windows.Media.Brushes.White, BorderBrush = System.Windows.Media.Brushes.Gray };
            foreach (string f in files) lb.Items.Add(f);
            var ti2 = new TabItem { Header = $"Файлы ({files.Count})" };
            ti2.Content = lb;
            tabControl.Items.Add(ti2);
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
                        else if (arg == "run") BtnRun_Click(null, null);
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

        private async void BtnRun_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "run");
            if (tabControl.SelectedItem is TabItem ti && ti.Content is DataGrid dg && dg.SelectedItem is ScriptItem si)
            {
                Log("INFO", $"Running script: {si.ScriptPath}");
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell",
                    Arguments = $"-NoLogo -ExecutionPolicy Bypass -File \"{si.ScriptPath}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using var proc = Process.Start(psi);
                if (proc != null) await proc.WaitForExitAsync();
                Log("INFO", $"Script exit code: {proc?.ExitCode ?? -1}");
            }
            else
            {
                MessageBox.Show("Выберите скрипт в таблице", "Запуск", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void BtnRefresh_Click(object sender, RoutedEventArgs e) { Log("CLICK", "refresh"); BuildTabs(); }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (e.ClickCount == 2) { ToggleMaximize(); return; } try { DragMove(); } catch { } }
        private void ToggleMaximize() { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; }
        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; Log("CLICK", "min"); }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); Log("CLICK", "max"); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Log("CLICK", "close"); Close(); }
    }
}