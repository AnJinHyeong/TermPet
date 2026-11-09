# TermPet zsh 연동 — 오래 걸린 명령이 끝나면 TermPet에 알린다.
# TermPet 앱이 ~/.termpet/zsh-integration.zsh 로 설치(갱신)한다.
# ~/.zshrc 에 다음 한 줄을 추가해서 사용:
#   [[ -f ~/.termpet/zsh-integration.zsh ]] && source ~/.termpet/zsh-integration.zsh
#
# 설정 (source 전에 ~/.zshrc 에서 덮어쓸 수 있음):
#   TERMPET_MIN_SECONDS=30          이 시간(초) 이상 걸린 명령만 알림
#   TERMPET_IGNORE+=(mycmd)         알림 제외 명령 추가

[[ -o interactive ]] || return 0
(( ${+_TERMPET_LOADED} )) && return 0
typeset -g _TERMPET_LOADED=1

zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook

typeset -g TERMPET_MIN_SECONDS=${TERMPET_MIN_SECONDS:-30}
typeset -ga TERMPET_IGNORE
TERMPET_IGNORE+=(
  claude codex aider gemini
  vim nvim vi nano emacs micro hx
  less more man bat
  ssh mosh tmux screen
  top htop btop watch tail
  fzf lazygit tig
  python python3 node irb ipython psql mysql sqlite3 redis-cli
)

_termpet_preexec() {
  typeset -g _termpet_cmd=$1
  typeset -g _termpet_start=$EPOCHSECONDS
}

_termpet_precmd() {
  local exit_code=$?   # 반드시 첫 줄: 직전 명령의 종료 코드
  [[ -n $_termpet_start ]] || return 0
  local duration=$(( EPOCHSECONDS - _termpet_start ))
  local cmd=$_termpet_cmd
  unset _termpet_start _termpet_cmd

  (( duration >= TERMPET_MIN_SECONDS )) || return 0
  [[ -n $cmd ]] || return 0

  # 첫 단어(명령 이름) 추출: sudo/env/time/nohup, VAR=값 접두어 건너뛰기
  local -a words=(${(z)cmd})
  local first
  for first in $words; do
    [[ $first == *=* || $first == (sudo|env|time|nohup|command|exec) ]] && continue
    break
  done
  (( ${TERMPET_IGNORE[(Ie)${first:t}]} )) && return 0

  # Ctrl+C(130)로 중단한 건 에러로 보지 않고 알리지 않음
  (( exit_code == 130 )) && return 0

  [[ -x $HOME/.termpet/bin/termpet-hook ]] || return 0
  "$HOME/.termpet/bin/termpet-hook" shell "$exit_code" "$duration" "$PWD" "$cmd" &!
}

add-zsh-hook preexec _termpet_preexec
add-zsh-hook precmd _termpet_precmd
# 다른 precmd 훅이 $?를 바꾸기 전에 실행되도록 맨 앞으로
precmd_functions=(_termpet_precmd ${precmd_functions:#_termpet_precmd})
