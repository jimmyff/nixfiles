#!/usr/bin/env bash
# Claude Code status line.
# Layout:  model·effort   ⎇ worktree[·branch]   ⊙ ctx%   5h left% ·reset   7d left% ·reset
# Most data comes from the JSON Claude Code sends on stdin; only the git
# worktree/branch needs a call, capped with `timeout` so a huge repo can't stall the bar.
# Colours: green = good, yellow = caution, red = nearly out.
# Every % is "how much is left" (high is good): context remaining, and the
# rate-limit windows shown as 100 - used. Each is paired with its reset countdown.

input=$(cat)

# Bare fallback if jq is somehow unavailable.
if ! command -v jq >/dev/null 2>&1; then
  printf 'Claude\n'
  exit 0
fi

# One jq pass: 7 values, one per line, empty string for absent/null fields.
i=0
while IFS= read -r line; do
  vals[i]=$line
  i=$((i + 1))
done < <(printf '%s' "$input" | jq -r '
  [ .model.display_name                    // "Claude",
    .effort.level                          // "",
    .context_window.remaining_percentage   // "",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.five_hour.resets_at       // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.seven_day.resets_at       // "",
    .workspace.current_dir                 // .cwd // ""
  ] | .[]')

model=${vals[0]:-Claude}
effort=${vals[1]:-}
ctx_rem=${vals[2]:-}
five_used=${vals[3]:-}
five_reset=${vals[4]:-}
seven_used=${vals[5]:-}
seven_reset=${vals[6]:-}
dir=${vals[7]:-}

esc=$'\033'
reset="${esc}[0m"; dim="${esc}[2m"; bold="${esc}[1m"
green="${esc}[32m"; yellow="${esc}[33m"; red="${esc}[31m"
cyan="${esc}[36m"; grey="${esc}[90m"; magenta="${esc}[35m"

int() { printf '%s' "${1%.*}"; }                 # drop any decimal part

col_remaining() {                                # high = good (context headroom)
  local p; p=$(int "$1")
  if   [ "$p" -gt 50 ]; then printf '%s' "$green"
  elif [ "$p" -gt 20 ]; then printf '%s' "$yellow"
  else                       printf '%s' "$red"; fi
}

col_effort() {                                   # blue -> magenta ramp (low..max)
  case "$1" in                                   # bold; distinct from green/yellow/red gauges
    low)    printf '%s' "${esc}[1;34m" ;;        # blue
    medium) printf '%s' "${esc}[1;94m" ;;        # bright blue
    high)   printf '%s' "${esc}[1;35m" ;;        # magenta
    xhigh)  printf '%s' "${esc}[1;95m" ;;        # bright magenta
    max)    printf '%s' "${esc}[1;7;95m" ;;      # bright magenta, reversed (redline)
    *)      printf '%s' "${esc}[1m" ;;           # bold fallback for unknown levels
  esac
}

fmt_reset() {                                    # epoch -> "3d4h" / "2h12m" / "45m"
  [ -z "$1" ] && return 0
  local now diff d h m
  now=$(date +%s)
  diff=$(( $1 - now ))
  [ "$diff" -lt 0 ] && diff=0
  d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh'  "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  else                      printf '%dm'     "$m"; fi
}

# Git worktree / branch — the one piece not in Claude's JSON, so one quick
# `git` call against the session dir, capped by `timeout` so a giant repo
# can't stall the bar. Shows the worktree folder name; appends the branch only
# when it differs (e.g. main checkout, or a worktree on an unrelated branch).
git_seg=""
if [ -n "$dir" ] && command -v git >/dev/null 2>&1; then
  if command -v timeout >/dev/null 2>&1; then tmo="timeout 1"; else tmo=""; fi
  branch=$($tmo git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    [ "$branch" = "HEAD" ] &&                       # detached: show short SHA
      branch="@$($tmo git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
    top=$($tmo git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    wt=${top##*/}; [ -z "$wt" ] && wt="$branch"     # worktree folder name
    git_seg="${dim}⎇${reset} ${magenta}${wt}${reset}"
    [ "$wt" != "$branch" ] &&                       # branch shown only when distinct
      git_seg="${git_seg}${dim}·${reset}${magenta}${branch}${reset}"
  fi
fi

out="${bold}${cyan}${model}${reset}"
[ -n "$effort" ] && out="${out}${dim}·${reset}$(col_effort "$effort")${effort}${reset}"
[ -n "$git_seg" ] && out="${out}   ${git_seg}"

if [ -n "$ctx_rem" ]; then
  c=$(col_remaining "$ctx_rem")
  out="${out}   ${dim}⊙${reset} ${c}$(int "$ctx_rem")%${reset}"
fi

if [ -n "$five_used" ]; then
  rem=$(( 100 - $(int "$five_used") )); c=$(col_remaining "$rem"); r=$(fmt_reset "$five_reset")
  out="${out}   ${dim}5h${reset} ${c}${rem}%${reset}"
  [ -n "$r" ] && out="${out} ${grey}·${r}${reset}"
fi

if [ -n "$seven_used" ]; then
  rem=$(( 100 - $(int "$seven_used") )); c=$(col_remaining "$rem"); r=$(fmt_reset "$seven_reset")
  out="${out}   ${dim}7d${reset} ${c}${rem}%${reset}"
  [ -n "$r" ] && out="${out} ${grey}·${r}${reset}"
fi

printf '%s\n' "$out"
