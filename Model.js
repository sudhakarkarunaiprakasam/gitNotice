.pragma library

function parseJson(text) {
  try {
    return JSON.parse(text || "")
  } catch (e) {
    return null
  }
}

// Path to the plugin's bash helper. Third-party plugins install to a
// fixed location, so we can build the path directly instead of resolving it.
function helperPath(homeDir) {
  return homeDir + "/.config/omarchy/plugins/sudhakar.gitnotice/gitnotice.sh"
}

function pluralize(count, singular) {
  return count === 1 ? singular : singular + "s"
}

function changedFilesText(count) {
  return count + " " + pluralize(count, "file") + " changed"
}

// Bar pill: a git-branch glyph plus the dirty count. Color (grey when clean,
// green when dirty) is applied by the caller via `dirtyColor`.
var dirtyColor = "#3fb950"

function pillText(dirtyCount) {
  var icon = "\uf126" // nf-fa-code_branch
  return dirtyCount > 0 ? (icon + " " + dirtyCount) : icon
}

function dirtyRepos(repos) {
  var result = []
  for (var i = 0; i < repos.length; i++) {
    if (repos[i] && repos[i].dirty) result.push(repos[i])
  }
  return result
}
