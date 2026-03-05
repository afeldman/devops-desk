#!/usr/bin/env bash

cmd_github() {
  check_dependency gh

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    prs)    github_prs "$@" ;;
    runs)   github_runs "$@" ;;
    issues) github_issues "$@" ;;
    "")     github_menu ;;
    *)
      error "github: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk github [prs|runs|issues]"
      exit 1 ;;
  esac
}

github_menu() {
  local choice
  choice=$(printf '%s\n' \
    "prs      Browse open pull requests" \
    "runs     Browse workflow runs" \
    "issues   Browse open issues" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="GitHub > " \
      --header="GitHub Operations" \
      --height=10) || return 0

  [[ -z "$choice" ]] && return
  cmd_github "$(echo "$choice" | awk '{print $1}')"
}

github_prs() {
  gh pr list --json number,title,author,headRefName,updatedAt \
    --template '{{range .}}#{{.number}} {{.title}} [{{.author.login}}] {{.headRefName}}{{"\n"}}{{end}}' \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="PR > " \
    --header="CTRL-O: open browser  CTRL-C: checkout  CTRL-M: merge  CTRL-R: request review" \
    --preview='echo {1} | tr -d "#" | xargs gh pr view 2>/dev/null' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-o:execute(echo {1} | tr -d "#" | xargs gh pr view --web)' \
    --bind='ctrl-c:execute(echo {1} | tr -d "#" | xargs gh pr checkout)' \
    --bind='ctrl-m:execute(echo {1} | tr -d "#" | xargs gh pr merge --squash)'
}

github_runs() {
  gh run list --json databaseId,name,status,conclusion,createdAt \
    --template '{{range .}}{{.databaseId}} {{.name}} [{{.status}}] {{.conclusion}}{{"\n"}}{{end}}' \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Run > " \
    --header="CTRL-O: open browser  CTRL-L: view logs  CTRL-R: rerun" \
    --preview='gh run view {1} 2>/dev/null' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-o:execute(gh run view --web {1})' \
    --bind='ctrl-l:execute(gh run view --log {1} | less)' \
    --bind='ctrl-r:execute(gh run rerun {1})'
}

github_issues() {
  gh issue list --json number,title,author,state,labels \
    --template '{{range .}}#{{.number}} {{.title}} [{{.author.login}}]{{"\n"}}{{end}}' \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Issue > " \
    --header="CTRL-O: open browser  CTRL-A: assign to me  CTRL-C: create branch" \
    --preview='echo {1} | tr -d "#" | xargs gh issue view 2>/dev/null' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-o:execute(echo {1} | tr -d "#" | xargs gh issue view --web)'
}
