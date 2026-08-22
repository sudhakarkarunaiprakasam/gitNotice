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

set -uo pipefail

MAX_GIT_OUTPUT_BYTES=65536
MAX_STORE_BYTES=262144
MAX_REPOS=64
MAX_PATH_LENGTH=4096
MAX_COMMIT_MESSAGE_LENGTH=4096
GIT_TIMEOUT_SECONDS=30

STORE_DIR="$HOME/.config/gitnotice"
STORE_PATH="$STORE_DIR/repos.json"

limit_output() {
  LC_ALL=C awk -v max="$MAX_GIT_OUTPUT_BYTES" '
    {
      line = $0 ORS
      remaining = max - emitted
      if (remaining > 0) {
        printf "%s", substr(line, 1, remaining)
        emitted += length(line)
      }
    }
  '
}

load_repos() {
  if [[ -f "$STORE_PATH" && ! -L "$STORE_PATH" && $(stat -c '%s' -- "$STORE_PATH" 2>/dev/null || echo 0) -le "$MAX_STORE_BYTES" ]]; then
    jq -c --argjson maxRepos "$MAX_REPOS" --argjson maxPathLength "$MAX_PATH_LENGTH" \
      '(.repos // []) | map(select(type == "string" and length <= $maxPathLength)) | .[:$maxRepos]' \
      "$STORE_PATH" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

save_repos() {
  local repos_json="$1"
  local temp_path
  [[ -L "$STORE_DIR" || -L "$STORE_PATH" ]] && return 1
  mkdir -p "$STORE_DIR"
  temp_path=$(mktemp "$STORE_DIR/.repos.json.XXXXXX") || return 1
  if ! (umask 077; jq -n --argjson repos "$repos_json" '{repos: $repos}' > "$temp_path"); then
    rm -f -- "$temp_path"
    return 1
  fi
  chmod 600 -- "$temp_path"
  mv -f -- "$temp_path" "$STORE_PATH"
}

acquire_store_lock() {
  [[ -L "$STORE_DIR" ]] && return 1
  mkdir -p "$STORE_DIR" || return 1
  [[ -L "$STORE_DIR/.lock" ]] && return 1
  exec 9>"$STORE_DIR/.lock" || return 1
  flock -x 9
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

  if [[ "$(timeout --foreground "$GIT_TIMEOUT_SECONDS" git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    jq -n --arg path "$path" --arg name "$name" \
      '{path: $path, name: $name, exists: true, isRepo: false, dirty: false, changedFiles: 0, branch: "", error: "Not a git repository"}'
    return
  fi

  local status_out changed_files branch
  if ! status_out=$(timeout --foreground "$GIT_TIMEOUT_SECONDS" git -C "$path" status --porcelain 2>&1 | limit_output); then
    jq -n --arg path "$path" --arg name "$name" --arg err "$status_out" \
      '{path: $path, name: $name, exists: true, isRepo: true, dirty: false, changedFiles: 0, branch: "", error: ($err // "git status failed")}'
    return
  fi

  changed_files=0
  [[ -n "$status_out" ]] && changed_files=$(grep -c . <<< "$status_out")
  branch=$(timeout --foreground "$GIT_TIMEOUT_SECONDS" git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null | limit_output) || branch=""

  jq -n --arg path "$path" --arg name "$name" --argjson changed "$changed_files" --arg branch "$branch" \
    '{path: $path, name: $name, exists: true, isRepo: true, dirty: ($changed > 0), changedFiles: $changed, branch: $branch, error: null}'
}

cmd_list() {
  local repos repo_objects
  repos=$(load_repos)
  repo_objects=$(while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    repo_info "$path"
  done < <(jq -r '.[]' <<< "$repos") | jq -s -c '.')

  local dirty_count
  dirty_count=$(jq '[.[] | select(.dirty == true)] | length' <<< "$repo_objects")
  jq -n --argjson repos "$repo_objects" --argjson dirtyCount "$dirty_count" '{ok: true, repos: $repos, dirtyCount: $dirtyCount}'
}

cmd_add() {
  local path="$1" normalized repos
  [[ ${#path} -le "$MAX_PATH_LENGTH" ]] || { jq -n '{ok: false, error: "Repository path is too long"}'; return; }
  acquire_store_lock || { jq -n '{ok: false, error: "Repository store is unavailable"}'; return; }
  normalized=$(realpath -m -- "$path" 2>/dev/null) || normalized="$path"
  [[ ${#normalized} -le "$MAX_PATH_LENGTH" ]] || { jq -n '{ok: false, error: "Repository path is too long"}'; return; }
  repos=$(load_repos)
  [[ $(jq 'length' <<< "$repos") -lt "$MAX_REPOS" ]] || { jq -n '{ok: false, error: "Repository limit reached"}'; return; }

  if jq -e --arg p "$normalized" 'index($p) != null' <<< "$repos" > /dev/null; then
    jq -n '{ok: false, error: "Repository already added"}'
    return
  fi

  if [[ "$(timeout --foreground "$GIT_TIMEOUT_SECONDS" git -C "$normalized" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    jq -n --arg p "$normalized" '{ok: false, error: ("Not a git repository: " + $p)}'
    return
  fi

  save_repos "$(jq -c --arg p "$normalized" '. + [$p]' <<< "$repos")" || { jq -n '{ok: false, error: "Could not save repository list"}'; return; }
  cmd_list
}

cmd_remove() {
  local path="$1" repos
  acquire_store_lock || { jq -n '{ok: false, error: "Repository store is unavailable"}'; return; }
  repos=$(load_repos)
  save_repos "$(jq -c --arg p "$path" 'map(select(. != $p))' <<< "$repos")" || { jq -n '{ok: false, error: "Could not save repository list"}'; return; }
  cmd_list
}

cmd_commit() {
  local path="$1" message="$2" out

  [[ ${#path} -le "$MAX_PATH_LENGTH" && ${#message} -le "$MAX_COMMIT_MESSAGE_LENGTH" ]] || {
    jq -n '{ok: false, error: "Commit input is too long"}'
    return
  }
  if [[ -z "${message// /}" ]]; then
    jq -n '{ok: false, error: "Commit message is required"}'
    return
  fi

  if ! jq -e --arg p "$path" 'index($p) != null' <<< "$(load_repos)" > /dev/null; then
    jq -n '{ok: false, error: "Repository is not tracked"}'
    return
  fi

  if ! out=$(timeout --foreground "$GIT_TIMEOUT_SECONDS" git -C "$path" add -A 2>&1 | limit_output); then
    jq -n --arg err "$out" '{ok: false, error: ($err // "git add failed")}'
    return
  fi

  if ! out=$(timeout --foreground "$GIT_TIMEOUT_SECONDS" git -c core.hooksPath=/dev/null -C "$path" commit -m "$message" 2>&1 | limit_output); then
    jq -n --arg err "$out" '{ok: false, error: ($err // "git commit failed")}'
    return
  fi

  if ! out=$(timeout --foreground "$GIT_TIMEOUT_SECONDS" git -C "$path" push 2>&1 | limit_output); then
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
