import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// GitNotice popup: lists tracked repos with uncommitted changes and lets you
// commit + push them. BarWidget.qml owns the repo state; this panel just
// drives it.
Panel {
  id: root
  moduleName: "sudhakar.gitnotice"
  ipcTarget: "sudhakar.gitnotice"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var repos: hostWidget ? hostWidget.repos : []
  readonly property var uncommittedRepos: hostWidget ? hostWidget.uncommittedRepos : []
  readonly property bool busy: hostWidget ? hostWidget.busy === true : false
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing === true : false
  readonly property string lastError: hostWidget ? hostWidget.lastError : ""

  property string activeCommitPath: ""
  property string commitMessage: ""
  property string newRepoPath: ""
  property bool manageOpen: false

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Uniform width for the small action buttons so "Commit"/"Cancel",
  // "Push"/"Add"/"Remove" etc. don't visibly vary in size.
  readonly property real actionButtonWidth: 96

  component FixedActionButton: Item {
    id: fixedButton

    property alias text: button.text
    property alias bordered: button.bordered
    property alias enabled: button.enabled
    signal clicked()

    width: root.actionButtonWidth
    implicitWidth: root.actionButtonWidth
    implicitHeight: button.implicitHeight
    Layout.minimumWidth: root.actionButtonWidth
    Layout.preferredWidth: root.actionButtonWidth
    Layout.maximumWidth: root.actionButtonWidth

    Button {
      id: button
      anchors.fill: parent
      onClicked: fixedButton.clicked()
    }
  }

  function beginCommit(path) {
    activeCommitPath = activeCommitPath === path ? "" : path
    commitMessage = ""
  }

  function submitCommit() {
    if (!hostWidget || !activeCommitPath || !commitMessage.trim()) return
    hostWidget.commitAndPush(activeCommitPath, commitMessage.trim())
    activeCommitPath = ""
    commitMessage = ""
  }

  function submitAddRepo() {
    if (!hostWidget || !newRepoPath.trim()) return
    hostWidget.addRepo(newRepoPath.trim())
    newRepoPath = ""
  }

  onOpenedChanged: if (opened && hostWidget) hostWidget.refresh()

  // KeyboardPanel provides compositor-level keyboard focus for text inputs;
  // PopupWindow only receives keyboard input after pointer focus changes.
  KeyboardPanel {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.opened
    centerOnBar: true
    focusTarget: content
    contentWidth: card.fittedContentWidth(Style.space(320))
    contentHeight: card.fittedContentHeight(content.implicitHeight, Style.space(480))

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      ColumnLayout {
        id: content
        width: panelFlick.width
        focus: true
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true

          Text {
            Layout.fillWidth: true
            text: "GitNotice"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          FixedActionButton {
            text: "Refresh"
            bordered: true
            enabled: !root.busy && !root.refreshing
            onClicked: if (root.hostWidget) root.hostWidget.refresh()
          }
        }

        Text {
          visible: root.lastError !== ""
          Layout.fillWidth: true
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.lastError
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "UNCOMMITTED REPOS"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.caption
        }

        Text {
          visible: root.uncommittedRepos.length === 0
          Layout.fillWidth: true
          text: root.refreshing ? "Checking repos…" : "All tracked repos are clean."
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Repeater {
            model: root.uncommittedRepos

            ColumnLayout {
              id: repoRow
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(4)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: repoRow.modelData.name
                    elide: Text.ElideMiddle
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    Layout.fillWidth: true
                    text: Model.changedFilesText(repoRow.modelData.changedFiles)
                    color: Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                FixedActionButton {
                  text: root.activeCommitPath === repoRow.modelData.path ? "Cancel" : "Commit"
                  bordered: true
                  enabled: !root.busy
                  onClicked: root.beginCommit(repoRow.modelData.path)
                }
              }

              RowLayout {
                id: commitRow
                visible: root.activeCommitPath === repoRow.modelData.path
                Layout.fillWidth: true
                spacing: Style.space(6)
                onVisibleChanged: if (visible) Qt.callLater(commitField.forceActiveFocus)

                TextField {
                  id: commitField
                  Layout.fillWidth: true
                  placeholderText: "Commit message"
                  maximumLength: 4096
                  text: root.commitMessage
                  enabled: !root.busy
                  focus: visible
                  selectByMouse: true
                  activeFocusOnPress: true
                  onTextChanged: root.commitMessage = text
                  onAccepted: root.submitCommit()
                  onActiveFocusChanged: if (root.hostWidget) root.hostWidget.suspendAutoRefresh = activeFocus
                  Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
                  TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: commitField.forceActiveFocus()
                  }
                }

                FixedActionButton {
                  text: "Push"
                  bordered: true
                  enabled: !root.busy && root.commitMessage.trim() !== ""
                  onClicked: root.submitCommit()
                }
              }
            }
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.contentForeground
        }

        RowLayout {
          Layout.fillWidth: true

          PanelSectionHeader {
            Layout.fillWidth: true
            text: "MANAGE REPOS (" + root.repos.length + ")"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            fontSize: Style.font.caption
          }

          FixedActionButton {
            text: root.manageOpen ? "Hide" : "Show"
            bordered: true
            onClicked: root.manageOpen = !root.manageOpen
          }
        }

        ColumnLayout {
          id: manageSection
          visible: root.manageOpen
          Layout.fillWidth: true
          spacing: Style.space(6)
          onVisibleChanged: if (visible) Qt.callLater(newRepoField.forceActiveFocus)

          Repeater {
            model: root.repos

            RowLayout {
              id: manageRow
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: manageRow.modelData.name + (manageRow.modelData.error ? " — " + manageRow.modelData.error : "")
                elide: Text.ElideMiddle
                color: manageRow.modelData.error ? Color.urgent : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              FixedActionButton {
                text: "Remove"
                bordered: true
                enabled: !root.busy
                onClicked: root.hostWidget && root.hostWidget.removeRepo(manageRow.modelData.path)
              }
            }
          }

          RowLayout {
            id: addRepoRow
            Layout.fillWidth: true
            spacing: Style.space(6)

            TextField {
              id: newRepoField
              Layout.fillWidth: true
              placeholderText: "/path/to/repo"
              maximumLength: 4096
              text: root.newRepoPath
              enabled: !root.busy
              focus: visible
              selectByMouse: true
              activeFocusOnPress: true
              onTextChanged: root.newRepoPath = text
              onAccepted: root.submitAddRepo()
              onActiveFocusChanged: if (root.hostWidget) root.hostWidget.suspendAutoRefresh = activeFocus
              Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
              TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: newRepoField.forceActiveFocus()
              }
            }

            FixedActionButton {
              text: "Add"
              bordered: true
              enabled: !root.busy && root.newRepoPath.trim() !== ""
              onClicked: root.submitAddRepo()
            }
          }
        }
      }
    }
  }
}


