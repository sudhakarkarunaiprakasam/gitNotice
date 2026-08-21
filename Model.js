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

// Bar pill text: a red dot + count when repos are dirty, a quiet check
// otherwise (also shown when no repos are tracked yet, so the widget stays
// clickable to add some).
function pillText(dirtyCount) {
  return dirtyCount > 0 ? ("\uD83D\uDD34 " + dirtyCount) : "\u2713"
}

function dirtyRepos(repos) {
  var result = []
  for (var i = 0; i < repos.length; i++) {
    if (repos[i] && repos[i].dirty) result.push(repos[i])
  }
  return result
}
