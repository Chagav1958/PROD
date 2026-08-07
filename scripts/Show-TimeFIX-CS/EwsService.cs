using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Exchange.WebServices.Data;

namespace Show_TimeFIX
{
    public class EwsService
    {
        private ExchangeService _service = null!;
        private bool _initialized;

        public bool IsInitialized => _initialized;

        public bool Initialize()
        {
            try
            {
                var creds = ReadCredentials();
                if (creds == null) return false;
                _service = new ExchangeService
                {
                    Credentials = new WebCredentials(creds.User, creds.Password, creds.Domain),
                    Url = new Uri(creds.ServerUrl)
                };
                if (creds.SkipVerify)
                    System.Net.ServicePointManager.ServerCertificateValidationCallback =
                        (sender, certificate, chain, sslPolicyErrors) => true;
                _service.FindItems(WellKnownFolderName.Calendar, new ItemView(1));
                _initialized = true;
                MainWindow.Log("EWS", $"Connected: {creds.User}");
                return true;
            }
            catch (Exception ex)
            {
                MainWindow.Log("EWS", $"Init failed: {ex.Message}");
                return false;
            }
        }

        public List<CalendarEntryEx> GetCalendar(DateTime weekStart)
        {
            var result = new List<CalendarEntryEx>();
            if (!_initialized) return result;
            try
            {
                var weekEnd = weekStart.AddDays(7);
                var cView = new CalendarView(weekStart, weekEnd, 100);
                var items = _service.FindAppointments(WellKnownFolderName.Calendar, cView).Result;
                foreach (var a in items)
                {
                    try
                    {
                        a.Load();
                        if (a.IsCancelled) continue;
                        if (a.Subject != null &&
                            (a.Subject.StartsWith("Canceled:") || a.Subject.StartsWith("Отменено:")))
                            continue;
                        var dur = a.IsAllDayEvent ? "весь день" : 
                            (a.End - a.Start).TotalMinutes >= 1440 ? "весь день" :
                            $"{(a.End - a.Start).TotalMinutes:F0} мин";
                        result.Add(new CalendarEntryEx
                        {
                            Date = a.Start.ToString("dd.MM.yyyy"),
                            Time = a.Start.ToString("HH:mm") + "-" + a.End.ToString("HH:mm"),
                            Subject = a.Subject ?? "",
                            Duration = dur,
                            Start = a.Start, End = a.End, Location = a.Location ?? ""
                        });
                    }
                    catch { /* skip individual item errors */ }
                }
                MainWindow.Log("EWS", $"Calendar: {result.Count} events");
            }
            catch (Exception ex) { MainWindow.Log("EWS", $"Calendar error: {ex.Message}"); }
            return result;
        }

        public bool CreateAppointment(string subject, DateTime start, int durationMinutes)
        {
            if (!_initialized) return false;
            try
            {
                var appt = new Appointment(_service)
                {
                    Subject = subject, Start = start,
                    End = start.AddMinutes(durationMinutes),
                    ReminderMinutesBeforeStart = 5, IsReminderSet = true
                };
                appt.Save(SendInvitationsMode.SendToNone);
                MainWindow.Log("EWS", $"Created: {subject} at {start:HH:mm}");
                return true;
            }
            catch (Exception ex) { MainWindow.Log("EWS", $"Create error: {ex.Message}"); return false; }
        }

        public bool HasEventToday(string keyword)
        {
            if (!_initialized) return false;
            try
            {
                var today = DateTime.Today;
                var cView = new CalendarView(today, today.AddDays(1), 50);
                cView.PropertySet = new PropertySet(AppointmentSchema.Subject);
                var items = _service.FindAppointments(WellKnownFolderName.Calendar, cView).Result;
                foreach (var a in items)
                {
                    if (a.IsCancelled) continue;
                    if (a.Subject != null &&
                        a.Subject.IndexOf(keyword, StringComparison.OrdinalIgnoreCase) >= 0)
                        return true;
                }
                return false;
            }
            catch (Exception ex) { MainWindow.Log("EWS", $"HasEvent error: {ex.Message}"); return false; }
        }

        private static EwsCredentials? ReadCredentials()
        {
            var envFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".config", "ews-mcp", "credentials.env");
            if (!File.Exists(envFile)) return null;
            var lines = File.ReadAllLines(envFile);
            string? server = null, user = null, pass = null, skipVerify = null;
            foreach (var line in lines)
            {
                var t = line.Trim();
                if (string.IsNullOrEmpty(t) || t.StartsWith("#")) continue;
                var eq = t.IndexOf('=');
                if (eq < 0) continue;
                var k = t.Substring(0, eq).Trim();
                var v = t.Substring(eq + 1).Trim();
                if ((v.StartsWith("\"") && v.EndsWith("\"")) || (v.StartsWith("'") && v.EndsWith("'")))
                    v = v.Substring(1, v.Length - 2);
                switch (k.ToUpper())
                {
                    case "EWS_SERVER_URL": server = v; break;
                    case "EWS_USERNAME": user = v; break;
                    case "EWS_PASSWORD": pass = v; break;
                    case "EWS_INSECURE_SKIP_VERIFY": skipVerify = v; break;
                }
            }
            if (string.IsNullOrEmpty(server) || string.IsNullOrEmpty(user) || string.IsNullOrEmpty(pass))
                return null;
            string domain = "";
            var up = user.Split('\\');
            if (up.Length == 2) { domain = up[0]; user = up[1]; }
            return new EwsCredentials
            {
                ServerUrl = server, User = user, Password = pass, Domain = domain,
                SkipVerify = string.Equals(skipVerify, "true", StringComparison.OrdinalIgnoreCase)
            };
        }

        private class EwsCredentials
        {
            public string ServerUrl { get; set; } = "";
            public string User { get; set; } = "";
            public string Password { get; set; } = "";
            public string Domain { get; set; } = "";
            public bool SkipVerify { get; set; }
        }
    }

    public class CalendarEntryEx
    {
        public string Date { get; set; } = "";
        public string Time { get; set; } = "";
        public string Subject { get; set; } = "";
        public string Duration { get; set; } = "";
        public string Status { get; set; } = "";
        public DateTime Start { get; set; }
        public DateTime End { get; set; }
        public string Location { get; set; } = "";
    }
}
