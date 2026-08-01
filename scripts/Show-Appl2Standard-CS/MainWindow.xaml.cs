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
using System.Windows.Media;

namespace ShowAppl2Standard
{
    public class Row
    {
        public string Name { get; set; } = "";
        public string Type { get; set; } = "";
        public string Status { get; set; } = "";
        public string Desc { get; set; } = "";
    }

    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")]
        private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("user32.dll")]
        private static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int W, int H, bool bRepaint);
        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);
        [DllImport("dwmapi.dll")]
        private static extern int DwmExtendFrameIntoClientArea(IntPtr hWnd, ref MARGINS pMargins);

        [StructLayout(LayoutKind.Sequential)]
        private struct MARGINS { public int cxLeftWidth, cxRightWidth, cyTopHeight, cyBottomHeight; }

        private const int WM_NCHITTEST = 0x0084;
        private const int HTLEFT = 10;
        private const int HTRIGHT = 11;
        private const int HTTOP = 12;
        private const int HTTOPLEFT = 13;
        private const int HTTOPRIGHT = 14;
        private const int HTBOTTOM = 15;
        private const int HTBOTTOMLEFT = 16;
        private const int HTBOTTOMRIGHT = 17;
        private const int HTCAPTION = 2;
        private const int HTCLIENT = 1;
        private const int HTNOWHERE = 0;

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }

        private List<Row> _allData = new();
        private List<Row> _filteredData = new();
        private List<int> _searchResults = new();
        private int _searchIdx = -1;
        private string _lastQuery = "";
        private DispatcherTimer? _animTimer;
        private int _animTick = 0;
        private const int ANIM_TOTAL = 30;
        private string[] PHASES = { "Фаза 1: инициализация", "Фаза 2: обработка", "Фаза 3: финализация" };

        // Technical journal
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
            LoadData();
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
                case "set_text": SetFieldText("txt", val); break;
                case "set_pwd": SetFieldText("pwd", val); break;
                case "set_search": SetFieldText("search", val); break;
                case "search_down": BtnSearchDown_Click(this, new RoutedEventArgs()); Log("AUTOTEST", "search_down"); break;
                case "search_up": BtnSearchUp_Click(this, new RoutedEventArgs()); Log("AUTOTEST", "search_up"); break;
                case "click": DoClick(arg); break;
                case "move": DoMove(arg); break;
                case "resize": DoResize(arg); break;
                case "scroll": DoScroll(arg); break;
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

        private void SetFieldText(string which, string val)
        {
            switch (which)
            {
                case "txt": txtField.Text = val; Log("AUTOTEST", $"txtField='{val}'"); break;
                case "pwd": pwdField.Password = val; Log("AUTOTEST", $"pwdField='{val}'"); break;
                case "search": txtSearch.Text = val; Log("AUTOTEST", $"txtSearch='{val}'"); break;
            }
        }

        private void DoClick(string which)
        {
            switch (which)
            {
                case "ok": BtnOk_Click(this, new RoutedEventArgs()); break;
                case "cancel": BtnCancel_Click(this, new RoutedEventArgs()); break;
                case "search_down": BtnSearchDown_Click(this, new RoutedEventArgs()); break;
                case "search_up": BtnSearchUp_Click(this, new RoutedEventArgs()); break;
                case "searchdown": BtnSearchDown_Click(this, new RoutedEventArgs()); break;
                case "searchup": BtnSearchUp_Click(this, new RoutedEventArgs()); break;
                case "min": BtnMinimize_Click(this, new RoutedEventArgs()); break;
                case "max": BtnMaximize_Click(this, new RoutedEventArgs()); break;
                case "close": BtnClose_Click(this, new RoutedEventArgs()); break;
            }
            Log("AUTOTEST", $"click: {which}");
        }

        private void DoMove(string arg)
        {
            var p = arg.Split(',');
            if (p.Length == 2 && int.TryParse(p[0], out int x) && int.TryParse(p[1], out int y))
            {
                Left = x; Top = y;
                Log("AUTOTEST", $"moved to ({x},{y})");
            }
        }

        private void DoResize(string arg)
        {
            var p = arg.Split(',');
            if (p.Length == 2 && int.TryParse(p[0], out int w) && int.TryParse(p[1], out int h))
            {
                Width = w; Height = h;
                Log("AUTOTEST", $"resized to {w}x{h}");
            }
        }

        private void DoScroll(string arg)
        {
            var p = arg.Split(',');
            if (p.Length == 2 && dgData.Items.Count > 0)
            {
                int row = int.Parse(p[0]);
                int idx = Math.Min(row, dgData.Items.Count - 1);
                if (idx >= 0) { dgData.ScrollIntoView(dgData.Items[idx]); }
                Log("AUTOTEST", $"scrolled to row {idx}");
            }
        }

        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            try
            {
                lock (_logLock)
                {
                    File.AppendAllText(_logPath, line + Environment.NewLine);
                }
                Console.WriteLine(line);
            }
            catch { }
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            Log("INFO", "Window loaded");
            ApplyData();
            ApplyRoundedRegion();
            EnableNativeShadow();
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

        private const int RESIZE_MARGIN = 8;

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            HwndSource source = PresentationSource.FromVisual(this) as HwndSource;
            if (source != null)
            {
                source.AddHook(WndProc);
            }
        }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_NCHITTEST)
            {
                int x = (int)(lParam.ToInt64() & 0xFFFF);
                int y = (int)((lParam.ToInt64() >> 16) & 0xFFFF);
                Point p = PointFromScreen(new Point(x, y));
                double w = ActualWidth;
                double h = ActualHeight;
                int m = RESIZE_MARGIN;
                bool onLeft = p.X < m;
                bool onRight = p.X > w - m;
                bool onTop = p.Y < m;
                bool onBottom = p.Y > h - m;
                bool inTitleBar = p.Y < 42;

                if (inTitleBar && !onTop && !onLeft && !onRight)
                {
                    handled = true;
                    return (IntPtr)HTCAPTION;
                }
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

        private void EnableNativeShadow()
        {
            try
            {
                IntPtr hWnd = new WindowInteropHelper(this).Handle;
                if (hWnd == IntPtr.Zero) return;
                MARGINS margins = new MARGINS { cxLeftWidth = 0, cxRightWidth = 0, cyTopHeight = 0, cyBottomHeight = 0 };
                DwmExtendFrameIntoClientArea(hWnd, ref margins);
                Log("INFO", "Native DWM shadow enabled");
            }
            catch (Exception ex) { Log("ERROR", $"EnableNativeShadow: {ex.Message}"); }
        }

        private void ApplyRoundedRegion()
        {
            try
            {
                IntPtr hWnd = new WindowInteropHelper(this).Handle;
                if (hWnd == IntPtr.Zero) return;
                int w = (int)ActualWidth;
                int h = (int)ActualHeight;
                if (w <= 0 || h <= 0) { w = 520; h = 580; }
                IntPtr hRgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, hRgn, true);
                DeleteObject(hRgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
        }

        private void LoadData()
        {
            _allData = new List<Row>
            {
                new Row { Name = "w_ais_request_select", Type = "Window", Status = "READY", Desc = "Окно выбора заявок — ожидает выгрузки" },
                new Row { Name = "w_ais_request_card", Type = "Window", Status = "NOT_READY", Desc = "Карточка заявки — требуется доработка" },
                new Row { Name = "u_em_ais_rs", Type = "UserObject", Status = "READY", Desc = "Пользовательский объект для работы с заявками" },
                new Row { Name = "d_ais_request_list", Type = "DataWindow", Status = "NOT_READY", Desc = "Список заявок — ожидает выверки" },
                new Row { Name = "f_get_client_requests", Type = "Function", Status = "READY", Desc = "Функция получения заявок клиента" },
                new Row { Name = "p_create_request", Type = "Procedure", Status = "DIFF", Desc = "Процедура создания заявки — есть отличия" },
                new Row { Name = "tr_request_after_insert", Type = "Trigger", Status = "READY", Desc = "Триггер после вставки заявки" },
                new Row { Name = "w_ais_request_edit", Type = "Window", Status = "NEW_OBJECT", Desc = "Новое окно редактирования заявки" }
            };
            Log("INFO", $"Loaded {_allData.Count} rows");
        }

        private void ApplyData()
        {
            _filteredData = new List<Row>(_allData);
            dgData.ItemsSource = _filteredData;
            Log("INFO", "Data bound to DataGrid");
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

        private void BtnOk_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "ok - starting animation");
            btnOk.IsEnabled = false;
            pbPhase.Value = 0; pbStep.Value = 0;
            lblPhase.Text = "Фаза 1: инициализация"; lblStep.Text = "(0 - 5)";
            _animTick = 0;
            _animTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
            _animTimer.Tick += AnimTick;
            _animTimer.Start();
        }

        private void AnimTick(object? sender, EventArgs e)
        {
            _animTick++;
            int pct = Math.Min(100, (int)(_animTick / (double)ANIM_TOTAL * 100));
            int phaseIdx = Math.Min(2, _animTick / 10);
            lblPhase.Text = PHASES[phaseIdx];
            pbPhase.Value = pct;
            lblStep.Text = $"({_animTick} из {ANIM_TOTAL})";
            pbStep.Value = Math.Min(100, (_animTick % 10) * 10);
            if (_animTick >= ANIM_TOTAL)
            {
                _animTimer?.Stop();
                lblPhase.Text = "Готово"; lblStep.Text = "Завершено";
                pbPhase.Value = 100; pbStep.Value = 100;
                btnOk.IsEnabled = true;
                Log("INFO", "Animation done");
            }
        }

        private void TxtSearch_TextChanged(object sender, TextChangedEventArgs e)
        {
            string q = txtSearch.Text;
            if (q == _lastQuery) return;
            _lastQuery = q;
            _searchResults.Clear(); _searchIdx = -1;
            _filteredData = string.IsNullOrEmpty(q)
                ? new List<Row>(_allData)
                : _allData.Where(r =>
                    r.Name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ||
                    r.Type.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ||
                    r.Status.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ||
                    r.Desc.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0).ToList();
            dgData.ItemsSource = null;
            dgData.ItemsSource = _filteredData;
            lblMatch.Text = $"0 - 0";
            Log("INFO", $"Search '{q}' -> {_filteredData.Count} rows");
        }

        private void TxtSearch_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter) { BtnSearchDown_Click(sender, e); e.Handled = true; }
        }

        private void BtnSearchDown_Click(object sender, RoutedEventArgs e)
        {
            string q = txtSearch.Text;
            if (string.IsNullOrEmpty(q)) return;
            if (_searchResults.Count != _filteredData.Count || q != _lastQuery)
            {
                _searchResults = Enumerable.Range(0, _filteredData.Count)
                    .Where(i => Matches(_filteredData[i], q)).ToList();
                _searchIdx = -1;
            }
            if (_searchResults.Count == 0) { lblMatch.Text = "0 - 0"; return; }
            _searchIdx = (_searchIdx + 1) % _searchResults.Count;
            int rowIdx = _searchResults[_searchIdx];
            dgData.SelectedIndex = rowIdx;
            dgData.ScrollIntoView(dgData.Items[rowIdx]);
            lblMatch.Text = $"{_searchIdx + 1} - {_searchResults.Count}";
            Log("CLICK", $"search_down idx={rowIdx}");
        }

        private void BtnSearchUp_Click(object sender, RoutedEventArgs e)
        {
            string q = txtSearch.Text;
            if (string.IsNullOrEmpty(q)) return;
            if (_searchResults.Count == 0) { BtnSearchDown_Click(sender, e); return; }
            _searchIdx = (_searchIdx - 1 + _searchResults.Count) % _searchResults.Count;
            int rowIdx = _searchResults[_searchIdx];
            dgData.SelectedIndex = rowIdx;
            dgData.ScrollIntoView(dgData.Items[rowIdx]);
            lblMatch.Text = $"{_searchIdx + 1} - {_searchResults.Count}";
            Log("CLICK", $"search_up idx={rowIdx}");
        }

        private static bool Matches(Row r, string q)
        {
            return r.Name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ||
                   r.Type.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ||
                   r.Status.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0 ||
                   r.Desc.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
        }
    }
}
