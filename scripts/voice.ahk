#Requires AutoHotkey v2.0
#SingleInstance Force

^!v:: {
  localAppData := EnvGet("LOCALAPPDATA")
  pyExe := localAppData . "\VoiceInput\Python\python.exe"
  pySc  := localAppData . "\VoiceInput\voice.py"
  try {
    RunWait('"' pyExe '" "' pySc '"', , "Hide")
  } catch as e {
    MsgBox("Voice Error: " e.Message)
  }
}
