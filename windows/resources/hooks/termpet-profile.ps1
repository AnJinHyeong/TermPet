# 텀펫 PowerShell 연동 - 오래 걸린 명령이 끝나면 텀펫에 알린다 (맥판 zsh-integration.zsh 의 윈도우판).
# 텀펫이 %USERPROFILE%\.termpet\termpet-profile.ps1 로 설치(갱신)한다.
# PowerShell 프로필($PROFILE)에 다음 한 줄을 추가해서 사용 (텀펫 메뉴의 [연결] 버튼이 해 준다):
#   if (Test-Path "$HOME\.termpet\termpet-profile.ps1") { . "$HOME\.termpet\termpet-profile.ps1" }
#
# 설정 (위 줄보다 먼저 프로필에서):
#   $TERMPET_MIN_SECONDS = 10        이 시간(초) 이상 걸린 명령만 알림 (기본 30)
#   $TERMPET_IGNORE = @('mycmd')     알림 제외 명령 추가
#
# 원칙: 프롬프트를 절대 느리게 하지 않는다 - 전송은 기다리지 않는 비동기(HttpClient.SendAsync).

if ($global:__TermPetLoaded) { return }
$global:__TermPetLoaded = $true

if (-not $global:TERMPET_MIN_SECONDS) { $global:TERMPET_MIN_SECONDS = 30 }
$global:__TermPetIgnore = @(
  'claude', 'codex', 'aider', 'gemini',
  'vim', 'nvim', 'vi', 'nano', 'emacs', 'micro', 'hx', 'notepad',
  'less', 'more', 'man', 'bat', 'help',
  'ssh', 'mosh', 'wsl', 'tmux',
  'top', 'htop', 'btop', 'watch',
  'fzf', 'lazygit', 'tig',
  'python', 'python3', 'py', 'node', 'irb', 'ipython', 'psql', 'mysql', 'sqlite3', 'redis-cli',
  'pwsh', 'powershell', 'cmd', 'bash'
) + @($global:TERMPET_IGNORE)

try {
  Add-Type -AssemblyName System.Net.Http
  $global:__TermPetHttp = New-Object System.Net.Http.HttpClient
  $global:__TermPetHttp.Timeout = [TimeSpan]::FromSeconds(2)
} catch {}

$global:__TermPetLastId = (Get-History -Count 1).Id
$global:__TermPetOrigPrompt = $function:prompt

function global:__TermPetNotify($h, [bool]$ok, $code) {
  try {
    if (-not $global:__TermPetHttp) { return }
    if ($h.ExecutionStatus -eq 'Stopped') { return }   # Ctrl+C 로 멈춘 건 알리지 않음
    $duration = [int]($h.EndExecutionTime - $h.StartExecutionTime).TotalSeconds
    if ($duration -lt $global:TERMPET_MIN_SECONDS) { return }
    $cmd = [string]$h.CommandLine
    if (-not $cmd) { return }
    # 첫 단어(명령 이름) 추출: & . 접두어와 경로·확장자 제거
    $first = ($cmd.Trim() -replace '^[&.]\s*', '' -split '\s+')[0].Trim('"', "'")
    $name = [IO.Path]::GetFileNameWithoutExtension($first).ToLower()
    if ($global:__TermPetIgnore -contains $name) { return }

    $dir = Join-Path $env:USERPROFILE '.termpet'
    $tokenFile = Join-Path $dir 'token'
    if (-not (Test-Path $tokenFile)) { return }
    $token = ([IO.File]::ReadAllText($tokenFile)).Trim()
    $port = 47821
    $portFile = Join-Path $dir 'port'
    if (Test-Path $portFile) { $p = ([IO.File]::ReadAllText($portFile)).Trim(); if ($p -match '^\d+$') { $port = [int]$p } }

    $exit = 0
    if (-not $ok) { $exit = 1; if ($code -is [int] -and $code -ne 0) { $exit = $code } }
    $body = @{ source = 'shell'; exitCode = $exit; durationSec = $duration; cwd = (Get-Location).Path; command = $cmd } | ConvertTo-Json -Compress
    $req = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::Post), "http://127.0.0.1:$port/event"
    [void]$req.Headers.TryAddWithoutValidation('X-TermPet-Token', $token)
    [void]$req.Headers.TryAddWithoutValidation('X-TermPet-Term-Program', "$env:TERM_PROGRAM")
    [void]$req.Headers.TryAddWithoutValidation('X-TermPet-Host-Exe', "$env:VSCODE_GIT_ASKPASS_NODE")
    [void]$req.Headers.TryAddWithoutValidation('X-TermPet-WT', "$env:WT_SESSION")
    $req.Content = New-Object System.Net.Http.StringContent $body, ([Text.Encoding]::UTF8), 'application/json'
    [void]$global:__TermPetHttp.SendAsync($req)   # 기다리지 않음 (앱이 꺼져 있어도 프롬프트는 바로 뜬다)
  } catch {}
}

function global:prompt {
  $ok = $?                       # 반드시 첫 줄: 직전 명령 성공 여부
  $code = $global:LASTEXITCODE
  try {
    $h = Get-History -Count 1
    if ($h -and $h.Id -ne $global:__TermPetLastId) {
      $global:__TermPetLastId = $h.Id
      __TermPetNotify $h $ok $code
    }
  } catch {}
  $global:LASTEXITCODE = $code    # 원래 프롬프트가 보던 값 그대로
  if ($global:__TermPetOrigPrompt) { & $global:__TermPetOrigPrompt } else { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }
}
