using System;
using System.IO;
using System.Text.Json;
using SharpToken;

var model = args.Length > 0 ? args[0] : "cl100k_base";
string text;

if (args.Length > 1)
{
    var file = args[1];
    if (!File.Exists(file)) { Console.Error.WriteLine($"{{\"error\": \"file not found: {file}\"}}"); return 1; }
    text = File.ReadAllText(file);
}
else if (Console.IsInputRedirected)
{
    text = Console.In.ReadToEnd();
}
else
{
    Console.Error.WriteLine("Use: Count-Token.exe [model] < file.txt  or  Count-Token.exe [model] path.txt");
    return 1;
}

try
{
    var enc = GptEncoding.GetEncoding(model);
    var tokens = enc.Encode(text);
    var result = new { model, tokens = tokens.Count, chars = text.Length };
    Console.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"{{\"error\": \"{ex.Message}\"}}");
    return 1;
}
