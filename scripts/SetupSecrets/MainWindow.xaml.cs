using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace SetupSecrets
{
    public partial class MainWindow : Window
    {
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int nL, int nT, int nR, int nB, int nWE, int nHE);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
        private const int WM_NCHITTEST = 0x0084, HTCAPTION = 2, RESIZE_MARGIN = 8;

        private static string _logPath = Path.Combine(
            Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".",
            $"tech_journal_{DateTime.Now:yyyyMMdd_HHmmss}.log");
        private static readonly object _logLock = new();
        private static bool _exitAfterAutoTest;
        private static List<string> _autoTestCmds = new();
        private static int _autoTestIdx;

        private string _secretsPath;
        private string _ewsEnvPath;
        private const string Entropy = "AIS.Secrets.2026";

        public MainWindow()
        {
            InitializeComponent();
            Log("START", "Setup-Secrets");

            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location) ?? ".";
            _secretsPath = Path.GetFullPath(Path.Combine(exeDir, "..\\..\\..\\config\\.local_secrets.json"));
            _ewsEnvPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".config", "ews-mcp", "credentials.env");

            if (!File.Exists(_secretsPath))
            {
                string alt = Path.GetFullPath(Path.Combine(exeDir, "..\\config\\.local_secrets.json"));
                if (File.Exists(alt)) _secretsPath = alt;
            }
            LoadSecrets();
            ParseAutoTestArgs();
        }

        public static void Log(string level, string msg)
        {
            string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {msg}";
            lock (_logLock) { File.AppendAllText(_logPath, line + Environment.NewLine); }
            Console.WriteLine(line);
        }

        private void ParseAutoTestArgs()
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
                if (args[i] == "--autotest" && i + 1 < args.Length)
                {
                    string file = args[i + 1];
                    if (File.Exists(file)) { _autoTestCmds = File.ReadAllLines(file).ToList(); _exitAfterAutoTest = true; Log("AUTOTEST", $"Loaded {_autoTestCmds.Count} commands"); }
                }
        }

        private void RunAutoTest()
        {
            if (_autoTestIdx >= _autoTestCmds.Count) { Log("AUTOTEST", "Done"); if (_exitAfterAutoTest) { var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) }; t.Tick += (s, e) => { t.Stop(); Close(); }; t.Start(); } return; }
            string line = _autoTestCmds[_autoTestIdx++].Trim();
            if (string.IsNullOrEmpty(line)) { RunAutoTest(); return; }
            Log("AUTOTEST", $"CMD: {line}");
            var parts = line.Split(' ', 3);
            string cmd = parts[0].ToLower(), a1 = parts.Length > 1 ? parts[1] : "", a2 = parts.Length > 2 ? parts[2] : "";
            try
            {
                switch (cmd)
                {
                    case "set": SetField(a1, a2); break;
                    case "save": BtnSave_Click(null!, null!); break;
                    case "close": Close(); return;
                    case "wait": Thread.Sleep(int.Parse(a1)); break;
                    case "log": Log("AUTOTEST", a1); break;
                }
            }
            catch (Exception ex) { Log("ERROR", $"AutoTest: {ex.Message}"); }
            var tt = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
            tt.Tick += (s, e) => { tt.Stop(); RunAutoTest(); }; tt.Start();
        }

        private void SetField(string name, string value)
        {
            switch (name)
            {
                case "sybase": tbSybasePass.Text = value; break;
                case "vss_user": tbVssUser.Text = value; break;
                case "vss_pass": tbVssPass.Text = value; break;
                case "vss_master": tbVssMaster.Text = value; break;
                case "jira_api": tbJiraApi.Text = value; break;
                case "jira_token": tbJiraToken.Text = value; break;
                case "oc_pass": tbOcPass.Text = value; break;
                case "ews_url": tbEwsUrl.Text = value; break;
                case "ews_email": tbEwsEmail.Text = value; break;
                case "ews_user": tbEwsUser.Text = value; break;
                case "ews_pass": tbEwsPass.Text = value; break;
            }
            Log("AUTOTEST", $"set {name}");
        }

        private void LoadSecrets()
        {
            int failed = 0;
            if (!File.Exists(_secretsPath)) { Log("WARN", ".local_secrets.json not found"); return; }
            try
            {
                var json = File.ReadAllText(_secretsPath);
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                if (root.TryGetProperty("sybase", out var sy)) failed += SetVal(sy, "password_encrypted", tbSybasePass);
                if (root.TryGetProperty("vss", out var vs))
                {
                    SetVal(vs, "user", tbVssUser, false);
                    failed += SetVal(vs, "password_encrypted", tbVssPass);
                    failed += SetVal(vs, "master_key_encrypted", tbVssMaster);
                }
                if (root.TryGetProperty("jira", out var ji))
                {
                    failed += SetVal(ji, "api_token_encrypted", tbJiraApi);
                    failed += SetVal(ji, "token_encrypted", tbJiraToken);
                }
                if (root.TryGetProperty("openCodeApi", out var oc))
                    SetVal(oc, "password", tbOcPass, false);

                Log("INFO", $"Loaded .local_secrets.json (decrypt failed: {failed})");
                if (failed > 0)
                    MessageBox.Show($"{failed} полей не удалось расшифровать (другой компьютер/пользователь).\nПоля оставлены пустыми — введите значения заново.",
                        "Внимание", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            catch (Exception ex) { Log("ERROR", $"Load: {ex.Message}"); }
            LoadEwsEnv();
        }

        private void LoadEwsEnv()
        {
            if (!File.Exists(_ewsEnvPath)) return;
            try
            {
                foreach (var line in File.ReadAllLines(_ewsEnvPath))
                {
                    var t = line.Trim();
                    if (string.IsNullOrEmpty(t) || t.StartsWith("#")) continue;
                    var eq = t.IndexOf('=');
                    if (eq < 0) continue;
                    var k = t.Substring(0, eq).Trim().ToUpper();
                    var v = t.Substring(eq + 1).Trim();
                    if ((v.StartsWith("\"") && v.EndsWith("\"")) || (v.StartsWith("'") && v.EndsWith("'")))
                        v = v.Substring(1, v.Length - 2);
                    switch (k)
                    {
                        case "EWS_SERVER_URL": tbEwsUrl.Text = v; break;
                        case "EWS_EMAIL": tbEwsEmail.Text = v; break;
                        case "EWS_USERNAME": tbEwsUser.Text = v; break;
                        case "EWS_PASSWORD": tbEwsPass.Text = v; break;
                    }
                }
                Log("INFO", "Loaded EWS credentials");
            }
            catch { }
        }

        private static int SetVal(JsonElement el, string key, TextBox tb, bool decrypt = true)
        {
            if (el.TryGetProperty(key, out var v))
            {
                var val = v.GetString() ?? "";
                if (decrypt && !string.IsNullOrEmpty(val))
                {
                    var dec = Decrypt(val);
                    if (string.IsNullOrEmpty(dec) && val.Length > 10)
                    {
                        Log("WARN", $"Не расшифровано: {key}");
                        tb.Text = "";
                        return 1;
                    }
                    val = dec;
                }
                tb.Text = val;
            }
            return 0;
        }

        private void BtnSave_Click(object sender, RoutedEventArgs e)
        {
            Log("CLICK", "save");
            try
            {
                SaveSecrets();
                SaveEwsEnv();
                Log("INFO", "Saved all secrets");
                MessageBox.Show("Секреты сохранены.\n\n.local_secrets.json — config/\nEWS — ~/.config/ews-mcp/credentials.env",
                    "Сохранено", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            catch (Exception ex) { Log("ERROR", $"Save: {ex.Message}"); }
        }

        private void SaveSecrets()
        {
            string dir = Path.GetDirectoryName(_secretsPath)!;
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            var obj = new
            {
                _comment = "Хранилище секретов. НИКОГДА не коммитить.",
                _date = DateTime.Now.ToString("yyyy-MM-dd"),
                sybase = new { password_encrypted = Enc(tbSybasePass.Text) },
                vss = new { user = tbVssUser.Text, password_encrypted = Enc(tbVssPass.Text), master_key_encrypted = tbVssMaster.Text },
                jira = new { api_token_encrypted = Enc(tbJiraApi.Text), token_encrypted = Enc(tbJiraToken.Text) },
                openCodeApi = new { password = tbOcPass.Text }
            };
            var json = JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
            File.WriteAllText(_secretsPath, json, new UTF8Encoding(false));
            Log("INFO", $"Saved: {_secretsPath}");
        }

        private void SaveEwsEnv()
        {
            string dir = Path.GetDirectoryName(_ewsEnvPath)!;
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            var sb = new StringBuilder();
            sb.AppendLine($"EWS_SERVER_URL=\"{tbEwsUrl.Text}\"");
            sb.AppendLine($"EWS_EMAIL=\"{tbEwsEmail.Text}\"");
            sb.AppendLine($"EWS_USERNAME=\"{tbEwsUser.Text}\"");
            sb.AppendLine($"EWS_PASSWORD=\"{tbEwsPass.Text}\"");
            sb.AppendLine("EWS_INSECURE_SKIP_VERIFY=true");
            sb.AppendLine("EWS_AUTH_TYPE=ntlm");
            File.WriteAllText(_ewsEnvPath, sb.ToString());
            Log("INFO", $"Saved: {_ewsEnvPath}");
        }

        private static string Enc(string val) => string.IsNullOrEmpty(val) ? "" : Encrypt(val);
        private static string Encrypt(string plain)
        {
            var data = Encoding.UTF8.GetBytes(plain);
            var entropy = Encoding.UTF8.GetBytes(Entropy);
            var encrypted = ProtectedData.Protect(data, entropy, DataProtectionScope.CurrentUser);
            return Convert.ToBase64String(encrypted);
        }
        private static string Decrypt(string base64)
        {
            try
            {
                var data = Convert.FromBase64String(base64);
                var entropy = Encoding.UTF8.GetBytes(Entropy);
                var decrypted = ProtectedData.Unprotect(data, entropy, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(decrypted);
            }
            catch { return ""; }
        }

        private void BtnMin_Click(object sender, RoutedEventArgs e) { WindowState = WindowState.Minimized; }
        private void BtnClose_Click(object sender, RoutedEventArgs e) { Log("CLICK", "close"); Close(); }
        private void Window_KeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Escape) Close(); }
        private void Window_Loaded(object sender, RoutedEventArgs e) { Log("INFO", "Window loaded"); ApplyRounded(); if (_autoTestCmds.Count > 0) { var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) }; t.Tick += (s, ev) => { t.Stop(); RunAutoTest(); }; t.Start(); } }
        private void Window_SizeChanged(object sender, SizeChangedEventArgs e) { ApplyRounded(); }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2) { WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized; return; }
            try { DragMove(); } catch { }
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            if (PresentationSource.FromVisual(this) is HwndSource hs) hs.AddHook(WndProc);
        }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_NCHITTEST)
            {
                int x = (int)(lParam.ToInt64() & 0xFFFF), y = (int)((lParam.ToInt64() >> 16) & 0xFFFF);
                var p = PointFromScreen(new Point(x, y)); double w = ActualWidth, h = ActualHeight; int m = RESIZE_MARGIN;
                if (p.Y < 42 && !(p.X < m) && !(p.X > w - m) && !(p.Y < m)) { handled = true; return (IntPtr)HTCAPTION; }
                if (p.X < m && p.Y < m) { handled = true; return (IntPtr)13; }
                if (p.X > w - m && p.Y < m) { handled = true; return (IntPtr)14; }
                if (p.X < m && p.Y > h - m) { handled = true; return (IntPtr)16; }
                if (p.X > w - m && p.Y > h - m) { handled = true; return (IntPtr)17; }
                if (p.X < m) { handled = true; return (IntPtr)10; }
                if (p.X > w - m) { handled = true; return (IntPtr)11; }
                if (p.Y < m) { handled = true; return (IntPtr)12; }
                if (p.Y > h - m) { handled = true; return (IntPtr)15; }
            }
            return IntPtr.Zero;
        }

        private void ApplyRounded()
        {
            try
            {
                var hWnd = new WindowInteropHelper(this).Handle;
                if (hWnd == IntPtr.Zero) return;
                int w = (int)ActualWidth, h = (int)ActualHeight;
                if (w <= 0 || h <= 0) { w = 680; h = 520; }
                var rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, 36, 36);
                SetWindowRgn(hWnd, rgn, true); DeleteObject(rgn);
            }
            catch { }
        }
    }
}
