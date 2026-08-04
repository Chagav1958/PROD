using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.ComponentModel;
using System.Collections.Generic;
using System.Reflection;
using System.Text.Json;
using System.Windows.Threading;
using System.Windows.Input;
using System.Windows.Markup;
using System.Xml;
using System.Text;
using System.Diagnostics;

namespace AIS.ObjectInfo
{
    public static class St2Button
    {
        static Style primaryStyle, secondaryStyle, smallStyle;

        public static Style GetStyle(bool isPrimary = true, bool isSmall = false) {
            if (isSmall) { if (smallStyle == null) smallStyle = CreateStyle(true, true); return smallStyle; }
            if (isPrimary) { if (primaryStyle == null) primaryStyle = CreateStyle(true, false); return primaryStyle; }
            if (secondaryStyle == null) secondaryStyle = CreateStyle(false, false); return secondaryStyle;
        }

        static Style CreateStyle(bool isPrimary, bool isSmall) {
            var style = new Style(typeof(Button));
            style.Setters.Add(new Setter(Control.FontSizeProperty, 11.0));
            style.Setters.Add(new Setter(Control.FontWeightProperty, FontWeights.Bold));
            style.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.White));
            style.Setters.Add(new Setter(Control.CursorProperty, Cursors.Hand));
            style.Setters.Add(new Setter(Button.WidthProperty, isSmall ? 30.0 : 120.0));
            style.Setters.Add(new Setter(Button.HeightProperty, isSmall ? 26.0 : 38.0));

            string borderColor = isPrimary ? "#CC0F3050" : "#CC404040";
            var stops = isPrimary
                ? new[] { "#CC9DC8F0", "#CC3B7BBF", "#CC1A4A7A" }
                : new[] { "#CCD0D0D0", "#CC909090", "#CC606060" };

            string xaml = string.Format(@"
<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'>
  <Grid>
    <Border CornerRadius='10' Background='{0}'>
      <Grid>
        <Border CornerRadius='9' Margin='1.5'>
          <Border.Background>
            <LinearGradientBrush StartPoint='0,0' EndPoint='0,1'>
              <GradientStop Color='{1}' Offset='0'/>
              <GradientStop Color='{2}' Offset='0.5'/>
              <GradientStop Color='{3}' Offset='1'/>
            </LinearGradientBrush>
          </Border.Background>
        </Border>
        <Border CornerRadius='9' Margin='2,2,2,20' Height='7' VerticalAlignment='Top'>
          <Border.Background>
            <LinearGradientBrush StartPoint='0,0' EndPoint='0,1'>
              <GradientStop Color='#E0FFFFFF' Offset='0'/>
              <GradientStop Color='#00FFFFFF' Offset='1'/>
            </LinearGradientBrush>
          </Border.Background>
        </Border>
        <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center' Margin='0,2,0,0'/>
      </Grid>
    </Border>
  </Grid>
</ControlTemplate>", borderColor, stops[0], stops[1], stops[2]);

            try {
                var doc = new XmlDocument(); doc.LoadXml(xaml);
                var template = (ControlTemplate)XamlReader.Load(new XmlNodeReader(doc.DocumentElement));
                style.Setters.Add(new Setter(Control.TemplateProperty, template));
            } catch { }
            return style;
        }
    }
    public class PbObject {
        public string name { get; set; } public string type { get; set; } public string lib { get; set; }
        public int size_kb { get; set; } public string modified { get; set; } public string first_anc { get; set; }
        public string src { get; set; } public string versions_match { get; set; } public string tasks { get; set; }
        public string file_path { get; set; } public string main_path { get; set; }
        public List<string> contained_list { get; set; } = new List<string>();
        public List<string> contained_sql { get; set; } = new List<string>();
        public List<string> contained_in_list { get; set; } = new List<string>();
        public List<string> funcs { get; set; } = new List<string>();
        public List<string> events { get; set; } = new List<string>();
    }

    public class SqlObject {
        public string name { get; set; } public string type { get; set; } public string category { get; set; }
        public string server { get; set; } public string db { get; set; } public int size_kb { get; set; }
        public string modified { get; set; } public string purpose { get; set; } public string src { get; set; }
        public string versions_match { get; set; } public string tasks { get; set; }
        public string file_path { get; set; } public string main_path { get; set; }
        public List<string> contained_list { get; set; } = new List<string>();
        public List<string> contained_in_list { get; set; } = new List<string>();
        public List<string> pb_refs_list { get; set; } = new List<string>();
        public List<string> funcs { get; set; } = new List<string>();
        public List<string> paramz { get; set; } = new List<string>();
        public List<string> tables { get; set; } = new List<string>();
    }

    public class App : Application
    {
        List<PbObject> pbData;
        List<SqlObject> sqlData;
        TextBox pbCode, sqlCode;
        TextBox pbMerge, sqlMerge;
        string PbCurPath, PbMainPath, SqlCurPath, SqlMainPath;
        string pbSearchIdx = "", sqlSearchIdx = "";
        int pbSearchPos = 0, sqlSearchPos = 0;
        DataGrid pbProps, sqlProps, pbCont, sqlCont, pbContIn, sqlContIn, pbContSql;
        ProgressBar progBar;
        TextBlock statusBar;
        string logPath;
        Window window;

        [STAThread]
        public static void Main() { new App().Run(); }

        public App() {
            logPath = Path.Combine(Path.GetTempPath(), "objinfo_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".log");
            Log("GUI start C# v2");

            try { pbData = LoadPb(); sqlData = LoadSql(); } catch { }
            Log(string.Format("Data: PB={0} SQL={1}", pbData != null ? pbData.Count : 0, sqlData != null ? sqlData.Count : 0));

            window = new Window {
                Title = "Справочник объектов AIS",
                Width = 960, Height = 680,
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Transparent,
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                ResizeMode = ResizeMode.CanResizeWithGrip
            };
            window.KeyDown += (s, e) => { if (e.Key == Key.Escape) window.Close(); };

            // STANDART2 wrapper
            var outer = new Border {
                CornerRadius = new CornerRadius(18),
                Background = (Brush)new BrushConverter().ConvertFrom("#E8ECF0"),
                BorderBrush = (Brush)new BrushConverter().ConvertFrom("#1A3A60"),
                BorderThickness = new Thickness(1),
                Effect = new DropShadowEffect { Color = Color.FromRgb(0x40, 0x40, 0x40), Direction = 270, ShadowDepth = 4, BlurRadius = 10, Opacity = 0.5 }
            };

            var contentGrid = new Grid();
            contentGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });
            contentGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            // Title bar
            var titleBorder = new Border {
                Background = (Brush)new BrushConverter().ConvertFrom("#807080B0"),
                CornerRadius = new CornerRadius(17, 17, 0, 0),
                BorderBrush = (Brush)new BrushConverter().ConvertFrom("#1A3A60"),
                BorderThickness = new Thickness(0, 0, 0, 1)
            };
            titleBorder.MouseLeftButtonDown += (s, e) => { if (e.ClickCount == 1) window.DragMove(); };
            Grid.SetRow(titleBorder, 0);

            var titleText = new TextBlock {
                Text = "Справочник объектов AIS",
                FontSize = 14, FontWeight = FontWeights.Bold, FontFamily = new FontFamily("Segoe UI"),
                Foreground = (Brush)new BrushConverter().ConvertFrom("#1A3A60"),
                VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(14, 0, 0, 0)
            };
            titleBorder.Child = titleText;
            contentGrid.Children.Add(titleBorder);

            // Main content
            var mainGrid = new Grid { Margin = new Thickness(2, 0, 2, 2) };
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var tabs = new TabControl { FontSize = 12 };
            tabs.Items.Add(BuildPbTab());
            tabs.Items.Add(BuildSqlTab());
            Grid.SetRow(tabs, 0);
            mainGrid.Children.Add(tabs);

            // Status bar
            var sb = new Grid { Margin = new Thickness(10, 4, 10, 4) };
            sb.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            sb.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            sb.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            statusBar = new TextBlock { Text = "Готов", FontSize = 10, Foreground = new SolidColorBrush(Color.FromRgb(0x4A, 0x55, 0x68)), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
            Grid.SetColumn(statusBar, 0); sb.Children.Add(statusBar);

            progBar = new ProgressBar { Height = 12, IsIndeterminate = false, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
            Grid.SetColumn(progBar, 1); sb.Children.Add(progBar);

            var closeBtn = new Button { Content = "Закрыть", FontSize = 10, Style = St2Button.GetStyle(false) };
            closeBtn.Click += (s, e) => { Log("Close"); window.Close(); };
            Grid.SetColumn(closeBtn, 2); sb.Children.Add(closeBtn);

            Grid.SetRow(sb, 1); mainGrid.Children.Add(sb);
            Grid.SetRow(mainGrid, 1); contentGrid.Children.Add(mainGrid);

            outer.Child = contentGrid;
            window.Content = outer;

            // Command timer
            var cmdTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            cmdTimer.Tick += ProcessCmd;
            cmdTimer.Start();

            window.Closed += (s, e) => { Log("Closed"); Shutdown(); };
            window.Show();
        }

        void ProcessCmd(object s, EventArgs e) {
            string cmdFile = Path.Combine(Path.GetTempPath(), "objinfo_cmd.txt");
            string respFile = Path.Combine(Path.GetTempPath(), "objinfo_resp.txt");
            try {
                if (File.Exists(cmdFile)) {
                    var cmd = File.ReadAllText(cmdFile, System.Text.Encoding.UTF8).Trim();
                    File.Delete(cmdFile);
                    string resp = "unknown";
            if (cmd == "ping") resp = "pong";
            else if (cmd.StartsWith("sel_pb ")) { resp = "ok"; File.WriteAllText(respFile, resp); FillPb(pbData[int.Parse(cmd.Substring(7))]); return; }
            else if (cmd.StartsWith("sel_sql ")) { resp = "ok"; File.WriteAllText(respFile, resp); FillSql(sqlData[int.Parse(cmd.Substring(8))]); return; }
            else if (cmd == "st_pb") resp = string.Format("{0},{1}", pbCode != null ? pbCode.Text.Length : 0, pbProps != null && pbProps.ItemsSource != null ? (pbProps.ItemsSource as System.Collections.IList).Count : 0);
            else if (cmd == "st_sql") resp = string.Format("{0},{1}", sqlCode != null ? sqlCode.Text.Length : 0, sqlProps != null && sqlProps.ItemsSource != null ? (sqlProps.ItemsSource as System.Collections.IList).Count : 0);
                    else if (cmd == "close") { resp = "ok"; File.WriteAllText(respFile, resp); window.Dispatcher.Invoke(() => window.Close()); return; }
                    File.WriteAllText(respFile, resp);
                }
            } catch { }
        }

        void Log(string msg) { try { File.AppendAllText(logPath, string.Format("[{0:HH:mm:ss}] {1}\n", DateTime.Now, msg)); } catch { } }

        TabItem BuildPbTab() {
            var tab = new TabItem { Header = "PB" };
            var inner = new TabControl { FontSize = 11 };

            var t1 = new TabItem { Header = "Объекты" };
            var g1 = new Grid();
            g1.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g1.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g1.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g1.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var dg = new DataGrid { ItemsSource = pbData, IsReadOnly = true, AutoGenerateColumns = true, CanUserSortColumns = true, SelectionMode = DataGridSelectionMode.Single, FontSize = 11, MinHeight = 250 };
            dg.AlternatingRowBackground = new SolidColorBrush(Color.FromRgb(0xF5, 0xF7, 0xFA));
            dg.RowBackground = Brushes.White;
            dg.MouseDoubleClick += (s, e2) => { if (dg.SelectedItem != null) { Log("DblClick: " + ((PbObject)dg.SelectedItem).name); FillPb((PbObject)dg.SelectedItem); } };

            var fp = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 2, 4, 2) };
            var ft = new TextBox { Width = 200, FontSize = 11 };
            ft.TextChanged += (s, e2) => {
                var txt = ft.Text.ToLower();
                var view = CollectionViewSource.GetDefaultView(dg.ItemsSource) as ICollectionView;
                if (string.IsNullOrEmpty(txt)) view.Filter = null;
                else view.Filter = o => (o as PbObject)?.name?.ToLower()?.Contains(txt) == true || (o as PbObject)?.lib?.ToLower()?.Contains(txt) == true;
            };
            fp.Children.Add(new TextBlock { Text = "Фильтр:", FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) });
            fp.Children.Add(ft);
            Grid.SetRow(fp, 0); g1.Children.Add(fp);

            var sp = new WrapPanel { Margin = new Thickness(4, 2, 4, 2) };
            sp.Children.Add(new TextBlock { Text = "Сорт:", FontSize = 10, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) });
            var cbF = new ComboBox { Width = 130, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            cbF.Items.Add("--поле--");
            foreach (var c in new[] { "name", "type", "lib", "size_kb", "modified", "first_anc", "src", "versions_match", "tasks" }) cbF.Items.Add(c);
            cbF.SelectedIndex = 0;
            var cbD = new ComboBox { Width = 70, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            cbD.Items.Add("Asc"); cbD.Items.Add("Desc"); cbD.SelectedIndex = 0;
            var slbl = new TextBlock { FontSize = 10, VerticalAlignment = VerticalAlignment.Center };
            var bAdd = new Button { Content = "+", Width = 24, Height = 20, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            bAdd.Click += (s, e2) => {
                if (cbF.SelectedIndex <= 0) return;
                var view = CollectionViewSource.GetDefaultView(dg.ItemsSource) as ListCollectionView;
                view.SortDescriptions.Add(new SortDescription(cbF.SelectedItem.ToString(), cbD.SelectedIndex == 0 ? ListSortDirection.Ascending : ListSortDirection.Descending));
                slbl.Text += string.IsNullOrEmpty(slbl.Text) ? cbF.SelectedItem.ToString() : " + " + cbF.SelectedItem;
            };
            var bClr = new Button { Content = "X", Width = 24, Height = 20, FontSize = 9 };
            bClr.Click += (s, e2) => { (CollectionViewSource.GetDefaultView(dg.ItemsSource) as ListCollectionView).SortDescriptions.Clear(); slbl.Text = ""; };
            sp.Children.Add(cbF); sp.Children.Add(cbD); sp.Children.Add(bAdd); sp.Children.Add(bClr); sp.Children.Add(slbl);
            Grid.SetRow(sp, 1); g1.Children.Add(sp);
            Grid.SetRow(dg, 2); g1.Children.Add(dg);

            var btn = new Button { Content = "Показать детали", Style = St2Button.GetStyle(true), Margin = new Thickness(4, 2, 4, 2) };
            btn.Click += (s, e2) => { if (dg.SelectedItem != null) FillPb((PbObject)dg.SelectedItem); };
            Grid.SetRow(btn, 3); g1.Children.Add(btn);
            t1.Content = g1;
            inner.Items.Add(t1);

            pbCode = new TextBox { IsReadOnly = true, FontFamily = new FontFamily("Consolas"), FontSize = 10, Background = Brushes.White, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, AcceptsReturn = true };
            var pbCodePanel = new DockPanel();
            var pbSearchPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 4) };
            pbSearchPanel.Children.Add(new TextBlock { Text = "Поиск:", FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) });
            var pbSearchBox = new TextBox { Width = 200, FontSize = 11, Margin = new Thickness(0, 0, 4, 0) };
            pbSearchBox.KeyDown += (s2, e2) => { if (e2.Key == Key.Enter) { DoSearch(pbCode, pbSearchBox, ref pbSearchIdx, ref pbSearchPos); } };
            pbSearchPanel.Children.Add(pbSearchBox);
            var pbSrchBtn = new Button { Content = "Далее", Width = 55, Height = 22, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            pbSrchBtn.Click += (s2, e2) => { DoSearch(pbCode, pbSearchBox, ref pbSearchIdx, ref pbSearchPos); };
            pbSearchPanel.Children.Add(pbSrchBtn);
            var pbClrBtn = new Button { Content = "X", Width = 24, Height = 22, FontSize = 9 };
            pbClrBtn.Click += (s2, e2) => { pbSearchBox.Text = ""; pbSearchIdx = ""; pbSearchPos = 0; };
            pbSearchPanel.Children.Add(pbClrBtn);
            DockPanel.SetDock(pbSearchPanel, Dock.Top);
            pbCodePanel.Children.Add(pbSearchPanel);
            pbCodePanel.Children.Add(pbCode);
            inner.Items.Add(new TabItem { Header = "Код", Content = pbCodePanel });
            var _pbCont = new DataGrid { IsReadOnly = true, AutoGenerateColumns = true, MinHeight = 80, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader };
            _pbCont.ContextMenu = MakeCollectionMenu("Содержит", _pbCont); pbCont = _pbCont;
            inner.Items.Add(new TabItem { Header = "Содержит", Content = pbCont });
            var _pbContSql = new DataGrid { IsReadOnly = true, AutoGenerateColumns = true, MinHeight = 80, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader };
            _pbContSql.ContextMenu = MakeCollectionMenu("Содержит SQL", _pbContSql); pbContSql = _pbContSql;
            inner.Items.Add(new TabItem { Header = "Содержит SQL", Content = pbContSql });
            var _pbContIn = new DataGrid { IsReadOnly = true, AutoGenerateColumns = true, MinHeight = 80, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader };
            _pbContIn.ContextMenu = MakeCollectionMenu("Содержится в", _pbContIn); pbContIn = _pbContIn;
            inner.Items.Add(new TabItem { Header = "Содержится в", Content = pbContIn });
            pbProps = new DataGrid { IsReadOnly = true, AutoGenerateColumns = true, MinHeight = 80, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader }; inner.Items.Add(new TabItem { Header = "Свойства", Content = pbProps });
            pbMerge = new TextBox { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontSize = 11, FontFamily = new FontFamily("Consolas"), Background = Brushes.White, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, AcceptsReturn = true };
            var pbMergePanel = new DockPanel { Margin = new Thickness(4) };
            var pbTmBtn = new Button { Content = "TortoiseMerge", Style = St2Button.GetStyle(true, false), Width = 130, Height = 28, FontSize = 10, Margin = new Thickness(0, 0, 0, 4) };
            pbTmBtn.Click += (s, e2) => RunTortoiseMerge(PbCurPath, PbMainPath);
            DockPanel.SetDock(pbTmBtn, Dock.Top);
            pbMergePanel.Children.Add(pbTmBtn);
            pbMergePanel.Children.Add(pbMerge);
            inner.Items.Add(new TabItem { Header = "Merge", Content = pbMergePanel });
            tab.Content = inner; return tab;
        }

        TabItem BuildSqlTab() {
            var tab = new TabItem { Header = "SQL" };
            var inner = new TabControl { FontSize = 11 };

            var t1 = new TabItem { Header = "Объекты" };
            var g1 = new Grid();
            g1.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g1.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            g1.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            g1.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var dg = new DataGrid { ItemsSource = sqlData, IsReadOnly = true, AutoGenerateColumns = false, CanUserSortColumns = true, SelectionMode = DataGridSelectionMode.Single, FontSize = 11, MinHeight = 250, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader };
            dg.Columns.Add(new DataGridTextColumn { Header = "Имя", Binding = new Binding("name"), Width = new DataGridLength(180) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Тип", Binding = new Binding("type"), Width = new DataGridLength(80) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Задачи", Binding = new Binding("tasks"), Width = new DataGridLength(130) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Описание", Binding = new Binding("purpose"), Width = new DataGridLength(160) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Размер", Binding = new Binding("size_kb"), Width = new DataGridLength(60) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Изменён", Binding = new Binding("modified"), Width = new DataGridLength(120) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Версия", Binding = new Binding("src"), Width = new DataGridLength(70) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Совпад", Binding = new Binding("versions_match"), Width = new DataGridLength(70) });
            dg.Columns.Add(new DataGridTextColumn { Header = "Сервер", Binding = new Binding("server"), Width = new DataGridLength(90) });
            dg.Columns.Add(new DataGridTextColumn { Header = "БД", Binding = new Binding("db"), Width = new DataGridLength(60) });
            dg.AlternatingRowBackground = new SolidColorBrush(Color.FromRgb(0xF5, 0xF7, 0xFA));
            dg.RowBackground = Brushes.White;
            dg.MouseDoubleClick += (s, e2) => { if (dg.SelectedItem != null) FillSql((SqlObject)dg.SelectedItem); };

            var fp = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 2, 4, 2) };
            var ft = new TextBox { Width = 200, FontSize = 11 };
            ft.TextChanged += (s, e2) => {
                var txt = ft.Text.ToLower();
                var view = CollectionViewSource.GetDefaultView(dg.ItemsSource) as ICollectionView;
                if (string.IsNullOrEmpty(txt)) view.Filter = null;
                else view.Filter = o => (o as SqlObject)?.name?.ToLower()?.Contains(txt) == true || (o as SqlObject)?.type?.ToLower()?.Contains(txt) == true;
            };
            fp.Children.Add(new TextBlock { Text = "Фильтр:", FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) });
            fp.Children.Add(ft);
            Grid.SetRow(fp, 0); g1.Children.Add(fp);

            var sp = new WrapPanel { Margin = new Thickness(4, 2, 4, 2) };
            sp.Children.Add(new TextBlock { Text = "Сорт:", FontSize = 10, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) });
            var cbF = new ComboBox { Width = 130, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            cbF.Items.Add("--поле--");
            foreach (var c in new[] { "name", "type", "server", "db", "size_kb", "modified", "src", "versions_match", "tasks" }) cbF.Items.Add(c);
            cbF.SelectedIndex = 0;
            var cbD = new ComboBox { Width = 70, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            cbD.Items.Add("Asc"); cbD.Items.Add("Desc"); cbD.SelectedIndex = 0;
            var slbl = new TextBlock { FontSize = 10, VerticalAlignment = VerticalAlignment.Center };
            var bAdd = new Button { Content = "+", Width = 24, Height = 20, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            bAdd.Click += (s, e2) => {
                if (cbF.SelectedIndex <= 0) return;
                var view = CollectionViewSource.GetDefaultView(dg.ItemsSource) as ListCollectionView;
                view.SortDescriptions.Add(new SortDescription(cbF.SelectedItem.ToString(), cbD.SelectedIndex == 0 ? ListSortDirection.Ascending : ListSortDirection.Descending));
                slbl.Text += string.IsNullOrEmpty(slbl.Text) ? cbF.SelectedItem.ToString() : " + " + cbF.SelectedItem;
            };
            var bClr = new Button { Content = "X", Width = 24, Height = 20, FontSize = 9 };
            bClr.Click += (s, e2) => { (CollectionViewSource.GetDefaultView(dg.ItemsSource) as ListCollectionView).SortDescriptions.Clear(); slbl.Text = ""; };
            sp.Children.Add(cbF); sp.Children.Add(cbD); sp.Children.Add(bAdd); sp.Children.Add(bClr); sp.Children.Add(slbl);
            Grid.SetRow(sp, 1); g1.Children.Add(sp);
            Grid.SetRow(dg, 2); g1.Children.Add(dg);

            var btn = new Button { Content = "Показать детали", Style = St2Button.GetStyle(true), Margin = new Thickness(4, 2, 4, 2) };
            btn.Click += (s, e2) => { if (dg.SelectedItem != null) FillSql((SqlObject)dg.SelectedItem); };
            Grid.SetRow(btn, 3); g1.Children.Add(btn);
            t1.Content = g1;
            inner.Items.Add(t1);

            sqlCode = new TextBox { IsReadOnly = true, FontFamily = new FontFamily("Consolas"), FontSize = 10, Background = Brushes.White, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, AcceptsReturn = true };
            var sqlCodePanel = new DockPanel();
            var sqlSearchPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 4) };
            sqlSearchPanel.Children.Add(new TextBlock { Text = "Поиск:", FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 4, 0) });
            var sqlSearchBox = new TextBox { Width = 200, FontSize = 11, Margin = new Thickness(0, 0, 4, 0) };
            sqlSearchBox.KeyDown += (s2, e2) => { if (e2.Key == Key.Enter) { DoSearch(sqlCode, sqlSearchBox, ref sqlSearchIdx, ref sqlSearchPos); } };
            sqlSearchPanel.Children.Add(sqlSearchBox);
            var sqlSrchBtn = new Button { Content = "Далее", Width = 55, Height = 22, FontSize = 10, Margin = new Thickness(0, 0, 4, 0) };
            sqlSrchBtn.Click += (s2, e2) => { DoSearch(sqlCode, sqlSearchBox, ref sqlSearchIdx, ref sqlSearchPos); };
            sqlSearchPanel.Children.Add(sqlSrchBtn);
            var sqlClrBtn = new Button { Content = "X", Width = 24, Height = 22, FontSize = 9 };
            sqlClrBtn.Click += (s2, e2) => { sqlSearchBox.Text = ""; sqlSearchIdx = ""; sqlSearchPos = 0; };
            sqlSearchPanel.Children.Add(sqlClrBtn);
            DockPanel.SetDock(sqlSearchPanel, Dock.Top);
            sqlCodePanel.Children.Add(sqlSearchPanel);
            sqlCodePanel.Children.Add(sqlCode);
            inner.Items.Add(new TabItem { Header = "Код", Content = sqlCodePanel });
            var _sqlCont = new DataGrid { IsReadOnly = true, AutoGenerateColumns = true, MinHeight = 80, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader };
            _sqlCont.ContextMenu = MakeCollectionMenu("Содержит", _sqlCont); sqlCont = _sqlCont;
            inner.Items.Add(new TabItem { Header = "Содержит", Content = sqlCont });
            var _sqlContIn = new DataGrid { IsReadOnly = true, AutoGenerateColumns = true, MinHeight = 80, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader };
            _sqlContIn.ContextMenu = MakeCollectionMenu("Содержится в", _sqlContIn); sqlContIn = _sqlContIn;
            inner.Items.Add(new TabItem { Header = "Содержится в", Content = sqlContIn });
            sqlProps = new DataGrid { IsReadOnly = true, AutoGenerateColumns = true, MinHeight = 80, ClipboardCopyMode = DataGridClipboardCopyMode.IncludeHeader }; inner.Items.Add(new TabItem { Header = "Свойства", Content = sqlProps });
            sqlMerge = new TextBox { IsReadOnly = true, TextWrapping = TextWrapping.Wrap, FontSize = 11, FontFamily = new FontFamily("Consolas"), Background = Brushes.White, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, AcceptsReturn = true };
            var sqlMergePanel = new DockPanel { Margin = new Thickness(4) };
            var sqlTmBtn = new Button { Content = "TortoiseMerge", Style = St2Button.GetStyle(true, false), Width = 130, Height = 28, FontSize = 10, Margin = new Thickness(0, 0, 0, 4) };
            sqlTmBtn.Click += (s, e2) => RunTortoiseMerge(SqlCurPath, SqlMainPath);
            DockPanel.SetDock(sqlTmBtn, Dock.Top);
            sqlMergePanel.Children.Add(sqlTmBtn);
            sqlMergePanel.Children.Add(sqlMerge);
            inner.Items.Add(new TabItem { Header = "Merge", Content = sqlMergePanel });
            tab.Content = inner; return tab;
        }

        void FillPb(PbObject o) {
            Log("PB: " + o.name);
            PbCurPath = o.file_path; PbMainPath = o.main_path;
            window.Dispatcher.Invoke(() => { statusBar.Text = "Загрузка: " + o.name + "..."; progBar.IsIndeterminate = true; });
            if (!string.IsNullOrEmpty(o.file_path) && File.Exists(o.file_path))
                try { var raw = File.ReadAllText(o.file_path); pbCode.Text = raw.Length > 30000 ? raw.Substring(0, 30000) + "\r\n...[обрезано]..." : raw; }
                catch (Exception ex) { pbCode.Text = "Ошибка: " + ex.Message; }
            else pbCode.Text = "Файл не найден: " + o.file_path;
            pbMerge.Text = BuildMerge(o.main_path, o.file_path, o.versions_match);
            pbCont.ItemsSource = o.contained_list.Select(x => new { Объект = x }).ToList();
            pbContSql.ItemsSource = o.contained_sql.Select(x => new { Объект = x }).ToList();
            pbContIn.ItemsSource = o.contained_in_list.Select(x => new { Объект = x }).ToList();
            var props = new List<object> { new { Свойство="Тип", Значение=o.type }, new { Свойство="Библ", Значение=o.lib }, new { Свойство="Размер", Значение=o.size_kb+" KB" }, new { Свойство="Предок", Значение=o.first_anc }, new { Свойство="Версия", Значение=o.src }, new { Свойство="Совпад", Значение=o.versions_match }, new { Свойство="Задачи", Значение=o.tasks } };
            foreach (var f in o.funcs) props.Add(new { Свойство = "Функция", Значение = f });
            pbProps.ItemsSource = props;
            window.Dispatcher.Invoke(() => { progBar.IsIndeterminate = false; statusBar.Text = "Готово: " + o.name; });
        }
        void FillSql(SqlObject o) {
            Log("SQL: " + o.name);
            SqlCurPath = o.file_path; SqlMainPath = o.main_path;
            window.Dispatcher.Invoke(() => { statusBar.Text = "Загрузка: " + o.name + "..."; progBar.IsIndeterminate = true; });
            if (!string.IsNullOrEmpty(o.file_path) && File.Exists(o.file_path))
                try { var raw = File.ReadAllText(o.file_path, GetFileEncoding(o.file_path)); sqlCode.Text = raw.Length > 30000 ? raw.Substring(0, 30000) + "\r\n...[обрезано]..." : raw; }
                catch (Exception ex) { sqlCode.Text = "Ошибка: " + ex.Message; }
            else sqlCode.Text = "Файл не найден: " + o.file_path;
            sqlMerge.Text = BuildMerge(o.main_path, o.file_path, o.versions_match);
            sqlCont.ItemsSource = o.contained_list.Select(x => new { Объект = x }).ToList();
            sqlContIn.ItemsSource = o.contained_in_list.Select(x => new { Объект = x }).ToList();
            var props = new List<object> { new { Свойство="Тип", Значение=o.type }, new { Свойство="Кат", Значение=o.category }, new { Свойство="Сервер", Значение=o.server }, new { Свойство="БД", Значение=o.db }, new { Свойство="Размер", Значение=o.size_kb+" KB" }, new { Свойство="Версия", Значение=o.src }, new { Свойство="Совпад", Значение=o.versions_match }, new { Свойство="Задачи", Значение=o.tasks } };
            foreach (var f in o.funcs) props.Add(new { Свойство = "Функция", Значение = f });
            sqlProps.ItemsSource = props;
            window.Dispatcher.Invoke(() => { progBar.IsIndeterminate = false; statusBar.Text = "Готово: " + o.name; });
        }

        List<PbObject> LoadPb() {
            var json = File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..\\temp\\pb_full.json"));
            var raw = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(json);
            return raw.Select(r => new PbObject {
                name = S(r,"name"), type = S(r,"type"), lib = S(r,"lib"), size_kb = I(r,"size_kb"), modified = S(r,"modified"),
                first_anc = S(r,"first_anc"), src = S(r,"src"), versions_match = S(r,"versions_match"), tasks = S(r,"tasks"),
                file_path = S(r,"file_path"), main_path = S(r,"main_path"),
                contained_list = L(r,"contained_list"), contained_sql = L(r,"contained_sql"),
                contained_in_list = L(r,"contained_in_list"), funcs = L(r,"funcs"), events = L(r,"events")
            }).ToList();
        }
        List<SqlObject> LoadSql() {
            var json = File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..\\temp\\sql_full.json"));
            var raw = JsonSerializer.Deserialize<List<Dictionary<string, object>>>(json);
            return raw.Select(r => new SqlObject {
                name = S(r,"name"), type = S(r,"type"), category = S(r,"category"), server = S(r,"server"), db = S(r,"db"),
                size_kb = I(r,"size_kb"), modified = S(r,"modified"), purpose = S(r,"purpose"), src = S(r,"src"),
                versions_match = S(r,"versions_match"), tasks = S(r,"tasks"), file_path = S(r,"file_path"), main_path = S(r,"main_path"),
                contained_list = L(r,"contained_list"), contained_in_list = L(r,"contained_in_list"),
                pb_refs_list = L(r,"pb_refs_list"), funcs = L(r,"funcs"), paramz = L(r,"params"), tables = L(r,"tables")
            }).ToList();
        }
        static string BuildMerge(string mainPath, string curPath, string versionsMatch) {
            var sb = new StringBuilder();
            sb.AppendLine("=== Сравнение версий (Main vs Current) ===");
            sb.AppendLine("Статус: " + (string.IsNullOrEmpty(versionsMatch) ? "нет данных" : versionsMatch));
            sb.AppendLine();
            bool mainOk = !string.IsNullOrEmpty(mainPath) && File.Exists(mainPath);
            bool curOk = !string.IsNullOrEmpty(curPath) && File.Exists(curPath);
            if (!mainOk) sb.AppendLine("Главный файл не найден: " + (mainPath ?? "нет пути"));
            if (!curOk) sb.AppendLine("Текущий файл не найден: " + (curPath ?? "нет пути"));
            if (!mainOk || !curOk) return sb.ToString();
            try {
                var enc = GetFileEncoding(mainPath);
                var mainLines = File.ReadAllLines(mainPath, enc);
                var curLines = File.ReadAllLines(curPath, enc);
                int max = Math.Min(500, Math.Max(mainLines.Length, curLines.Length));
                int diffCount = 0;
                for (int i = 0; i < max; i++) {
                    bool hasMain = i < mainLines.Length;
                    bool hasCur = i < curLines.Length;
                    if (hasMain && hasCur) {
                        if (mainLines[i] != curLines[i]) {
                            sb.AppendLine(string.Format("- {0,4}: {1}", i + 1, Trunc(mainLines[i])));
                            sb.AppendLine(string.Format("+ {0,4}: {1}", i + 1, Trunc(curLines[i])));
                            diffCount++;
                            if (diffCount >= 200) { sb.AppendLine(string.Format("...и ещё {0} различий (показаны первые 200)", max - i - 1)); break; }
                        }
                    } else if (hasMain && !hasCur)
                        sb.AppendLine(string.Format("- {0,4}: {1}", i + 1, Trunc(mainLines[i])));
                    else if (!hasMain && hasCur)
                        sb.AppendLine(string.Format("+ {0,4}: {1}", i + 1, Trunc(curLines[i])));
                }
                if (diffCount == 0 && mainLines.Length == curLines.Length) sb.AppendLine("Файлы идентичны.");
                else if (diffCount == 0) sb.AppendLine(string.Format("Содержимое совпадает, но строк: Main={0}, Current={1}", mainLines.Length, curLines.Length));
                sb.AppendLine();
                sb.AppendLine(string.Format("Всего: Main={0} стр, Current={1} стр, различий={2}", mainLines.Length, curLines.Length, diffCount));
            } catch (Exception ex) { sb.AppendLine("Ошибка сравнения: " + ex.Message); }
            return sb.ToString();
        }
        static void RunTortoiseMerge(string curPath, string mainPath) {
            string tm = null;
            foreach (var p in new[] {
                @"C:\Program Files\TortoiseGit\bin\TortoiseGitMerge.exe",
                @"C:\Program Files\TortoiseSVN\bin\TortoiseMerge.exe"
            }) { if (File.Exists(p)) { tm = p; break; } }
            if (tm == null) { MessageBox.Show("TortoiseMerge не найден. Установите TortoiseGit или TortoiseSVN.", "Ошибка", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
            if (string.IsNullOrEmpty(mainPath) || !File.Exists(mainPath)) { MessageBox.Show("Главный файл не найден: " + (mainPath ?? "нет"), "Ошибка", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
            if (string.IsNullOrEmpty(curPath) || !File.Exists(curPath)) { MessageBox.Show("Текущий файл не найден: " + (curPath ?? "нет"), "Ошибка", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
            try { System.Diagnostics.Process.Start(tm, string.Format("/base:\"{0}\" /mine:\"{1}\"", mainPath, curPath)); } catch (Exception ex) { MessageBox.Show("Ошибка запуска: " + ex.Message, "Ошибка", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        static Window ShowCollectionWindow(string title, List<string> items) {
            var w = new Window { Title = title, Width = 500, Height = 400, WindowStartupLocation = WindowStartupLocation.CenterScreen, FontSize = 12, FontFamily = new FontFamily("Segoe UI") };
            var lb = new ListBox { ItemsSource = items, FontSize = 12 };
            w.Content = new ScrollViewer { Content = lb, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            w.Show();
            return w;
        }

        static ContextMenu MakeCollectionMenu(string title, DataGrid dg) {
            var menu = new ContextMenu();
            var mi = new MenuItem { Header = "Открыть в окне" };
            mi.Click += (s, e2) => {
                var items = new List<string>();
                if (dg.ItemsSource != null) {
                    foreach (var row in (System.Collections.IEnumerable)dg.ItemsSource) {
                        var props = row.GetType().GetProperties();
                        if (props.Length > 0) items.Add(props[0].GetValue(row, null)?.ToString() ?? "");
                    }
                }
                if (items.Count > 0) ShowCollectionWindow(title, items);
            };
            menu.Items.Add(mi);
            return menu;
        }
        static void DoSearch(TextBox tb, TextBox searchBox, ref string lastIdx, ref int lastPos) {
            var needle = searchBox.Text;
            if (string.IsNullOrEmpty(needle) || string.IsNullOrEmpty(tb.Text)) return;
            if (needle != lastIdx) { lastIdx = needle; lastPos = 0; }
            var idx = tb.Text.IndexOf(needle, lastPos, StringComparison.OrdinalIgnoreCase);
            if (idx < 0 && lastPos > 0) { lastPos = 0; idx = tb.Text.IndexOf(needle, 0, StringComparison.OrdinalIgnoreCase); }
            if (idx >= 0) {
                tb.Focus(); tb.Select(idx, needle.Length);
                var lineIdx = tb.Text.Substring(0, idx).Split('\n').Length;
                tb.ScrollToLine(lineIdx - 1);
                lastPos = idx + needle.Length;
            }
        }
        static Encoding GetFileEncoding(string path) {
            try {
                var raw = File.ReadAllBytes(path);
                if (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF)
                    return Encoding.UTF8;
                if (raw.Length >= 2 && raw[0] == 0xFF && raw[1] == 0xFE)
                    return Encoding.Unicode;
                return Encoding.GetEncoding(1251);
            } catch { return Encoding.UTF8; }
        }
        static string Trunc(string s) { return s == null ? "" : (s.Length > 120 ? s.Substring(0, 120) + "..." : s); }

        static string S(Dictionary<string, object> d, string k) { return d.ContainsKey(k) ? d[k]?.ToString() ?? "" : ""; }
        static int I(Dictionary<string, object> d, string k) { return d.ContainsKey(k) ? Convert.ToInt32(d[k]) : 0; }
        static List<string> L(Dictionary<string, object> d, string k) {
            if (!d.ContainsKey(k) || d[k] == null) return new List<string>();
            return (d[k] as System.Collections.ArrayList)?.Cast<string>()?.ToList() ?? new List<string>();
        }
    }
}
