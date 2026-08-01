using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace ShowRestoreDialog
{
    public class SnapshotInfo
    {
        public string Folder { get; set; } = "";
        public string Date { get; set; } = "";
        public string Label { get; set; } = "";
        public int Files { get; set; }
        public string Display => $"{Folder,-45} {Date,-18} {Files,3}ф  {Label}";
        public string FolderDate
        {
            get
            {
                var m = System.Text.RegularExpressions.Regex.Match(Folder, @"Snapshot_(\d{8}_\d{6})");
                return m.Success ? m.Groups[1].Value : "";
            }
        }
    }

    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")]
        private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);

        private const int WM_NCHITTEST = 0x0084;
        private const int HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14;
        private const int HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private List<SnapshotInfo> _snapshots = new();

        private static string _logPath = Path.Combine(
            Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".",
            $"tech_journal_{DateTime.Now:yyyyMMdd_HHmmss}.log");
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
            LoadSnapshots();
            ParseAutoTestArgs();
        }

        private void ParseAutoTestArgs()
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
            {
                if (args[i] == "--autotest")
                {
                    if (i + 1 < args.Length)
                    {
                        try
                        {
                            string file = args[i + 1];
                            if (File.Exists(file))
                            {
                                _autoTestCommands = File.ReadAllLines(file).ToList();
                                Log("AUTOTEST", $"Loaded {_autoTestCommands.Count} commands from {file}");
                                _exitAfterAutoTest = true;
                            }
                        }
                        catch (Exception ex) { Log("ERROR", $"Failed to load autotest file: {ex.Message}"); }
                    }
                }
            }
        }

        private void RunAutoTestCommand()
        {
            if (_autoTestCmdIndex >= _autoTestCommands.Count) return;
            string line = _autoTestCommands[_autoTestCmdIndex++].Trim();
            if (string.IsNullOrEmpty(line)) { RunAutoTestCommand(); return; }
            Log("AUTOTEST", $"CMD[{_autoTestCmdIndex - 1}]: {line}");
            var parts = line.Split(' ', 3);
            string cmd = parts[0].ToLower();
            string arg = parts.Length > 1 ? parts[1] : "";
            string val = parts.Length > 2 ? parts[2] : "";
            try
            {
                switch (cmd)
                {
                    case "close": Close(); break;
                    case "set_date": txtDate.Text = val; Log("AUTOTEST", $"date='{val}'"); break;
                    case "select_snapshot": SelectSnapshot(int.Parse(arg)); break;
                    case "click":
                        switch (arg)
                        {
                            case "restore": BtnRestore_Click(this, new RoutedEventArgs()); break;
                            case "cancel": BtnCancel_Click(this, new RoutedEventArgs()); break;
                            case "min": BtnMinimize_Click(this, new RoutedEventArgs()); break;
                            case "max": BtnMaximize_Click(this, new RoutedEventArgs()); break;
                            case "close": BtnClose_Click(this, new RoutedEventArgs()); break;
                        }
                        Log("AUTOTEST", $"click: {arg}");
                        break;
                    case "wait": Thread.Sleep(int.Parse(arg)); break;
                    case "log": Log("AUTOTEST", arg); break;
                    default: Log("AUTOTEST", $"Unknown: {cmd}"); break;
                }
            }
            catch (Exception ex) { Log("ERROR", $"CMD failed: {ex.Message}"); }
            if (_autoTestCmdIndex < _autoTestCommands.Count)
            {
                DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
                t.Tick += (s, e) => { t.Stop(); RunAutoTestCommand(); };
                t.Start();
            }
            else
            {
                Log("AUTOTEST", "All commands done");
                if (_exitAfterAutoTest)
                {
                    DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
                    t.Tick += (s, e) => { t.Stop(); Close(); };
                    t.Start();
                }
            }
        }

        private void SelectSnapshot(int index)
        {
            if (index >= 0 && index < lstSnapshots.Items.Count)
            {
                lstSnapshots.SelectedIndex = index;
                Log("AUTOTEST", $"selected snapshot {index}");
            }
        }

        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { }
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            Log("INFO", "Window loaded");
            ApplyRoundedRegion();
            BindSnapshots();
            if (_autoTestCommands.Count > 0)
            {
                DispatcherTimer t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
                t.Tick += (s, ev) => { t.Stop(); RunAutoTestCommand(); };
                t.Start();
            }
        }

        private void Window_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            ApplyRoundedRegion();
            Log("INFO", $"SizeChanged: {ActualWidth}x{ActualHeight}");
        }

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
                int x = (int)(lParam.ToInt64() & 0xFFFF);
                int y = (int)((lParam.ToInt64() >> 16) & 0xFFFF);
                Point p = PointFromScreen(new Point(x, y));
                double w = ActualWidth, h = ActualHeight;
                int m = RESIZE_MARGIN;
                bool onLeft = p.X < m, onRight = p.X > w - m, onTop = p.Y < m, onBottom = p.Y > h - m;
                bool inTitleBar = p.Y < 42;
                if (inTitleBar && !onTop && !onLeft && !onRight) { handled = true; return (IntPtr)HTCAPTION; }
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
                if (w <= 0 || h <= 0) { w = 580; h = 480; }
                IntPtr hRgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, hRgn, true);
                DeleteObject(hRgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
        }

        private void LoadSnapshots()
        {
            string projectRoot = Path.GetDirectoryName(Path.GetDirectoryName(
                Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".")) ?? ".";
            string archiveRoot = Path.Combine(projectRoot, "archives", "OpenCode");
            _snapshots.Clear();

            if (Directory.Exists(archiveRoot))
            {
                var dirs = Directory.GetDirectories(archiveRoot, "Snapshot_*")
                    .OrderByDescending(d => d);
                foreach (var dir in dirs)
                {
                    var di = new DirectoryInfo(dir);
                    string metaPath = Path.Combine(dir, "_meta.json");
                    string label = "";
                    if (File.Exists(metaPath))
                    {
                        try
                        {
                            var meta = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string>>(
                                File.ReadAllText(metaPath));
                            if (meta != null && meta.ContainsKey("label")) label = meta["label"];
                        }
                        catch { }
                    }
                    int fileCount = Directory.GetFiles(dir).Count(f => !Path.GetFileName(f).Equals("_meta.json"));
                    _snapshots.Add(new SnapshotInfo
                    {
                        Folder = di.Name,
                        Date = di.LastWriteTime.ToString("yyyy-MM-dd HH:mm"),
                        Label = label,
                        Files = fileCount
                    });
                }
            }
            Log("INFO", $"Loaded {_snapshots.Count} snapshots");
        }

        private void BindSnapshots()
        {
            lstSnapshots.ItemsSource = null;
            if (_snapshots.Count > 0)
            {
                lstSnapshots.ItemsSource = _snapshots;
                lstSnapshots.SelectedIndex = 0;
            }
            else
            {
                lstSnapshots.ItemsSource = new List<string> { "--- Нет снапшотов ---" };
            }
        }

        private void LstSnapshots_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (lstSnapshots.SelectedItem is SnapshotInfo si)
            {
                lblStatus.Text = $"Снапшот: {si.Folder} | {si.Date} | {si.Files} файлов";
                txtDate.Text = si.FolderDate;
            }
        }

        private void TxtDate_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter) { BtnRestore_Click(sender, e); e.Handled = true; }
        }

        private async void BtnRestore_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "restore");
            string dateParam = txtDate.Text.Trim();

            if (string.IsNullOrEmpty(dateParam) && lstSnapshots.SelectedItem is SnapshotInfo si)
            {
                dateParam = si.FolderDate;
            }

            if (string.IsNullOrEmpty(dateParam))
            {
                lblStatus.Text = "Ошибка: не указана дата снапшота";
                Log("ERROR", "No date specified");
                return;
            }

            btnRestore.IsEnabled = false;
            pbRestore.Value = 10;
            lblStatus.Text = "Восстановление...";

            try
            {
                string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
                string restoreScript = Path.Combine(exeDir, "Restore-OpenCode.ps1");
                if (!File.Exists(restoreScript))
                {
                    string projectRoot = Path.GetDirectoryName(exeDir) ?? ".";
                    restoreScript = Path.Combine(projectRoot, "scripts", "Restore-OpenCode.ps1");
                }

                if (!File.Exists(restoreScript))
                {
                    lblStatus.Text = "Ошибка: Restore-OpenCode.ps1 не найден";
                    Log("ERROR", $"Restore script not found: {restoreScript}");
                    pbRestore.Value = 0;
                    btnRestore.IsEnabled = true;
                    return;
                }

                pbRestore.Value = 30;
                lblStatus.Text = "Запуск Restore-OpenCode...";

                var psi = new ProcessStartInfo
                {
                    FileName = "powershell",
                    Arguments = $"-NoLogo -File \"{restoreScript}\" -Date \"{dateParam}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using var process = new Process { StartInfo = psi };
                process.Start();
                pbRestore.Value = 60;

                string output = await process.StandardOutput.ReadToEndAsync();
                string error = await process.StandardError.ReadToEndAsync();
                process.WaitForExit();

                pbRestore.Value = 90;
                Log("INFO", $"Restore exit code: {process.ExitCode}");

                string resultMsg = output;
                if (!string.IsNullOrEmpty(error)) resultMsg += "\n" + error;

                pbRestore.Value = 100;
                lblStatus.Text = process.ExitCode == 0 ? "Восстановление завершено" : "Ошибка при восстановлении";

                MessageBox.Show(resultMsg,
                    process.ExitCode == 0 ? "Восстановление завершено" : "Ошибка при восстановлении",
                    MessageBoxButton.OK,
                    process.ExitCode == 0 ? MessageBoxImage.Information : MessageBoxImage.Error);
            }
            catch (Exception ex)
            {
                Log("ERROR", $"Restore failed: {ex.Message}");
                lblStatus.Text = $"Ошибка: {ex.Message}";
                pbRestore.Value = 0;
            }
            finally
            {
                btnRestore.IsEnabled = true;
            }
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2) { ToggleMaximize(); return; }
            try { DragMove(); } catch (Exception ex) { Log("ERROR", $"DragMove: {ex.Message}"); }
        }

        private void ToggleMaximize()
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
            Log("INFO", $"Maximized: {WindowState == WindowState.Maximized}");
        }

        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; Log("CLICK", "min"); }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); Log("CLICK", "max"); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Log("CLICK", "close"); Close(); }
        private void BtnCancel_Click(object sender, RoutedEventArgs e) { Log("CLICK", "cancel"); Close(); }
    }
}
