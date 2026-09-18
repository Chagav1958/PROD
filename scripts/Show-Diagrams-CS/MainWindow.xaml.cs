using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Show_Diagrams
{
    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
        private const int WM_NCHITTEST = 0x0084, HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17, HTCAPTION = 2;
        private const int RESIZE_MARGIN = 8;

        private static string _logPath = Path.Combine(AppContext.BaseDirectory, $"tech_journal_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        private static readonly object _logLock = new();
        private static bool _exitAfterAutoTest = false;
        private static List<string> _autoTestCommands = new();
        private static int _autoTestCmdIndex = 0;

        private readonly string _vizRoot;
        private readonly string _bpRoot;
        private readonly string _pilotDir;
        private readonly string _fullDir;
        private readonly string _outputDir;
        private readonly string _bpDocsDir;
        private readonly string _tempDir;
        private readonly string _plantumlJar;

        private string _currentFilter = "";

        private static readonly (string Header, string[] Files, string Category)[] TabDefs = new[]
        {
            ("Модули", new[] { "modules.mmd", "modules.svg", "modules.puml", "modules.dot", "modules.html" }, "Dev"),
            ("Классы PB", new[] { "classes.mmd", "class-db-link.mmd", "class-db-link.svg" }, "Dev"),
            ("Схема БД", new[] { "db-schema.mmd", "db-schema.puml", "db-schema.svg" }, "Dev"),
            ("Пилот", new[] { "pilot.mmd", "pilot.svg", "pilot.puml", "pilot.dot", "pilot.html" }, "Pilot"),
            ("Бизнес-процессы", new[] { "gen_bp_BP_01.mmd", "gen_bp_BP_02.mmd", "gen_bp_BP_03.mmd", "gen_consolidated.mmd", "gen_tech_map.mmd", "business-process-bpmn.md" }, "BP"),
            ("Сводная", new[] { "consolidated-diagram.mmd", "consolidated-diagram.svg", "consolidated-report.md" }, "Final"),
        };

        private readonly Dictionary<string, string> _mermaidTheme = new()
        {
            ["pilot.mmd"] = "base", ["classes.mmd"] = "base", ["class-db-link.mmd"] = "base",
            ["modules.mmd"] = "default", ["db-schema.mmd"] = "default",
            ["consolidated-diagram.mmd"] = "default",
            ["gen_consolidated.mmd"] = "default", ["gen_tech_map.mmd"] = "default"
        };

        public MainWindow()
        {
            InitializeComponent();
            Log("INFO", "Window constructed");
            Log("INFO", $"EXE path: {AppContext.BaseDirectory}");
            Log("INFO", $"Args: {string.Join(" | ", Environment.GetCommandLineArgs())}");

            _vizRoot = @"C:\AIS\AI\Visualization";
            _bpRoot = @"C:\AIS\AI\BP";
            _pilotDir = Path.Combine(_vizRoot, "diagrams", "pilot");
            _fullDir = Path.Combine(_vizRoot, "diagrams", "full");
            _outputDir = Path.Combine(_vizRoot, "output");
            _bpDocsDir = Path.Combine(_bpRoot, "docs");
            _tempDir = Path.Combine(Path.GetTempPath(), "ais-diagrams");
            _plantumlJar = @"C:\AIS\AI\Tools\plantuml.jar";
            Directory.CreateDirectory(_tempDir);

            EnsureBrowserEmulation();
            BuildTabs("");
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            try { lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine, Encoding.UTF8); } Console.WriteLine(line); } catch { }
        }

        /// <summary>
        /// Принудительно включает IE11 Edge-режим для WebBrowser в текущем процессе.
        /// Ключ реестра: FEATURE_BROWSER_EMULATION = 11001 (IE11 Edge mode)
        /// </summary>
        private static void EnsureBrowserEmulation()
        {
            string procName = Process.GetCurrentProcess().ProcessName + ".exe";
            try
            {
                using var key = Registry.CurrentUser.CreateSubKey(
                    @"Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION");
                object? existing = key?.GetValue(procName);
                if (existing is not int val || val != 11001)
                {
                    key?.SetValue(procName, 11001, RegistryValueKind.DWord);
                    Log("INFO", $"FEATURE_BROWSER_EMULATION set: {procName}=11001");
                }
            }
            catch (Exception ex) { Log("ERROR", $"BrowserEmulation: {ex.Message}"); }
        }

        private void BuildTabs(string filter)
        {
            _currentFilter = filter;
            tabControl.Items.Clear();

            foreach (var (header, files, category) in TabDefs)
            {
                string dir = category switch
                {
                    "Dev" => _fullDir, "Pilot" => _pilotDir, "BP" => _bpDocsDir, "Final" => _outputDir, _ => _fullDir
                };

                var available = files.Where(f => File.Exists(Path.Combine(dir, f))).ToArray();
                if (available.Length == 0 && !string.IsNullOrEmpty(filter)) continue;

                if (!string.IsNullOrEmpty(filter))
                    available = available.Where(f => CountMatches(File.ReadAllText(Path.Combine(dir, f), Encoding.UTF8), filter) > 0).ToArray();

                if (available.Length == 0) continue;

                var ti = new TabItem { Header = $"{header} ({available.Length})" };
                ti.Content = available.Length == 1
                    ? BuildSingleViewer(dir, available[0])
                    : BuildMultiViewer(dir, available);
                tabControl.Items.Add(ti);
            }

            if (tabControl.Items.Count == 0)
            {
                var ti = new TabItem { Header = "Нет данных" };
                ti.Content = new TextBlock
                {
                    Text = $"Диаграммы не найдены.\nПроверьте: {_fullDir}, {_bpDocsDir}",
                    FontSize = 11, Foreground = Brushes.Red, Margin = new Thickness(10)
                };
                tabControl.Items.Add(ti);
            }
            Log("INFO", $"Built {tabControl.Items.Count} tabs");
        }

        private UIElement BuildMultiViewer(string dir, string[] files)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(6) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var lb = new ListBox { FontSize = 11, Background = Brushes.Transparent, BorderBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#CBD5E0")), BorderThickness = new Thickness(1) };
            foreach (var f in files) lb.Items.Add($"{Path.GetFileNameWithoutExtension(f)} [{Path.GetExtension(f)}]");
            lb.SelectedIndex = 0;
            Grid.SetColumn(lb, 0);

            var splitter = new GridSplitter { Width = 4, HorizontalAlignment = HorizontalAlignment.Stretch, Background = Brushes.Transparent, ResizeDirection = GridResizeDirection.Columns };
            Grid.SetColumn(splitter, 1);

            var panel = new Border { BorderBrush = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#CBD5E0")), BorderThickness = new Thickness(1), Background = Brushes.White };
            panel.Child = BuildSingleViewer(dir, files[0]);
            Grid.SetColumn(panel, 2);

            lb.SelectionChanged += (s, e) => { if (lb.SelectedIndex >= 0 && lb.SelectedIndex < files.Length) panel.Child = BuildSingleViewer(dir, files[lb.SelectedIndex]); };

            grid.Children.Add(lb); grid.Children.Add(splitter); grid.Children.Add(panel);
            return grid;
        }

        private UIElement BuildSingleViewer(string dir, string fileName)
        {
            string path = Path.Combine(dir, fileName);
            if (!File.Exists(path))
                return ErrorBlock($"Файл не найден: {path}");

            string ext = Path.GetExtension(fileName).ToLowerInvariant();

            return ext switch
            {
                ".svg" => BuildSvgViewer(path, fileName),
                ".mmd" => BuildMmdViewer(path, fileName),
                ".html" => BuildExternalViewer(path, fileName, "D3 интерактивный граф — Drag = перетащить узел | Scroll = зум | Drag фон = панорама", static p => Process.Start(new ProcessStartInfo(p) { UseShellExecute = true })),
                ".puml" => BuildPumlViewer(path, fileName),
                ".dot" => BuildDotViewer(path, fileName),
                ".md" => BuildMarkdownViewer(path, fileName),
                _ => BuildTextViewer(path, fileName)
            };
        }

        private UIElement BuildSvgViewer(string path, string fileName)
        {
            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var panel = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
            panel.Children.Add(new TextBlock { Text = "SVG диаграмма", FontSize = 16, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#1A3A60")), HorizontalAlignment = HorizontalAlignment.Center });
            panel.Children.Add(new TextBlock { Text = fileName, FontSize = 11, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#4A5568")), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 20) });

            var btnOpen = new Button { Content = "Открыть в браузере", Width = 280, Height = 48, FontSize = 14, FontWeight = FontWeights.Bold, Cursor = Cursors.Hand };
            btnOpen.Click += (s, e) => { try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); Log("CLICK", "svg-browser"); } catch { } };
            panel.Children.Add(btnOpen);

            var btnText = new Button { Content = "Показать исходный код", Width = 200, Height = 32, FontSize = 11, Cursor = Cursors.Hand, Margin = new Thickness(0, 10, 0, 0) };
            btnText.Click += (s, e) => { ShowTextDialog(path, fileName); };
            panel.Children.Add(btnText);
            Grid.SetRow(panel, 0);

            var infoBar = FileInfoBar(path, fileName, "SVG (открывается в браузере)");
            infoBar.Children.Add(OpenBtn(path, fileName));
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(panel); grid.Children.Add(infoBar);
            return grid;
        }

        private UIElement BuildMmdViewer(string path, string fileName)
        {
            string content;
            try { content = File.ReadAllText(path, Encoding.UTF8); }
            catch { return ErrorBlock($"Ошибка чтения: {path}"); }

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var panel = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
            panel.Children.Add(new TextBlock { Text = "Mermaid диаграмма", FontSize = 16, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#1A3A60")), HorizontalAlignment = HorizontalAlignment.Center });
            panel.Children.Add(new TextBlock { Text = fileName, FontSize = 11, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#4A5568")), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 20) });

            var btnHtml = new Button { Content = "Открыть в браузере (Mermaid.js)", Width = 280, Height = 48, FontSize = 14, FontWeight = FontWeights.Bold, Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 0, 10) };
            btnHtml.Click += (s, e) => { OpenMermaidInBrowser(path, fileName); };
            panel.Children.Add(btnHtml);

            var btnText = new Button { Content = "Показать исходный код", Width = 200, Height = 32, FontSize = 11, Cursor = Cursors.Hand };
            btnText.Click += (s, e) => { ShowTextDialog(path, fileName); };
            panel.Children.Add(btnText);
            Grid.SetRow(panel, 0);

            var infoBar = FileInfoBar(path, fileName, "Mermaid (открывается в браузере)");
            infoBar.Children.Add(OpenBtn(path, fileName));
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(panel); grid.Children.Add(infoBar);
            return grid;
        }

        private void OpenMermaidInBrowser(string mmdPath, string fileName)
        {
            try
            {
                string htmlPath = Path.Combine(_tempDir, Path.GetFileNameWithoutExtension(fileName) + ".html");
                string html = GenerateMermaidHtml(mmdPath, fileName);
                File.WriteAllText(htmlPath, html, Encoding.UTF8);
                Log("MH", $"Generated HTML: {htmlPath}");
                Process.Start(new ProcessStartInfo(htmlPath) { UseShellExecute = true });
                Log("MH", "Browser opened");
            }
            catch (Exception ex) { Log("ERROR", $"MermaidHtml: {ex.Message}"); MessageBox.Show($"Ошибка: {ex.Message}", "Mermaid", MessageBoxButton.OK, MessageBoxImage.Error); }
        }

        private UIElement BuildDotViewer(string path, string fileName)
        {
            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var panel = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
            panel.Children.Add(new TextBlock { Text = "Graphviz DOT диаграмма", FontSize = 16, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#1A3A60")), HorizontalAlignment = HorizontalAlignment.Center });
            panel.Children.Add(new TextBlock { Text = fileName, FontSize = 11, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#4A5568")), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 20) });

            var btnOpen = new Button { Content = "Открыть в браузере (Viz.js)", Width = 280, Height = 48, FontSize = 14, FontWeight = FontWeights.Bold, Cursor = Cursors.Hand, Margin = new Thickness(0, 0, 0, 10) };
            btnOpen.Click += (s, e) => { OpenDotInBrowser(path, fileName); };
            panel.Children.Add(btnOpen);

            var btnText = new Button { Content = "Показать исходный код", Width = 200, Height = 32, FontSize = 11, Cursor = Cursors.Hand };
            btnText.Click += (s, e) => { ShowTextDialog(path, fileName); };
            panel.Children.Add(btnText);
            Grid.SetRow(panel, 0);

            var infoBar = FileInfoBar(path, fileName, "Graphviz DOT (открывается в браузере)");
            infoBar.Children.Add(OpenBtn(path, fileName));
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(panel); grid.Children.Add(infoBar);
            return grid;
        }

        private void OpenDotInBrowser(string dotPath, string fileName)
        {
            try
            {
                string dotSrc = File.ReadAllText(dotPath, Encoding.UTF8);
                string esc = EscapeJsTemplate(dotSrc);
                string html = @"<!DOCTYPE html><html><head><meta charset='utf-8'><title>" + fileName + @"</title>
<style>body{font-family:Segoe UI;margin:20px;background:#fff}#out{max-width:100%;overflow-x:auto}.err{color:red;display:none}</style></head>
<body><h2>" + fileName + @"</h2><div id='out'></div><div id='err' class='err'></div>
<script src='https://cdn.jsdelivr.net/npm/@viz-js/viz@3/lib/viz-standalone.js'></script>
<script>Viz.instance().then(function(v){try{var s=v.renderString(" + esc + @",{format:'svg'});document.getElementById('out').innerHTML=s}catch(e){document.getElementById('err').style.display='block';document.getElementById('err').textContent='Error: '+e}})</script>
</body></html>";
                string htmlPath = Path.Combine(_tempDir, Path.GetFileNameWithoutExtension(fileName) + ".html");
                File.WriteAllText(htmlPath, html, Encoding.UTF8);
                Process.Start(new ProcessStartInfo(htmlPath) { UseShellExecute = true });
                Log("DOT", "Browser opened");
            }
            catch (Exception ex) { Log("ERROR", $"DotBrowser: {ex.Message}"); }
        }

        private UIElement BuildTextWithPreview(string path, string fileName, string info)
        {
            string content;
            try { content = File.ReadAllText(path, Encoding.UTF8); }
            catch (Exception ex) { return ErrorBlock($"Ошибка чтения: {ex.Message}"); }

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var tb = new TextBox
            {
                Text = content, IsReadOnly = true,
                FontFamily = new FontFamily("Consolas"), FontSize = 11,
                AcceptsReturn = true, VerticalScrollBarVisibility = ScrollBarVisibility.Visible,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                Background = Brushes.White, BorderThickness = new Thickness(0),
                Padding = new Thickness(6), TextWrapping = TextWrapping.NoWrap
            };
            Grid.SetRow(tb, 0);

            var infoBar = FileInfoBar(path, fileName, info);
            infoBar.Children.Add(OpenBtn(path, fileName));
            if (Path.GetExtension(fileName).ToLowerInvariant() == ".mmd")
                infoBar.Children.Add(RenderMmdBtn(path, fileName));
            var btnCopy = new Button { Content = "Копировать", Width = 90, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
            btnCopy.Click += (s, e) => { try { Clipboard.SetText(content); Log("CLICK", "copy"); } catch { } };
            infoBar.Children.Add(btnCopy);
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(tb); grid.Children.Add(infoBar);
            return grid;
        }

        private UIElement BuildPumlViewer(string path, string fileName)
        {
            string content;
            try { content = File.ReadAllText(path, Encoding.UTF8); }
            catch (Exception ex) { return ErrorBlock($"Ошибка чтения: {ex.Message}"); }

            string pngPath = Path.ChangeExtension(path, ".png");
            if (File.Exists(pngPath) && new FileInfo(pngPath).Length > 0)
                return BuildPngViewer(pngPath, Path.GetFileName(pngPath), path, fileName);

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var tb = new TextBox
            {
                Text = content, IsReadOnly = true,
                FontFamily = new FontFamily("Segoe UI, Consolas"), FontSize = 11,
                AcceptsReturn = true, VerticalScrollBarVisibility = ScrollBarVisibility.Visible,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                Background = Brushes.White, BorderThickness = new Thickness(0),
                Padding = new Thickness(6), TextWrapping = TextWrapping.NoWrap
            };
            Grid.SetRow(tb, 0);

            var infoBar = FileInfoBar(path, fileName, "PlantUML диаграмма");
            infoBar.Children.Add(OpenBtn(path, fileName));
            infoBar.Children.Add(RenderPumlBtn(path, fileName, pngPath));
            var btnOnline = new Button { Content = "Online", Width = 70, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
            var raw = Convert.ToBase64String(Encoding.UTF8.GetBytes(content));
            var enc = raw.Replace("+", "-").Replace("/", "_");
            var onlineUrl = $"https://www.plantuml.com/plantuml/uml/~h{enc}";
            btnOnline.Click += (s, e) => { try { Process.Start(new ProcessStartInfo(onlineUrl) { UseShellExecute = true }); } catch { } };
            infoBar.Children.Add(btnOnline);
            var btnCopy = new Button { Content = "Копировать", Width = 90, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
            btnCopy.Click += (s, e) => { try { Clipboard.SetText(content); } catch { } };
            infoBar.Children.Add(btnCopy);
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(tb); grid.Children.Add(infoBar);
            return grid;
        }

        private UIElement BuildPngViewer(string pngPath, string pngName, string? sourcePath, string? sourceName)
        {
            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var img = new System.Windows.Controls.Image();
            try
            {
                var bmp = new System.Windows.Media.Imaging.BitmapImage();
                bmp.BeginInit(); bmp.UriSource = new Uri(pngPath); bmp.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad; bmp.EndInit();
                img.Source = bmp; img.Stretch = System.Windows.Media.Stretch.Uniform;
            }
            catch { }
            Grid.SetRow(img, 0);

            var infoBar = FileInfoBar(pngPath, pngName, "PNG диаграмма");
            infoBar.Children.Add(new Button { Content = "Открыть файл", Width = 100, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand, Command = null });
            if (sourcePath != null)
            {
                var btnSource = new Button { Content = "Исходник .puml", Width = 120, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
                btnSource.Click += (s, e) => { ShowTextDialog(sourcePath, sourceName ?? ""); };
                infoBar.Children.Add(btnSource);
            }
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(img); grid.Children.Add(infoBar);
            return grid;
        }

        private Button RenderPumlBtn(string pumlPath, string fileName, string pngPath)
        {
            var btn = new Button { Content = "Render PNG", Width = 110, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
            btn.Click += (s, e) =>
            {
                try
                {
                    if (!File.Exists(_plantumlJar)) { MessageBox.Show($"plantuml.jar: {_plantumlJar}", "Ошибка", MessageBoxButton.OK, MessageBoxImage.Warning); return; }
                    try { File.Delete(pngPath); } catch { }
                    var psi = new ProcessStartInfo("java", $"-Djava.awt.headless=true -Dfile.encoding=UTF-8 -jar \"{_plantumlJar}\" -charset UTF-8 -tpng \"{pumlPath}\" -o \"{Path.GetDirectoryName(pumlPath)}\"")
                    {
                        UseShellExecute = false, CreateNoWindow = true
                    };
                    using var proc = Process.Start(psi);
                    proc?.WaitForExit(15000);
                    Log("RENDER", $"plantuml {fileName}: exit={proc?.ExitCode}");

                    if (File.Exists(pngPath) && new FileInfo(pngPath).Length > 0)
                    {
                        BuildTabs(_currentFilter);
                        Log("RENDER", $"PNG ok: {Path.GetFileName(pngPath)} ({new FileInfo(pngPath).Length} bytes)");
                        MessageBox.Show($"PNG сгенерирован!\n{Path.GetFileName(pngPath)}", "Render PNG", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                    else
                        MessageBox.Show("Не удалось сгенерировать PNG.\nПроверьте синтаксис PlantUML.", "Render PNG", MessageBoxButton.OK, MessageBoxImage.Warning);
                }
                catch (Exception ex) { Log("ERROR", $"RenderPuml: {ex.Message}"); }
            };
            return btn;
        }

        private UIElement BuildExternalViewer(string path, string fileName, string info, Action<string> openAction)
        {
            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var placeholder = new TextBlock
            {
                Text = $"{info}\n\nНажмите «Открыть в браузере» для просмотра.",
                FontSize = 13, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#4A5568")),
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Center
            };
            Grid.SetRow(placeholder, 0);

            var infoBar = FileInfoBar(path, fileName, info);
            var btnOpen = new Button { Content = "Открыть в браузере", Width = 150, Height = 38, FontSize = 12, FontWeight = FontWeights.Bold, Margin = new Thickness(4, 0, 0, 0), Cursor = Cursors.Hand };
            btnOpen.Click += (s, e) => { openAction(path); Log("CLICK", $"open:{fileName}"); };
            infoBar.Children.Add(btnOpen);
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(placeholder); grid.Children.Add(infoBar);
            return grid;
        }

        private UIElement BuildMarkdownViewer(string path, string fileName)
        {
            string content;
            try { content = File.ReadAllText(path, Encoding.UTF8); }
            catch (Exception ex) { return ErrorBlock($"Ошибка чтения: {ex.Message}"); }

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            // Извлекаем Mermaid-блоки и показываем их
            var extracted = new StringBuilder();
            bool inMermaid = false;
            foreach (var line in content.Split('\n'))
            {
                if (line.Trim() == "```mermaid") { inMermaid = true; extracted.AppendLine("// --- Mermaid block ---"); continue; }
                if (line.Trim() == "```") { inMermaid = false; continue; }
                if (inMermaid) extracted.AppendLine(line);
                else if (!line.StartsWith("#") && !string.IsNullOrWhiteSpace(line))
                    extracted.AppendLine($"// {line.Trim()}");
            }

            var tb = new TextBox
            {
                Text = extracted.ToString(), IsReadOnly = true,
                FontFamily = new FontFamily("Consolas"), FontSize = 11,
                AcceptsReturn = true, VerticalScrollBarVisibility = ScrollBarVisibility.Visible,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                Background = Brushes.White, BorderThickness = new Thickness(0),
                Padding = new Thickness(6), TextWrapping = TextWrapping.NoWrap
            };
            Grid.SetRow(tb, 0);

            var infoBar = FileInfoBar(path, fileName, "Markdown с Mermaid");
            infoBar.Children.Add(OpenBtn(path, fileName));
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(tb); grid.Children.Add(infoBar);
            return grid;
        }

        private UIElement BuildTextViewer(string path, string fileName)
        {
            string content;
            try { content = File.ReadAllText(path, Encoding.UTF8); }
            catch (Exception ex) { return ErrorBlock($"Ошибка чтения: {ex.Message}"); }

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            var tb = new TextBox
            {
                Text = content, IsReadOnly = true,
                FontFamily = new FontFamily("Consolas"), FontSize = 11,
                AcceptsReturn = true, VerticalScrollBarVisibility = ScrollBarVisibility.Visible,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                Background = Brushes.White, BorderThickness = new Thickness(0),
                Padding = new Thickness(6), TextWrapping = TextWrapping.NoWrap
            };
            Grid.SetRow(tb, 0);

            var infoBar = FileInfoBar(path, fileName, "Текстовый файл");
            infoBar.Children.Add(OpenBtn(path, fileName));
            Grid.SetRow(infoBar, 1);

            grid.Children.Add(tb); grid.Children.Add(infoBar);
            return grid;
        }

        private Button RenderMmdBtn(string path, string fileName)
        {
            var btn = new Button { Content = "Render SVG", Width = 110, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
            btn.Click += (s, e) =>
            {
                try
                {
                    string mmdc = Path.Combine(_vizRoot, "node_modules", ".bin", "mmdc.cmd");
                    string svgOut = Path.ChangeExtension(path, ".svg");
                    if (!File.Exists(mmdc)) { MessageBox.Show("mmdc не найден.", "Ошибка", MessageBoxButton.OK, MessageBoxImage.Warning); return; }

                    // Удаляем старый SVG чтобы гарантировать свежий рендер
                    try { File.Delete(svgOut); } catch { }

                    var psi = new ProcessStartInfo
                    {
                        FileName = mmdc,
                        Arguments = $"-i \"{path}\" -o \"{svgOut}\" -w 1200",
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        WorkingDirectory = _vizRoot
                    };
                    using var proc = Process.Start(psi);
                    proc?.WaitForExit(15000);
                    Log("RENDER", $"mmdc {fileName}: exit={proc?.ExitCode}");

                    if (File.Exists(svgOut))
                    {
                        BuildTabs(_currentFilter);
                        Log("RENDER", $"SVG ok: {Path.GetFileName(svgOut)} ({new FileInfo(svgOut).Length} bytes)");
                        MessageBox.Show($"SVG сгенерирован!\n{Path.GetFileName(svgOut)}", "Render SVG", MessageBoxButton.OK, MessageBoxImage.Information);
                    }
                    else
                    {
                        MessageBox.Show($"Не удалось сгенерировать SVG.\nВозможно, синтаксическая ошибка в Mermaid.\n\nФайл: {fileName}", "Render SVG", MessageBoxButton.OK, MessageBoxImage.Warning);
                    }
                }
                catch (Exception ex) { Log("ERROR", $"RenderMmd: {ex.Message}"); MessageBox.Show(ex.Message, "Ошибка", MessageBoxButton.OK, MessageBoxImage.Error); }
            };
            return btn;
        }

        private static StackPanel FileInfoBar(string path, string fileName, string info)
        {
            var sp = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 2, 4, 2) };
            var fi = new FileInfo(path);
            sp.Children.Add(new TextBlock
            {
                Text = $"{fileName} | {FormatSize(fi.Length)} | {fi.LastWriteTime:dd.MM.yyyy HH:mm} | {info}",
                FontSize = 10, Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#4A5568")),
                VerticalAlignment = VerticalAlignment.Center
            });
            return sp;
        }

        private static Button OpenBtn(string path, string fileName)
        {
            var btn = new Button { Content = "Открыть файл", Width = 100, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
            btn.Click += (s, e) => { try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { } };
            return btn;
        }

        private Button OpenMermaidHtmlBtn(string path, string fileName)
        {
            var btn = new Button { Content = "Mermaid HTML", Width = 120, Height = 24, FontSize = 10, Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
            btn.Click += (s, e) =>
            {
                string html = GenerateMermaidHtml(path, fileName);
                string htmlPath = Path.Combine(_tempDir, Path.GetFileNameWithoutExtension(fileName) + ".html");
                File.WriteAllText(htmlPath, html, Encoding.UTF8);
                try { Process.Start(new ProcessStartInfo(htmlPath) { UseShellExecute = true }); Log("CLICK", $"mermaid-html:{fileName}"); }
                catch (Exception ex) { Log("ERROR", $"MermaidHtml: {ex.Message}"); }
            };
            return btn;
        }

        private string GenerateMermaidHtml(string mmdPath, string fileName)
        {
            string mmd = File.ReadAllText(mmdPath, Encoding.UTF8);
            bool isClass = mmd.TrimStart().StartsWith("classDiagram");
            string theme = isClass
                ? "theme:'base',themeVariables:{primaryColor:'#1A3A60',primaryTextColor:'#FFFFFF',secondaryColor:'#F0F9FF'}"
                : "theme:'default'";

            return @"<!DOCTYPE html><html lang='ru'><head><meta charset='utf-8'><title>" + fileName + @"</title>
<style>body{font-family:Segoe UI;margin:20px;background:#fff}h2{color:#1A3A60}.err{color:red;background:#fff0f0;padding:10px;border:1px solid red;border-radius:4px;display:none;white-space:pre-wrap;font-family:Consolas;font-size:11px}</style>
<script src='https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js'></script>
<script>mermaid.initialize({" + theme + @",startOnLoad:false,securityLevel:'loose'});</script></head>
<body><h2>" + fileName + @"</h2>
<pre class='mermaid'>
" + mmd + @"
</pre>
<div class='err' id='err'></div>
<script>
mermaid.run({querySelector:'.mermaid'}).catch(function(e){document.getElementById('err').style.display='block';document.getElementById('err').textContent='Error: '+e});
</script>
</body></html>";
        }

        private static string EscapeJsTemplate(string s) => "`" + s.Replace("\\", "\\\\").Replace("`", "\\`").Replace("$", "\\$") + "`";

        private void ShowTextDialog(string path, string fileName)
        {
            string content = File.ReadAllText(path, Encoding.UTF8);
            var dlg = new Window
            {
                Title = $"Исходник: {fileName}",
                Width = 800, Height = 600,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Owner = this,
                Content = new TextBox { Text = content, FontFamily = new FontFamily("Consolas"), FontSize = 11, IsReadOnly = true, VerticalScrollBarVisibility = ScrollBarVisibility.Visible, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(8) }
            };
            dlg.ShowDialog();
        }

        private static TextBlock ErrorBlock(string text) => new() { Text = text, FontSize = 11, Foreground = Brushes.Red, Margin = new Thickness(10), TextWrapping = TextWrapping.Wrap };

        private static int CountMatches(string text, string filter)
        {
            if (string.IsNullOrEmpty(filter)) return 0;
            int count = 0, idx = 0;
            while ((idx = text.IndexOf(filter, idx, StringComparison.OrdinalIgnoreCase)) >= 0) { count++; idx += filter.Length; }
            return count;
        }

        private static string FormatSize(long bytes) => bytes < 1024 ? $"{bytes} B" : bytes < 1024 * 1024 ? $"{bytes / 1024.0:F1} KB" : $"{bytes / 1024.0 / 1024.0:F2} MB";

        // ===== Search =====
        private void TxtSearch_TextChanged(object sender, TextChangedEventArgs e)
        {
            string filter = txtSearch.Text.Trim();
            if (filter.Length >= 2 || filter.Length == 0) { BuildTabs(filter); Log("SEARCH", $"filter='{filter}'"); }
        }
        private void TxtSearch_KeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) e.Handled = true; }
        private void BtnSearchDown_Click(object sender, RoutedEventArgs e) { Log("CLICK", "search_down"); }
        private void BtnSearchUp_Click(object sender, RoutedEventArgs e) { Log("CLICK", "search_up"); }

        // ===== Autotest =====
        private void ParseAutoTestArgs()
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
                if (args[i] == "--autotest" && i + 1 < args.Length)
                { string file = args[i + 1]; if (File.Exists(file)) { _autoTestCommands = File.ReadAllLines(file).ToList(); _exitAfterAutoTest = true; Log("AUTOTEST", $"Loaded {_autoTestCommands.Count} commands"); } }
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
                        if (arg == "refresh") BtnRefresh_Click(this, new RoutedEventArgs());
                        else if (arg == "close") BtnClose_Click(this, new RoutedEventArgs());
                        Log("AUTOTEST", $"click: {arg}"); break;
                    case "set_search": txtSearch.Text = arg; break;
                    case "wait": Thread.Sleep(int.Parse(arg)); break;
                    case "log": Log("AUTOTEST", arg); break;
                    case "resize": var sz = arg.Split(','); if (sz.Length == 2) { Width = int.Parse(sz[0]); Height = int.Parse(sz[1]); } break;
                }
            }
            catch (Exception ex) { Log("ERROR", $"CMD failed: {ex.Message}"); }
            if (_autoTestCmdIndex < _autoTestCommands.Count) { var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) }; t.Tick += (s, e) => { t.Stop(); RunAutoTestCommand(); }; t.Start(); }
            else { Log("AUTOTEST", "All commands done"); if (_exitAfterAutoTest) { var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, e) => { t.Stop(); Close(); }; t.Start(); } }
        }

        // ===== Window chrome =====
        private void Window_Loaded(object sender, RoutedEventArgs e) { Log("INFO", "Window loaded"); ApplyRoundedRegion(); if (_autoTestCommands.Count > 0) { var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, ev) => { t.Stop(); RunAutoTestCommand(); }; t.Start(); } }
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
                if (w <= 0 || h <= 0) { w = 1100; h = 720; }
                var rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, rgn, true); DeleteObject(rgn);
            }
            catch (Exception ex) { Log("ERROR", $"ApplyRoundedRegion: {ex.Message}"); }
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
        private void BtnRefresh_Click(object sender, RoutedEventArgs e) { Log("CLICK", "refresh"); BuildTabs(txtSearch.Text.Trim()); }
        private void BtnOpenFolder_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "openfolder");
            try { Process.Start(new ProcessStartInfo("explorer.exe", $"\"{_vizRoot}\"") { UseShellExecute = false }); }
            catch (Exception ex) { Log("ERROR", $"OpenFolder: {ex.Message}"); }
        }
    }
}
