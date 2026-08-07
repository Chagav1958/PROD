using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Microsoft.Data.Sqlite;

class ExportFull
{
    static string DbPath = @"C:\AIS\AI\Prod\scripts\ais_objects_mcp\objects.db";
    static string PbOut = @"C:\AIS\AI\Prod\temp\pb_full.json";
    static string SqlOut = @"C:\AIS\AI\Prod\temp\sql_full.json";

    static List<Dictionary<string, object>> ExportPb()
    {
        var rows = new List<Dictionary<string, object>>();
        using var db = new SqliteConnection($"Data Source={DbPath}");
        db.Open();
        var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT o.id, o.name, o.obj_type, o.lib, o.file_size, o.file_modified, o.src, o.file_path, (SELECT m.file_sha256 FROM objects m WHERE m.name=o.name AND m.kind='PB' AND m.src='main') as main_sha, (SELECT c.file_sha256 FROM objects c WHERE c.name=o.name AND c.kind=c.kind AND c.src='current') as cur_sha, (SELECT value FROM object_properties WHERE object_id=o.id AND key='purpose') as purpose, (SELECT m.file_path FROM objects m WHERE m.name=o.name AND m.kind='PB' AND m.src='main') as main_path FROM objects o WHERE o.kind='PB' AND o.src='current' ORDER BY o.lib, o.obj_type, o.name";
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var oid = reader.GetInt64(0);
            var name = reader.GetString(1);
            var analysis = "";
            var acmd = db.CreateCommand();
            acmd.CommandText = "SELECT text FROM object_analyses WHERE object_id=@p AND tags LIKE '%auto_analysis%' ORDER BY created_at DESC LIMIT 1";
            acmd.Parameters.Add(new SqliteParameter("@p", oid));
            using var ar = acmd.ExecuteReader();
            if (ar.Read()) analysis = ar.GetString(0);
            ar.Close();

            var tasks = new HashSet<string>();
            foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(analysis, @"SYBASE-\d+|SUPRT-\d+"))
                tasks.Add(m.Value);

            var firstAnc = "";
            var allAnc = new List<string>();
            if (analysis.Contains("[PREDKI]"))
            {
                var inSec = false;
                foreach (var line in analysis.Split('\n'))
                {
                    if (line.Contains("[PREDKI]")) { inSec = true; continue; }
                    if (line.StartsWith("[")) { inSec = false; continue; }
                    if (inSec && line.TrimStart().StartsWith("- "))
                    {
                        var a = line.Trim().Substring(2).Split('(')[0].Trim();
                        if (string.IsNullOrEmpty(firstAnc)) firstAnc = a;
                        if (!allAnc.Contains(a)) allAnc.Add(a);
                    }
                }
            }

            var funcs = new List<string>();
            if (analysis.Contains("[FUNKTSII]"))
            {
                var inSec = false;
                foreach (var line in analysis.Split('\n'))
                {
                    if (line.Contains("[FUNKTSII]")) { inSec = true; continue; }
                    if (line.StartsWith("[")) { inSec = false; continue; }
                    if (inSec && line.TrimStart().StartsWith("- "))
                        funcs.Add(line.Trim().Substring(2));
                }
            }

            var events = new List<string>();
            if (analysis.Contains("[EVENTS]"))
            {
                var inSec = false;
                foreach (var line in analysis.Split('\n'))
                {
                    if (line.Contains("[EVENTS]")) { inSec = true; continue; }
                    if (line.StartsWith("[")) { inSec = false; continue; }
                    if (inSec && line.TrimStart().StartsWith("- "))
                        events.Add(line.Trim().Substring(2));
                }
            }

            var contained = new List<string>();
            var ccmd = db.CreateCommand();
            ccmd.CommandText = "SELECT to_object FROM object_dependencies WHERE from_object=@p AND from_src='current' LIMIT 50";
            ccmd.Parameters.Add(new SqliteParameter("@p", name));
            using var cr = ccmd.ExecuteReader();
            while (cr.Read()) contained.Add(cr.GetString(0));
            cr.Close();

            var sqlRefs = new List<string>();
            var scmd = db.CreateCommand();
            scmd.CommandText = "SELECT to_object FROM object_dependencies WHERE from_object=@p AND from_src='current' AND dep_type='sql_ref' LIMIT 50";
            scmd.Parameters.Add(new SqliteParameter("@p", name));
            using var sr = scmd.ExecuteReader();
            while (sr.Read()) sqlRefs.Add(sr.GetString(0));
            sr.Close();

            var containedIn = new List<string>();
            var icmd = db.CreateCommand();
            icmd.CommandText = "SELECT from_object FROM object_dependencies WHERE to_object=@p LIMIT 50";
            icmd.Parameters.Add(new SqliteParameter("@p", name));
            using var ir = icmd.ExecuteReader();
            while (ir.Read()) containedIn.Add(ir.GetString(0));
            ir.Close();

            var versionsMatch = "?";
            var mainSha = reader.IsDBNull(8) ? null : reader.GetString(8);
            var curSha = reader.IsDBNull(9) ? null : reader.GetString(9);
            if (mainSha != null && curSha != null)
                versionsMatch = mainSha == curSha ? "Yes" : "No";

            rows.Add(new Dictionary<string, object>
            {
                ["name"] = name,
                ["type"] = reader.GetString(2),
                ["lib"] = reader.GetString(3),
                ["size_kb"] = reader.IsDBNull(4) || reader.GetValue(4) == DBNull.Value ? 0 : Convert.ToInt64(reader.GetValue(4)) / 1024,
                ["modified"] = reader.IsDBNull(5) || reader.GetValue(5) == DBNull.Value ? "" : reader.GetString(5).Substring(0, Math.Min(16, reader.GetString(5).Length)),
                ["first_anc"] = firstAnc,
                ["title"] = reader.IsDBNull(10) || reader.GetValue(10) == DBNull.Value ? "" : reader.GetString(10),
                ["all_anc"] = string.Join(", ", allAnc.GetRange(0, Math.Min(10, allAnc.Count))),
                ["contained_list"] = contained.GetRange(0, Math.Min(20, contained.Count)),
                ["contained_sql"] = sqlRefs.GetRange(0, Math.Min(20, sqlRefs.Count)),
                ["contained_in_list"] = containedIn.GetRange(0, Math.Min(20, containedIn.Count)),
                ["src"] = reader.GetString(6) == "current" ? "Current" : "Main",
                ["versions_match"] = versionsMatch,
                ["tasks"] = string.Join(", ", new List<string>(tasks).GetRange(0, Math.Min(10, tasks.Count))),
                ["funcs"] = funcs.GetRange(0, Math.Min(30, funcs.Count)),
                ["events"] = events.GetRange(0, Math.Min(10, events.Count)),
                ["file_path"] = reader.IsDBNull(7) || reader.GetValue(7) == DBNull.Value ? "" : reader.GetString(7),
                ["main_path"] = reader.IsDBNull(11) || reader.GetValue(11) == DBNull.Value ? "" : reader.GetString(11),
            });
        }
        db.Close();
        return rows;
    }

    static List<Dictionary<string, object>> ExportSql()
    {
        var rows = new List<Dictionary<string, object>>();
        using var db = new SqliteConnection($"Data Source={DbPath}");
        db.Open();
        var cmd = db.CreateCommand();
        cmd.CommandText = "SELECT o.id, o.name, o.obj_type, o.lib, o.file_size, o.file_modified, o.src, o.file_path, (SELECT m.file_sha256 FROM objects m WHERE m.name=o.name AND m.kind='SQL' AND m.src='main') as main_sha, (SELECT c.file_sha256 FROM objects c WHERE c.name=o.name AND c.kind=c.kind AND c.src='current') as cur_sha, (SELECT value FROM object_properties WHERE object_id=o.id AND key='purpose') as purpose, (SELECT m.file_path FROM objects m WHERE m.name=o.name AND m.kind='SQL' AND m.src='main') as main_path FROM objects o WHERE o.kind='SQL' AND o.src='current' ORDER BY o.lib, o.name";
        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            var oid = reader.GetInt64(0);
            var name = reader.GetString(1);
            var analysis = "";
            var acmd = db.CreateCommand();
            acmd.CommandText = "SELECT text FROM object_analyses WHERE object_id=@p AND tags LIKE '%auto_analysis%' ORDER BY created_at DESC LIMIT 1";
            acmd.Parameters.Add(new SqliteParameter("@p", oid));
            using var ar = acmd.ExecuteReader();
            if (ar.Read()) analysis = ar.GetString(0);
            ar.Close();

            var tasks = new HashSet<string>();
            foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(analysis, @"SYBASE-\d+|SUPRT-\d+"))
                tasks.Add(m.Value);

            var contained = new List<string>();
            var ccmd = db.CreateCommand();
            ccmd.CommandText = "SELECT to_object FROM object_dependencies WHERE from_object=@p AND from_src='current' LIMIT 50";
            ccmd.Parameters.Add(new SqliteParameter("@p", name));
            using var cr = ccmd.ExecuteReader();
            while (cr.Read()) contained.Add(cr.GetString(0));
            cr.Close();

            var containedIn = new List<string>();
            var icmd = db.CreateCommand();
            icmd.CommandText = "SELECT from_object FROM object_dependencies WHERE to_object=@p LIMIT 50";
            icmd.Parameters.Add(new SqliteParameter("@p", name));
            using var ir = icmd.ExecuteReader();
            while (ir.Read()) containedIn.Add(ir.GetString(0));
            ir.Close();

            var pbRefs = new List<string>();
            var pcmd = db.CreateCommand();
            pcmd.CommandText = "SELECT from_object FROM object_dependencies WHERE to_object=@p AND dep_type='sql_ref' LIMIT 50";
            pcmd.Parameters.Add(new SqliteParameter("@p", name));
            using var pr = pcmd.ExecuteReader();
            while (pr.Read()) pbRefs.Add(pr.GetString(0));
            pr.Close();

            var funcs = new List<string>();
            if (analysis.Contains("[FUNKTSII]"))
            {
                var inSec = false;
                foreach (var line in analysis.Split('\n'))
                {
                    if (line.Contains("[FUNKTSII]")) { inSec = true; continue; }
                    if (line.StartsWith("[")) { inSec = false; continue; }
                    if (inSec && line.TrimStart().StartsWith("- "))
                        funcs.Add(line.Trim().Substring(2));
                }
            }

            var parms = new List<string>();
            if (analysis.Contains("[PARAMETRY]"))
            {
                var inSec = false;
                foreach (var line in analysis.Split('\n'))
                {
                    if (line.Contains("[PARAMETRY]")) { inSec = true; continue; }
                    if (line.StartsWith("[")) { inSec = false; continue; }
                    if (inSec && line.TrimStart().StartsWith("- "))
                        parms.Add(line.Trim().Substring(2));
                }
            }

            var tables = new List<string>();
            if (analysis.Contains("[TABLITSY]"))
            {
                var inSec = false;
                foreach (var line in analysis.Split('\n'))
                {
                    if (line.Contains("[TABLITSY]")) { inSec = true; continue; }
                    if (line.StartsWith("[")) { inSec = false; continue; }
                    if (inSec && line.TrimStart().StartsWith("- "))
                        tables.Add(line.Trim().Substring(2));
                }
            }

            var versionsMatch = "?";
            var mainSha = reader.IsDBNull(8) ? null : reader.GetString(8);
            var curSha = reader.IsDBNull(9) ? null : reader.GetString(9);
            if (mainSha != null && curSha != null)
                versionsMatch = mainSha == curSha ? "Yes" : "No";

            rows.Add(new Dictionary<string, object>
            {
                ["name"] = name,
                ["type"] = reader.GetString(2),
                ["category"] = reader.GetString(3),
                ["server"] = "dev_golden",
                ["db"] = "golden",
                ["size_kb"] = reader.IsDBNull(4) || reader.GetValue(4) == DBNull.Value ? 0 : Convert.ToInt64(reader.GetValue(4)) / 1024,
                ["modified"] = reader.IsDBNull(5) || reader.GetValue(5) == DBNull.Value ? "" : reader.GetString(5).Substring(0, Math.Min(16, reader.GetString(5).Length)),
                ["purpose"] = reader.IsDBNull(10) || reader.GetValue(10) == DBNull.Value ? "" : reader.GetString(10),
                ["tasks"] = string.Join(", ", new List<string>(tasks).GetRange(0, Math.Min(10, tasks.Count))),
                ["contained_list"] = contained.GetRange(0, Math.Min(20, contained.Count)),
                ["contained_in_list"] = containedIn.GetRange(0, Math.Min(20, containedIn.Count)),
                ["pb_refs_list"] = pbRefs.GetRange(0, Math.Min(20, pbRefs.Count)),
                ["src"] = reader.GetString(6) == "current" ? "Current" : "Main",
                ["versions_match"] = versionsMatch,
                ["funcs"] = funcs.GetRange(0, Math.Min(30, funcs.Count)),
                ["params"] = parms.GetRange(0, Math.Min(20, parms.Count)),
                ["tables"] = tables.GetRange(0, Math.Min(30, tables.Count)),
                ["file_path"] = reader.IsDBNull(7) || reader.GetValue(7) == DBNull.Value ? "" : reader.GetString(7),
                ["main_path"] = reader.IsDBNull(11) || reader.GetValue(11) == DBNull.Value ? "" : reader.GetString(11),
            });
        }
        db.Close();
        return rows;
    }

    static void Main()
    {
        Console.WriteLine("Exporting PB objects...");
        var pb = ExportPb();
        Console.WriteLine($"PB: {pb.Count}");

        Console.WriteLine("Exporting SQL objects...");
        var sql = ExportSql();
        Console.WriteLine($"SQL: {sql.Count}");

        var pbJson = JsonSerializer.Serialize(pb, new JsonSerializerOptions { WriteIndented = false });
        File.WriteAllText(PbOut, pbJson, System.Text.Encoding.UTF8);

        var sqlJson = JsonSerializer.Serialize(sql, new JsonSerializerOptions { WriteIndented = false });
        File.WriteAllText(SqlOut, sqlJson, System.Text.Encoding.UTF8);

        Console.WriteLine($"Done. PB={pb.Count} SQL={sql.Count}");
    }
}