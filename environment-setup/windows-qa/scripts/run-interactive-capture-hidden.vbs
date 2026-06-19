Set shell = CreateObject("WScript.Shell")
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File C:\oribis-qa\oribis\__incoming__\interactive-capture.ps1", 0, True

