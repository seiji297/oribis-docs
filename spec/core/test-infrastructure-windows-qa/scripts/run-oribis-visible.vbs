Set shell = CreateObject("WScript.Shell")
Set env = shell.Environment("PROCESS")
env("ORIBIS_CLEAN_LAUNCH") = "1"
env("ORIBIS_TEST_MODE") = "1"
env("TAURI_WEBVIEW_AUTOMATION") = "true"
shell.CurrentDirectory = "C:\oribis-qa\oribis"
shell.Run "C:\oribis-qa\oribis\src-tauri\target\debug\oribis.exe", 1, False

