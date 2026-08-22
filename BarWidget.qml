import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget entry point for GitNotice: a pill that appears when any tracked
// local repo has uncommitted changes, and hosts the review/commit popup
// (Panel.qml).
BarWidget {
  id: root
  moduleName: "sudhakar.gitnotice"

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string helperPath: Model.helperPath(homeDir)
  readonly property int refreshIntervalSec: Math.max(15, parseInt(setting("refreshIntervalSec", 120)) || 120)

  property var repos: []
  readonly property var uncommittedRepos: Model.dirtyRepos(repos)
  readonly property int dirtyCount: uncommittedRepos.length
  property bool refreshing: false
  property bool busy: false
  property string lastError: ""
  readonly property color dirtyColor: Border.hyprlandActiveSpec(Color.accent, 0).color

  // Set by Panel.qml while a text field is being edited, so the periodic
  // auto-refresh below doesn't replace `repos` (which rebuilds the
  // Repeater delegates and kills focus/in-progress text) out from under
  // the user. This was the root cause of the "unreliable" text field.
  property bool suspendAutoRefresh: false

  function refresh() {
    if (listProcess.running) return
    refreshing = true
    listProcess.command = [helperPath, "list"]
    listProcess.running = true
  }

  function applyList(raw) {
    refreshing = false
    var parsed = Model.parseJson(raw)
    if (!parsed || parsed.ok !== true) {
      lastError = (parsed && parsed.error) || "Failed to read repo status"
      return
    }
    var next = parsed.repos || []
    // Skip the assignment when nothing actually changed so the Repeater
    // delegates (and any focused input inside them) aren't torn down and
    // recreated on every routine refresh.
    if (JSON.stringify(next) !== JSON.stringify(repos)) repos = next
    lastError = ""
  }

  function addRepo(path) {
    if (busy || !path) return
    busy = true
    actionProcess.command = [helperPath, "add", path]
    actionProcess.running = true
  }

  function removeRepo(path) {
    if (busy || !path) return
    busy = true
    actionProcess.command = [helperPath, "remove", path]
    actionProcess.running = true
  }

  function commitAndPush(path, message) {
    if (busy || !path || !message) return
    busy = true
    actionProcess.command = [helperPath, "commit", path, message]
    actionProcess.running = true
  }

  function applyAction(raw) {
    busy = false
    var parsed = Model.parseJson(raw)
    if (parsed && parsed.repos !== undefined) {
      // add/remove replies with the same shape as `list`.
      applyList(raw)
      return
    }
    if (!parsed || parsed.ok !== true) {
      lastError = (parsed && parsed.error) || "GitNotice action failed"
    } else {
      lastError = ""
    }
    refresh()
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // Hints the bar's open-panel underline to the label's own width/height
  // instead of a generic fraction of the slot, so it fully covers the pill.
  readonly property real openPanelIndicatorWidth: label.implicitWidth
  readonly property real openPanelIndicatorHeight: label.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  visible: true
  implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  Component.onCompleted: refresh()

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: if (!root.suspendAutoRefresh) root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: listProcess
    running: false
    command: []
    stdout: StdioCollector { id: listStdout; waitForEnd: true }
    stderr: StdioCollector { id: listStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.applyList(listStdout.text || listStderr.text || "")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.applyAction(actionStdout.text || actionStderr.text || "")
    }
  }

  IpcHandler {
    target: "sudhakar.gitnotice"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function togglePanel(): void { root.togglePanel() }
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: Model.pillText(root.dirtyCount)
    opacity: root.dirtyCount > 0 ? 1.0 : 0.6
    color: root.dirtyCount > 0 ? root.dirtyColor : (root.bar ? root.bar.barForeground : Color.foreground)
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.togglePanel()
  }
}
