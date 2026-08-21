#!/usr/bin/env bash
# Helper script for the GitNotice bar widget.
#
# Tracks a small list of local git repo paths and reports which ones have
# uncommitted changes. Storage is a plain JSON file so the QML side never
# has to touch the filesystem directly. Requires bash, git, and jq (all
# ship with Omarchy by default).
#
# Usage:
#   gitnotice.sh list
#   gitnotice.sh add <path>
#   gitnotice.sh remove <path>
#   gitnotice.sh commit <path> <message>

set -u

STORE_DIR="$HOME/.config/gitnotice"
STORE_PATH="$STORE_DIR/repos.json"

load_repos() {
  if [[ -f "$STORE_PATH" ]]; then
    jq -c '(.repos // []) | map(select(type == "string"))' "$STORE_PATH" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

save_repos() {
  local repos_json="$1"
  mkdir -p "$STORE_DIR"
  jq -n --argjson repos "$repos_json" '{repos: $repos}' > "$STORE_PATH"
}

# Emits one repo's status object as JSON, given its path.
repo_info() {
  local path="$1"
  local name
  name=$(basename "${path%/}")
  [[ -z "$name" ]] && name="$path"

  if [[ ! -d "$path" ]]; then
    jq -n --arg path "$path" --arg name "$name" \
      '{path: $path, name: $name, exists: false, isRepo: false, dirty: false, changedFiles: 0, branch: "", error: "Path not found"}'
    return
  fi

  if [[ "$(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    jq -n --arg path "$path" --arg name "$name" \
      '{path: $path, name: $name, exists: true, isRepo: false, dirty: false, changedFiles: 0, branch: "", error: "Not a git repository"}'
    return
  fi

  local status_out changed_files branch
  if ! status_out=$(git -C "$path" status --porcelain 2>&1); then
    jq -n --arg path "$path" --arg name "$name" --arg err "$status_out" \
      '{path: $path, name: $name, exists: true, isRepo: true, dirty: false, changedFiles: 0, branch: "", error: ($err // "git status failed")}'
    return
  fi

  changed_files=0
  [[ -n "$status_out" ]] && changed_files=$(grep -c . <<< "$status_out")
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  jq -n --arg path "$path" --arg name "$name" --argjson changed "$changed_files" --arg branch "$branch" \
    '{path: $path, name: $name, exists: true, isRepo: true, dirty: ($changed > 0), changedFiles: $changed, branch: $branch, error: null}'
}

cmd_list() {
  local repos repo_objects="[]"
  repos=$(load_repos)
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    repo_objects=$(jq -c --argjson obj "$(repo_info "$path")" '. + [$obj]' <<< "$repo_objects")
  done < <(jq -r '.[]' <<< "$repos")

  local dirty_count
  dirty_count=$(jq '[.[] | select(.dirty == true)] | length' <<< "$repo_objects")
  jq -n --argjson repos "$repo_objects" --argjson dirtyCount "$dirty_count" '{ok: true, repos: $repos, dirtyCount: $dirtyCount}'
}

cmd_add() {
  local path="$1" normalized repos
  normalized=$(realpath -m -- "$path" 2>/dev/null) || normalized="$path"
  repos=$(load_repos)

  if jq -e --arg p "$normalized" 'index($p) != null' <<< "$repos" > /dev/null; then
    jq -n '{ok: false, error: "Repository already added"}'
    return
  fi

  if [[ "$(git -C "$normalized" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    jq -n --arg p "$normalized" '{ok: false, error: ("Not a git repository: " + $p)}'
    return
  fi

  save_repos "$(jq -c --arg p "$normalized" '. + [$p]' <<< "$repos")"
  cmd_list
}

cmd_remove() {
  local path="$1" repos
  repos=$(load_repos)
  save_repos "$(jq -c --arg p "$path" 'map(select(. != $p))' <<< "$repos")"
  cmd_list
}

cmd_commit() {
  local path="$1" message="$2" out

  if [[ -z "${message// /}" ]]; then
    jq -n '{ok: false, error: "Commit message is required"}'
    return
  fi

  if ! out=$(git -C "$path" add -A 2>&1); then
    jq -n --arg err "$out" '{ok: false, error: ($err // "git add failed")}'
    return
  fi

  if ! out=$(git -C "$path" commit -m "$message" 2>&1); then
    jq -n --arg err "$out" '{ok: false, error: ($err // "git commit failed")}'
    return
  fi

  if ! out=$(git -C "$path" push 2>&1); then
    jq -n --arg err "$out" '{ok: false, error: ("Committed, but push failed: " + $err)}'
    return
  fi

  jq -n '{ok: true}'
}

main() {
  local command="${1:-}"
  case "$command" in
    list)
      cmd_list
      ;;
    add)
      [[ $# -ge 2 ]] || { jq -n '{ok: false, error: "Invalid arguments"}'; exit 1; }
      cmd_add "$2"
      ;;
    remove)
      [[ $# -ge 2 ]] || { jq -n '{ok: false, error: "Invalid arguments"}'; exit 1; }
      cmd_remove "$2"
      ;;
    commit)
      [[ $# -ge 3 ]] || { jq -n '{ok: false, error: "Invalid arguments"}'; exit 1; }
      local commit_path="$2"
      shift 2
      cmd_commit "$commit_path" "$*"
      ;;
    *)
      jq -n '{ok: false, error: "Invalid arguments"}'
      exit 1
      ;;
  esac
}

main "$@"
