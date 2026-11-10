# termpet-hook.ps1 - Codex notify 를 텀펫으로 보낸다 (윈도우판).
# 텀펫이 실행될 때 %USERPROFILE%\.termpet\bin\ 에 설치(갱신)된다.
#
# 사용법 (~/.codex/config.toml 의 notify 가 부른다. JSON은 항상 마지막 인자):
#   termpet-hook.ps1 codex '<json>'
#   termpet-hook.ps1 codex-chain <원래 notify 명령...> '<json>'   # 원래 notify를 먼저 실행한 뒤 텀펫에도 알림
#
# 원칙: 앱이 꺼져 있거나 어떤 오류가 나도 조용히 exit 0.
# TODO: Codex 가 윈도우에서 JSON 인자를 따옴표 이스케이프해 넘기는 방식이 공식 문서에 없음 → 실사용 확인 필요
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Quote-Arg([string]$s) {
  # 윈도우 명령줄 규칙(CommandLineToArgvW)대로 인자 하나를 감싼다
  if ($s -ne '' -and $s -notmatch '[\s"]') { return $s }
  $out = '"'; $bs = 0
  foreach ($c in $s.ToCharArray()) {
    if ($c -eq '\') { $bs++; continue }
    if ($c -eq '"') { $out += ('\' * ($bs * 2 + 1)) + '"' } else { $out += ('\' * $bs) + $c }
    $bs = 0
  }
  return $out + ('\' * ($bs * 2)) + '"'
}

try {
  $a = @($args)
  if ($a.Count -ge 3 -and $a[0] -eq 'codex-chain') {
    # 원래 notify 명령 + 마지막 인자(JSON) — Codex가 직접 부른 것과 똑같이, 기다리지 않고
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $a[1]
    $psi.Arguments = (@($a[2..($a.Count - 1)]) | ForEach-Object { Quote-Arg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    [void][System.Diagnostics.Process]::Start($psi)
    $a = @('codex', $a[$a.Count - 1])
  }
  if ($a.Count -lt 2 -or $a[0] -ne 'codex') { exit 0 }
  $body = [string]$a[$a.Count - 1]
  if (-not $body) { exit 0 }

  $dir = Join-Path $env:USERPROFILE '.termpet'
  $token = (Get-Content -Raw -Path (Join-Path $dir 'token')).Trim()
  if (-not $token) { exit 0 }
  $port = 47821
  $p = (Get-Content -Raw -Path (Join-Path $dir 'port')) -as [string]
  if ($p -and $p.Trim() -match '^\d+$') { $port = [int]$p.Trim() }

  $headers = @{
    'X-TermPet-Token'        = $token
    'X-TermPet-Term-Program' = "$env:TERM_PROGRAM"
    'X-TermPet-Host-Exe'     = "$env:VSCODE_GIT_ASKPASS_NODE"
    'X-TermPet-WT'           = "$env:WT_SESSION"
  }
  Invoke-WebRequest -UseBasicParsing -Method Post -Uri "http://127.0.0.1:$port/hook/codex" -Headers $headers `
    -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 1 | Out-Null
} catch {}
exit 0
