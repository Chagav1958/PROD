using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace Show_TimeFIX
{
    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int nLeft, int nTop, int nRight, int nBottom, int nWidth, int nHeight);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
        private const int WM_NCHITTEST = 0x0084, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private static string _logPath = Path.Combine(
            Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".",
            $"tech_journal_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        private static readonly object _logLock = new();
        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); }
            Console.WriteLine(line);
        }

        private DateTime _currentWeekStart;
        private EwsService _ews = new();
        private List<CalendarEntryEx> _events = new();
        private HashSet<string> _confirmed = new();

        private readonly string[] _dayNames = { "Пн", "Вт", "Ср", "Чт", "Пт" };
        private readonly string[] _months = { "янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек" };
        private const int HourStart = 8, HourEnd = 19, HourHeight = 65;

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window start");
            _currentWeekStart = GetWeekStart(DateTime.Now);
            UpdatePeriodLabel();
            _ews.Initialize();
            var loaded = LoadCalendar();
            BuildGrid(loaded);
            CheckDailyAis();
        }

        private DateTime GetWeekStart(DateTime dt)
        {
            int diff = (7 + (dt.DayOfWeek - DayOfWeek.Monday)) % 7;
            return dt.AddDays(-diff).Date;
        }

        private void UpdatePeriodLabel()
        {
            var end = _currentWeekStart.AddDays(4);
            txtPeriod.Text = $"{_currentWeekStart.Day} {_months[_currentWeekStart.Month - 1]} — {end.Day} {_months[end.Month - 1]} {end.Year}";
        }

        private bool LoadCalendar()
        {
            _events.Clear();
            if (!_ews.IsInitialized) return false;
            _events = _ews.GetCalendar(_currentWeekStart);
            Log("INFO", $"Loaded {_events.Count} events");
            return true;
        }

        private void BuildGrid(bool loaded)
        {
            calGrid.Children.Clear();
            calGrid.ColumnDefinitions.Clear();
            calGrid.RowDefinitions.Clear();

            calGrid.Width = 1000;
            calGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(55) });
            for (int c = 0; c < 5; c++)
                calGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(189) });

            calGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(30) });

            // header row
            var corner = CreateBorder("#F5F5F5", "#DDD", "0,0,1,1", 0, 0);
            calGrid.Children.Add(corner);

            for (int c = 0; c < 5; c++)
            {
                var d = _currentWeekStart.AddDays(c);
                bool isToday = d.Date == DateTime.Today;
                var hdr = new Border
                {
                    Background = isToday ? new SolidColorBrush(Color.FromRgb(33, 150, 243)) :
                                 new SolidColorBrush(Color.FromRgb(245, 245, 245)),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(221, 221, 221)),
                    BorderThickness = new Thickness(0, 0, 1, 1),
                    Child = new TextBlock
                    {
                        Text = $"{_dayNames[c]} {d.Day}.{d.Month}",
                        FontSize = 12, FontWeight = FontWeights.Bold,
                        HorizontalAlignment = HorizontalAlignment.Center,
                        VerticalAlignment = VerticalAlignment.Center,
                        Foreground = isToday ? Brushes.White : Brushes.Black
                    }
                };
                Grid.SetRow(hdr, 0); Grid.SetColumn(hdr, c + 1);
                calGrid.Children.Add(hdr);
            }

            // hour rows
            for (int h = HourStart; h <= HourEnd; h++)
            {
                int ri = h - HourStart + 1;
                calGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(HourHeight) });

                var lb = new Border
                {
                    Background = new SolidColorBrush(Color.FromRgb(250, 250, 250)),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(221, 221, 221)),
                    BorderThickness = new Thickness(0, 0, 1, 1),
                    Child = new TextBlock
                    {
                        Text = $"{h:00}:00", FontSize = 10, Foreground = Brushes.Gray,
                        HorizontalAlignment = HorizontalAlignment.Right,
                        VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 0, 6, 0)
                    }
                };
                Grid.SetRow(lb, ri); Grid.SetColumn(lb, 0);
                calGrid.Children.Add(lb);

                for (int c = 0; c < 5; c++)
                {
                    var d = _currentWeekStart.AddDays(c);
                    bool isToday = d.Date == DateTime.Today;
                    var cell = new Border
                    {
                        Background = isToday ? new SolidColorBrush(Color.FromRgb(227, 242, 253)) : Brushes.White,
                        BorderBrush = new SolidColorBrush(Color.FromRgb(224, 224, 224)),
                        BorderThickness = new Thickness(0, 0, 1, 1),
                        Tag = $"cell_{c}_{ri}"
                    };
                    Grid.SetRow(cell, ri); Grid.SetColumn(cell, c + 1);
                    calGrid.Children.Add(cell);
                }
            }

            // place events
            if (!loaded) return;
            foreach (var evt in _events)
            {
                var dayIdx = (int)(evt.Start.Date - _currentWeekStart).TotalDays;
                if (dayIdx < 0 || dayIdx > 4) continue;

                int startMin = evt.Start.Hour * 60 + evt.Start.Minute;
                int endMin = evt.End.Hour * 60 + evt.End.Minute;
                int gridStart = startMin - HourStart * 60;
                int gridEnd = endMin - HourStart * 60;
                if (gridStart < 0) gridStart = 0;
                if (gridEnd > (HourEnd + 1 - HourStart) * 60) gridEnd = (HourEnd + 1 - HourStart) * 60;
                if (gridStart >= gridEnd) gridStart = gridEnd - 15;

                string key = $"{evt.Start.Ticks}_{evt.Subject}";
                bool cf = _confirmed.Contains(key);

                var topOffset = (double)gridStart / 60 * HourHeight;
                var height = Math.Max(20, (double)(gridEnd - gridStart) / 60 * HourHeight);

                var sp = FindOrCreateCellPanel(dayIdx, gridStart, topOffset);
                if (sp == null) continue;

                var evtBlock = new Border
                {
                    CornerRadius = new CornerRadius(4), Padding = new Thickness(4, 2, 4, 2), Margin = new Thickness(0, 1, 0, 0),
                    Background = cf ? new SolidColorBrush(Color.FromRgb(200, 230, 201)) :
                                      new SolidColorBrush(Color.FromRgb(255, 243, 224)),
                    BorderBrush = cf ? new SolidColorBrush(Color.FromRgb(76, 175, 80)) :
                                       new SolidColorBrush(Color.FromRgb(255, 152, 0)),
                    BorderThickness = new Thickness(1), Tag = key
                };

                var inner = new StackPanel();
                var topLine = new DockPanel();
                var chk = new CheckBox
                {
                    IsChecked = cf, Margin = new Thickness(0, 0, 3, 0),
                    VerticalAlignment = VerticalAlignment.Center, Tag = key
                };
                chk.Checked += (s, e) => { _confirmed.Add(key); Rebuild(); };
                chk.Unchecked += (s, e) => { _confirmed.Remove(key); Rebuild(); };
                DockPanel.SetDock(chk, Dock.Left);
                topLine.Children.Add(chk);

                var timeTb = new TextBlock
                {
                    Text = $"{evt.Start:HH:mm}-{evt.End:HH:mm} ({evt.Duration})",
                    FontSize = 9, Foreground = Brushes.Gray
                };
                topLine.Children.Add(timeTb);
                inner.Children.Add(topLine);

                var subjTb = new TextBlock
                {
                    Text = evt.Subject, FontSize = 11, TextWrapping = TextWrapping.Wrap,
                    Margin = new Thickness(18, 0, 0, 0)
                };
                inner.Children.Add(subjTb);

                evtBlock.Child = inner;
                sp.Children.Add(evtBlock);
            }
        }

        private StackPanel? FindOrCreateCellPanel(int dayIdx, int gridStart, double topOffset)
        {
            int rowIdx = gridStart / 60 + 1;
            string tag = $"cell_{dayIdx}_{rowIdx}";
            foreach (var child in calGrid.Children)
            {
                if (child is Border b && b.Tag?.ToString() == tag)
                {
                    if (b.Child is not StackPanel sp)
                    {
                        sp = new StackPanel { Margin = new Thickness(2) };
                        b.Child = sp;
                    }
                    return sp;
                }
            }
            return null;
        }

        private void Rebuild() { BuildGrid(true); }

        private Border CreateBorder(string bgHex, string borderHex, string thickness, int row, int col)
        {
            var b = new Border
            {
                Background = (Brush)new BrushConverter().ConvertFrom(bgHex)!,
                BorderBrush = (Brush)new BrushConverter().ConvertFrom(borderHex)!,
                BorderThickness = (Thickness)new ThicknessConverter().ConvertFrom(thickness)!
            };
            Grid.SetRow(b, row); Grid.SetColumn(b, col);
            return b;
        }

        private void CheckDailyAis()
        {
            try
            {
                var now = DateTime.Now;
                if (now.DayOfWeek == DayOfWeek.Saturday || now.DayOfWeek == DayOfWeek.Sunday) return;
                if (!_ews.IsInitialized) return;
                bool found = _ews.HasEventToday("дейли") || _ews.HasEventToday("Daily") || _ews.HasEventToday("AIS");
                if (found) { Log("AUTO", "Daily AIS уже есть"); return; }
                var r = MessageBox.Show("Сегодня нет 'Daily AIS'. Создать?", "Авто-проверка",
                    MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (r == MessageBoxResult.Yes)
                {
                    var dt = new DateTime(now.Year, now.Month, now.Day, 9, 30, 0);
                    _ews.CreateAppointment("Дейли AIS", dt, 30);
                    Log("AUTO", "Daily AIS создан");
                }
            }
            catch (Exception ex) { Log("AUTO", $"Err: {ex.Message}"); }
        }

        private void BtnSync_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "sync");
            _ews.Initialize();
            LoadCalendar();
            Rebuild();
            UpdateStatus();
        }

        private void BtnConfirm_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "confirm");
            MessageBox.Show($"Подтверждено: {_confirmed.Count} мероприятий", "Подтверждение",
                MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void BtnToday_Click(object sender, RoutedEventArgs e) { _currentWeekStart = GetWeekStart(DateTime.Now); UpdatePeriodLabel(); LoadCalendar(); Rebuild(); UpdateStatus(); }
        private void BtnPrev_Click(object sender, RoutedEventArgs e) { _currentWeekStart = _currentWeekStart.AddDays(-7); UpdatePeriodLabel(); LoadCalendar(); Rebuild(); UpdateStatus(); }
        private void BtnNext_Click(object sender, RoutedEventArgs e) { _currentWeekStart = _currentWeekStart.AddDays(7); UpdatePeriodLabel(); LoadCalendar(); Rebuild(); UpdateStatus(); }

        private void UpdateStatus()
        {
            var end = _currentWeekStart.AddDays(4);
            lblStatus.Text = $"Календарь: {_currentWeekStart.Day}.{_currentWeekStart.Month} — {end.Day}.{end.Month}, событий: {_events.Count}";
        }

        private void Window_Loaded(object sender, RoutedEventArgs e) { Log("INFO", "Window loaded"); ApplyRoundedRegion(); UpdateStatus(); }
        private void Window_SizeChanged(object sender, SizeChangedEventArgs e) { ApplyRoundedRegion(); }
        protected override void OnSourceInitialized(EventArgs e) { base.OnSourceInitialized(e); if (PresentationSource.FromVisual(this) is HwndSource hs) hs.AddHook(WndProc); }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_NCHITTEST)
            {
                int x = (int)(lParam.ToInt64() & 0xFFFF), y = (int)((lParam.ToInt64() >> 16) & 0xFFFF);
                var p = PointFromScreen(new Point(x, y)); double w = ActualWidth, h = ActualHeight; int m = RESIZE_MARGIN;
                if (p.Y < 42 && !(p.X < m) && !(p.X > w - 160) && !(p.Y < m)) { handled = true; return (IntPtr)HTCAPTION; }
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
                if (w <= 0 || h <= 0) { w = 1100; h = 720; }
                var rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, rgn, true); DeleteObject(rgn);
            }
            catch { }
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) { if (HasButtonParent(e.OriginalSource as DependencyObject)) return; if (e.ClickCount == 2) { ToggleMaximize(); return; } try { DragMove(); } catch { } }
        private static bool HasButtonParent(DependencyObject? d) { while (d != null) { if (d is Button) return true; d = VisualTreeHelper.GetParent(d); } return false; }
        private void ToggleMaximize() { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; }
        private void BtnMinimize_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; }
        private void BtnMaximize_Click(object sender, RoutedEventArgs e) { ToggleMaximize(); }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Close(); }
        private void Window_KeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) Close(); }
    }
}
