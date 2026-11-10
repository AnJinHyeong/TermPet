@echo off
rem termpet-hook.cmd - send Claude Code hook input (stdin JSON) to TermPet (Windows version of Scripts/termpet-hook).
rem Installed/updated to %USERPROFILE%\.termpet\bin\ every time TermPet starts.
rem
rem Usage:  termpet-hook.cmd claude        (Stop / Notification / UserPromptSubmit / SessionEnd ...)
rem         termpet-hook.cmd claude-tool   (PostToolUse - the app reads only the head of the big tool output)
rem
rem Rules: always exit 0 immediately and print nothing, even if TermPet is not running.
rem        (exit 2 from a Stop hook would make Claude keep working)
rem        Only the built-in curl.exe (Windows 10 1803+) is used. The app parses the JSON.
rem        Comments are ASCII on purpose: cmd.exe reads batch files in the OEM code page.
setlocal
set "TP=%USERPROFILE%\.termpet"
if not exist "%TP%\token" exit /b 0
set "TOKEN="
set /p TOKEN=<"%TP%\token"
if not defined TOKEN exit /b 0
set "PORT=47821"
if exist "%TP%\port" set /p PORT=<"%TP%\port"
set "ROUTE=/hook/claude"
if /i "%~1"=="claude-tool" set "ROUTE=/hook/claude-tool"
rem If the app is off, the connection is refused within a few ms; worst case 1 second.
curl.exe -s -o NUL --connect-timeout 0.3 --max-time 1 -X POST -H "Content-Type: application/json" -H "X-TermPet-Token: %TOKEN%" -H "X-TermPet-Term-Program: %TERM_PROGRAM%" -H "X-TermPet-Host-Exe: %VSCODE_GIT_ASKPASS_NODE%" -H "X-TermPet-WT: %WT_SESSION%" --data-binary @- "http://127.0.0.1:%PORT%%ROUTE%" >NUL 2>NUL
exit /b 0
