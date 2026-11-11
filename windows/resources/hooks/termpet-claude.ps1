# termpet-claude.ps1 - send a Claude Code hook input (stdin JSON) to TermPet. Windows version.
# Installed/updated to %USERPROFILE%\.termpet\bin\ every time TermPet starts.
#
# ~/.claude/settings.json runs it with "shell": "powershell" (same on every PC, with or without Git Bash):
#   & ([scriptblock]::Create([IO.File]::ReadAllText('<this file>'))) claude        (Stop, Notification, ...)
#   & ([scriptblock]::Create([IO.File]::ReadAllText('<this file>'))) claude-tool   (PostToolUse: only the head is sent)
# Running the file content as a scriptblock is not blocked by the execution policy (Restricted).
#
# Rules: never print anything, never fail, never wait long - even if TermPet is not running.
#        stdin is read as raw bytes so UTF-8 (Korean text, paths) reaches the app unchanged.
#        ASCII only on purpose (Windows PowerShell 5.1 reads BOM-less files in the ANSI code page).
param([string]$Route = 'claude')

function Send-TermPet([string]$Route) {
  $dir = Join-Path $env:USERPROFILE '.termpet'
  $tokenFile = Join-Path $dir 'token'
  if (-not (Test-Path -LiteralPath $tokenFile)) { return }
  $token = ([IO.File]::ReadAllText($tokenFile)).Trim()
  if (-not $token) { return }
  $port = 47821
  $portFile = Join-Path $dir 'port'
  if (Test-Path -LiteralPath $portFile) {
    $p = ([IO.File]::ReadAllText($portFile)).Trim()
    if ($p -match '^\d+$') { $port = [int]$p }
  }

  # PostToolUse input can be several MB (tool output); the app only needs the first few KB
  $limit = 1000000
  $path = '/hook/claude'
  if ($Route -eq 'claude-tool') { $limit = 8192; $path = '/hook/claude-tool' }
  $stdin = [Console]::OpenStandardInput()
  $ms = New-Object IO.MemoryStream
  $buf = New-Object byte[] 65536
  while ($ms.Length -lt $limit) {
    $n = $stdin.Read($buf, 0, $buf.Length)
    if ($n -le 0) { break }
    $ms.Write($buf, 0, $n)
  }
  if ($ms.Length -eq 0) { return }
  $data = $ms.ToArray()

  $req = [Net.HttpWebRequest]::Create("http://127.0.0.1:$port$path")
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Timeout = 1500
  $req.ReadWriteTimeout = 1500
  $req.Proxy = $null
  $req.Headers.Add('X-TermPet-Token', $token)
  # Where the session runs (for "go to that window"). Non-ASCII values are skipped instead of failing.
  $extra = @{ 'X-TermPet-Term-Program' = $env:TERM_PROGRAM; 'X-TermPet-Host-Exe' = $env:VSCODE_GIT_ASKPASS_NODE; 'X-TermPet-WT' = $env:WT_SESSION }
  foreach ($k in $extra.Keys) {
    $v = [string]$extra[$k]
    if ($v -and $v -notmatch '[^\x20-\x7E]') { try { $req.Headers.Add($k, $v) } catch {} }
  }
  $req.ContentLength = $data.Length
  $out = $req.GetRequestStream()
  $out.Write($data, 0, $data.Length)
  $out.Close()
  $req.GetResponse().Close()
}

try { Send-TermPet $Route } catch {}
exit 0
