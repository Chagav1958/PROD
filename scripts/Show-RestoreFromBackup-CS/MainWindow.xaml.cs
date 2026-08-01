using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace ShowRestoreFromBackup
{
    public class FileEntry
    {
        public string RelativePath { get; set; } = "";
        public string Status { get; set; } = "MISS";
        public string SourcePath { get; set; } = "";
        public string FullPath { get; set; } = "";
    }

    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")]
        private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);

        private const int WM_NCHITTEST = 0x0084;
        private const int HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14;
        private const int HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private string _projectRoot = ".";
        private List<FileEntry> _allFiles = new();
        private List<FileEntry> _filteredFiles = new();

        private static string _logPath = Path.Combine(
            Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".",
            $"tech_journal_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        private static readonly object _logLock = new();
        private static bool _exitAfterAutoTest = false;
        private static List<string> _autoTestCommands = new();
        private static int _autoTestCmdIndex = 0;

        private string[] _criticalFiles = new[]
        {
            "bin\\Show-TimeFIX.ps1", "bin\\Show-TimeFIX.vbs", "bin\\Show-TimeFIX.bat",
            "bin\\Prod-GUI.ps1", "bin\\Prod-GUI.bat", "bin\\OC-Config-Manager.ps1",
            "scripts\\Add-Bom.ps1", "scripts\\Add-Bom.bat", "scripts\\Fix-HexEncoding.ps1",
            "scripts\\Fix-HexEncoding.bat", "scripts\\Preflight-Antivirus.ps1",
            "scripts\\Preflight-Antivirus.bat", "scripts\\VSS-History-Show.ps1",
            "scripts\\VSS-History-Show.bat", "scripts\\VSS-History.ps1",
            "scripts\\ConvertTo-BatLauncher.ps1", "scripts\\ConvertTo-BatLauncher.bat",
            "scripts\\Init-Task.ps1", "scripts\\Init-Task.bat", "scripts\\Set-MetroTheme.ps1",
            "scripts\\Stells-HideConsole.ps1", "scripts\\Initialize-Project.ps1",
            "scripts\\TaskPlan-Manager.ps1", "scripts\\TaskPlan-Tracker.ps1",
            "scripts\\Show-TaskPlanGUI.ps1", "scripts\\Export-PB.ps1",
            "scripts\\Compare-Export.ps1", "scripts\\Compare-SQL-Task.ps1",
            "scripts\\Add-ReleaseComment.ps1", "scripts\\Save-UserPrompt.ps1",
            "scripts\\Save-Analysis.ps1", "scripts\\Save-Snapshot.ps1",
            "scripts\\Remove-BomFromConfigs.ps1",
            "scripts\\AIS_export.ps1", "scripts\\AIS_export.bat", "scripts\\Convert-Docs.ps1",
            "config\\config.json", "config\\vss_object_history.json", "config\\task_name_history.json"
        };

        private string[] _backupSourcePaths = new[]
        {
            "archives\\SNAPSHOT", "Restore", "Restore\\OLD",
            "archives\\FIX", "archives\\opencode_backup", "archives\\powershell_backup"
        };

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {System.Reflection.Assembly.GetExecutingAssembly().Location}");
            Log("INFO", $"Args: {string.Join(" | ", Environment.GetCommandLineArgs())}");
            LocateProjectRoot();
            ScanFiles();
            ParseAutoTestArgs();
        }

        private void LocateProjectRoot()
        {
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            if (File.Exists(Path.Combine(exeDir, "..\\..\\..\\opencode.jsonc")))
                _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\..\\"));
            else if (File.Exists(Path.Combine(exeDir, "..\\opencode.jsonc")))
                _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\"));
            else if (File.Exists(Path.Combine(exeDir, "opencode.jsonc")))
                _projectRoot = exeDir;
            else
                _projectRoot = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\"));
            Log("INFO", $"Project root: {_projectRoot}");
        }

        private void ParseAutoTestArgs()
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
                if (args[i] == "--autotest" && i + 1 < args.Length)
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

        private void RunAutoTestCommand()
        {
            if (_autoTestCmdIndex >= _autoTestCommands.Count) return;
            string line = _autoTestCommands[_autoTestCmdIndex++].Trim();
            if (string.IsNullOrEmpty(line)) { RunAutoTestCommand(); return; }
            Log("AUTOTEST", $"CMD[{_autoTestCmdIndex - 1}]: {line}");
            var parts = line.Split(' ', 3);
            string cmd = parts[0].ToLower();
            string arg = parts.Length > 1 ? parts[1] : "";
            try
            {
                switch (cmd)
                {
                    case "close": Close(); break;
                    case "click":
                        switch (arg)
                        {
                            case "restore_missing": BtnRestoreMissing_Click(this, new RoutedEventArgs()); break;
                            case "restore_all": BtnRestoreAll_Click(this, new RoutedEventArgs()); break;
                            case "cancel": BtnCancel_Click(this, new RoutedEventArgs()); break;
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

        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); } Console.WriteLine(line); } catch { }
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            Log("INFO", "Window loaded");
            ApplyRoundedRegion();
            BindData();
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
                if (w <= 0 || h <= 0) { w = 700; h = 520; }
                IntPtr hRgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, hRgn, true);
                DeleteObject(hRgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
        }

        private void ScanFiles()
        {
            _allFiles.Clear();
            foreach (string relPath in _criticalFiles)
            {
                string fullPath = Path.Combine(_projectRoot, relPath);
                string status = File.Exists(fullPath) ? "OK" : "MISS";
                string srcPath = "";
                if (status == "MISS")
                {
                    string found = FindInBackups(relPath);
                    if (found != null) srcPath = found;
                }
                _allFiles.Add(new FileEntry
                {
                    RelativePath = relPath,
                    Status = status,
                    SourcePath = srcPath,
                    FullPath = fullPath
                });
            }
            Log("INFO", $"Scanned {_allFiles.Count} files, missing: {_allFiles.Count(f => f.Status == "MISS")}");
        }

        private string FindInBackups(string relPath)
        {
            string fileName = Path.GetFileName(relPath);
            foreach (string srcRel in _backupSourcePaths)
            {
                string srcDir = Path.Combine(_projectRoot, srcRel);
                if (!Directory.Exists(srcDir)) continue;

                string exactPath = Path.Combine(srcDir, relPath);
                if (File.Exists(exactPath)) return exactPath;

                var found = Directory.GetFiles(srcDir, fileName, SearchOption.AllDirectories).FirstOrDefault();
                if (found != null) return found;
            }
            return "";
        }

        private void BindData()
        {
            ApplyFilter();
            UpdateSummary();
        }

        private void ApplyFilter()
        {
            string q = txtSearch.Text.ToLower();
            _filteredFiles = string.IsNullOrEmpty(q)
                ? new List<FileEntry>(_allFiles)
                : _allFiles.Where(f =>
                    f.RelativePath.ToLower().Contains(q) ||
                    f.Status.ToLower().Contains(q)).ToList();
            dgFiles.ItemsSource = null;
            dgFiles.ItemsSource = _filteredFiles;
        }

        private void UpdateSummary()
        {
            int total = _allFiles.Count;
            int miss = _allFiles.Count(f => f.Status == "MISS");
            int restored = _allFiles.Count(f => f.Status == "RESTORED");
            lblSummary.Text = $"Всего: {total} | Отсутствует: {miss} | Восстановлено: {restored}";
        }

        private void TxtSearch_TextChanged(object sender, TextChangedEventArgs e)
        {
            ApplyFilter();
        }

        private async void BtnRestoreMissing_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "restore_missing");
            await RestoreFiles(onlyMissing: true);
        }

        private async void BtnRestoreAll_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "restore_all");
            await RestoreFiles(onlyMissing: false);
        }

        private async System.Threading.Tasks.Task RestoreFiles(bool onlyMissing)
        {
            btnRestoreMissing.IsEnabled = false;
            btnRestoreAll.IsEnabled = false;

            var toRestore = _allFiles.Where(f =>
                !onlyMissing || f.Status == "MISS").ToList();

            if (toRestore.Count == 0)
            {
                lblSummary.Text = "Нет файлов для восстановления";
                btnRestoreMissing.IsEnabled = true;
                btnRestoreAll.IsEnabled = true;
                return;
            }

            pbRestore.Maximum = toRestore.Count;
            pbRestore.Value = 0;

            int restored = 0;
            int failed = 0;

            foreach (var file in toRestore)
            {
                bool success = await TryRestoreFile(file);
                if (success) restored++; else failed++;
                pbRestore.Value++;
                UpdateSummary();
                ApplyFilter();
            }

            Log("INFO", $"Restore complete: {restored} restored, {failed} failed");

            btnRestoreMissing.IsEnabled = true;
            btnRestoreAll.IsEnabled = true;

            string msg = $"Восстановлено: {restored}\nОшибок: {failed}";
            MessageBox.Show(msg, "Восстановление завершено",
                MessageBoxButton.OK, failed > 0 ? MessageBoxImage.Warning : MessageBoxImage.Information);
        }

        private System.Threading.Tasks.Task<bool> TryRestoreFile(FileEntry file)
        {
            return System.Threading.Tasks.Task.Run(() =>
            {
                try
                {
                    if (file.Status == "OK") return true;

                    string srcPath = FindInBackups(file.RelativePath);
                    if (string.IsNullOrEmpty(srcPath))
                    {
                        Log("ERROR", $"No backup found for {file.RelativePath}");
                        return false;
                    }

                    string destDir = Path.GetDirectoryName(file.FullPath) ?? "";
                    if (!string.IsNullOrEmpty(destDir) && !Directory.Exists(destDir))
                        Directory.CreateDirectory(destDir);

                    File.Copy(srcPath, file.FullPath, overwrite: true);
                    file.Status = "RESTORED";
                    file.SourcePath = srcPath;
                    Log("INFO", $"Restored: {file.RelativePath} from {srcPath}");
                    return true;
                }
                catch (Exception ex)
                {
                    Log("ERROR", $"Failed to restore {file.RelativePath}: {ex.Message}");
                    return false;
                }
            });
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
