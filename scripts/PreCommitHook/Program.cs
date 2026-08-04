// PreCommitHook: блокирует коммиты с паролями, токенами, логинами, API-ключами.
// Соответствует правилу: логины/пароли/токены НИКОГДА не в Git/GitHub — только в config/.local_secrets.json (.gitignore).
using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Collections.Generic;

namespace PreCommitHook
{
    class Program
    {
        // Паттерны секретов (регистронезависимые)
        static readonly Regex[] BlockPatterns = new[]
        {
            // password[=:]<quotes>value<quotes>  (допускает закрывающую кавычку JSON-ключа)
            new Regex("(?i)(password|пароль)\\s*[\"']?\\s*[=:]\\s*[\"'][^\"']{3,}[\"']", RegexOptions.Compiled),
            new Regex("(?i)password_encrypted", RegexOptions.Compiled),
            new Regex("(?i)(api[_-]?key|token|api[_-]?token|access[_-]?token)\\s*[\"']?\\s*[=:]\\s*[\"'][^\"']{3,}[\"']", RegexOptions.Compiled),
            new Regex("(?i)(secret[_-]?key|client[_-]?secret)\\s*[\"']?\\s*[=:]\\s*[\"'][^\"']{3,}[\"']", RegexOptions.Compiled),
            new Regex("(?i)(login|логин|user(name)?|учётн?ая[_\\s]запись)\\s*[\"']?\\s*[=:]\\s*[\"'][^\"']{3,}[\"']", RegexOptions.Compiled),
            // длинные строки (>32 символа) в кавычках — подозрительно
            new Regex("[\"'][A-Za-z0-9_\\-]{32,}[\"']", RegexOptions.Compiled),
            // Bearer <token>
            new Regex("Bearer\\s+[A-Za-z0-9._-]+", RegexOptions.Compiled),
        };

        static readonly HashSet<string> SkipExt = new(StringComparer.OrdinalIgnoreCase)
        {
            ".exe", ".dll", ".db", ".bin", ".png", ".jpg", ".jpeg", ".gif", ".ico",
            ".pdf", ".zip", ".tar", ".gz", ".pdb", ".cache"
        };
        static readonly HashSet<string> SkipDirs = new() { ".git", "node_modules", "__pycache__", "bin", "obj" };

        static int Main(string[] args)
        {
            var violations = new List<(string file, int line, string snippet)>();

            foreach (var f in GetStagedFiles())
            {
                if (!ShouldCheck(f)) continue;
                foreach (var (ln, snip) in CheckFile(f))
                    violations.Add((f, ln, snip));
            }

            if (violations.Count > 0)
            {
                Console.WriteLine("\nОШИБКА: обнаружены потенциальные секреты в staged-файлах!\n");
                Console.WriteLine("Правило: логины, пароли, токены, API-ключи НИКОГДА не попадают в Git/GitHub.");
                Console.WriteLine("Храни их значения только в config/.local_secrets.json (файл в .gitignore).\n");
                foreach (var (file, line, snip) in violations)
                    Console.WriteLine($"  {file}:{line}: {snip}...");
                Console.WriteLine("\nКоммит отменён. Перенеси секреты в config/.local_secrets.json и закоммить без них.");
                Console.WriteLine("(Справка: config/.local_secrets.example.json — шаблон структуры.)");
                return 1;
            }
            return 0;
        }

        static List<string> GetStagedFiles()
        {
            var proc = Process.Start(new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "diff --cached --name-only --diff-filter=ACMR",
                RedirectStandardOutput = true,
                UseShellExecute = false
            })!;
            string output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit();
            var list = new List<string>();
            foreach (var line in output.Split('\n'))
            {
                var f = line.Trim().Replace('/', Path.DirectorySeparatorChar);
                if (!string.IsNullOrEmpty(f)) list.Add(f);
            }
            return list;
        }

        static bool ShouldCheck(string filepath)
        {
            var ext = Path.GetExtension(filepath).ToLowerInvariant();
            if (SkipExt.Contains(ext)) return false;
            var parts = filepath.Split(Path.DirectorySeparatorChar, '/');
            foreach (var p in parts) if (SkipDirs.Contains(p)) return false;
            if (filepath.Contains("local_secrets", StringComparison.OrdinalIgnoreCase)) return false;
            return File.Exists(filepath);
        }

        static List<(int line, string snippet)> CheckFile(string filepath)
        {
            string content;
            try { content = File.ReadAllText(filepath); }
            catch { return new List<(int, string)>(); }
            var hits = new List<(int, string)>();
            foreach (var p in BlockPatterns)
                foreach (Match m in p.Matches(content))
                {
                    int line = 1;
                    for (int i = 0; i < m.Index; i++) if (content[i] == '\n') line++;
                    var snip = m.Value.Trim();
                    if (snip.Length > 40) snip = snip.Substring(0, 40);
                    hits.Add((line, snip));
                }
            return hits;
        }
    }
}
