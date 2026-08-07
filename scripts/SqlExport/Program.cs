using System;
using System.Diagnostics;
using System.IO;
using System.Text;

if (args.Length < 4) { Console.Error.WriteLine("SqlExport server db password exportPath [objectType]"); return 1; }

string server = args[0], db = args[1], password = args[2], exportPath = args[3];
string objectType = args.Length > 4 ? args[4] : "";

string bat = @"C:\AIS\AI\Prod\bin\SQL_exp_param.bat";
exportPath = Path.GetFullPath(exportPath);

string argsStr = $"{bat} {server} {db} {password} \"\" {exportPath} {objectType}";
Console.Error.WriteLine("ARGS: " + argsStr);
var psi = new ProcessStartInfo
{
    FileName = "cmd",
    Arguments = "/c " + argsStr,
    UseShellExecute = false,
    RedirectStandardOutput = true,
    RedirectStandardError = true,
    CreateNoWindow = true
};

using var proc = Process.Start(psi)!;
int stepCount = 0, phaseTotal = 0;
while (!proc.StandardOutput.EndOfStream)
{
    var line = proc.StandardOutput.ReadLine();
    if (line != null)
    {
        if (line.StartsWith("###PHASE###"))
        {
            var m = System.Text.RegularExpressions.Regex.Match(line, @"###PHASE###(.+?)\|(\d+)###");
            if (m.Success) { phaseTotal = int.Parse(m.Groups[2].Value); stepCount = 0; }
        }
        else if (line == "###STEP###")
        {
            stepCount++;
            if (phaseTotal > 0)
                line = $"###STEP###{stepCount}|{phaseTotal}###";
            else
                line = $"###STEP###{stepCount}###";
        }
        Console.WriteLine(line);
        Console.Out.Flush();
    }
}
proc.WaitForExit();
var stderr = proc.StandardError.ReadToEnd();
if (!string.IsNullOrWhiteSpace(stderr))
{
    Console.Error.WriteLine(stderr);
    Console.Error.Flush();
}
return proc.ExitCode;
