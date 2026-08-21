import QtQuick
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

  // PopupCard is the actual layer-shell surface; the base Panel only tracks
  // open/close state, so nothing renders on screen without this.
  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.opened
    centerOnBar: true
    contentWidth: card.fittedContentWidth(Style.space(320))
    contentHeight: card.fittedContentHeight(content.implicitHeight, Style.space(480))

    ColumnLayout {
      id: content
      width: card.contentWidth
      spacing: Style.space(10)

      Text {
        Layout.fillWidth: true
        text: "GitNotice"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.h1
      }

      Text {
        visible: root.lastError !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
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
                  text: repoRow.modelData.name
                  elide: Text.ElideMiddle
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  Layout.fillWidth: true
                  text: Model.changedFilesText(repoRow.modelData.changedFiles)
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Button {
                text: root.activeCommitPath === repoRow.modelData.path ? "Cancel" : "Commit"
                bordered: true
                enabled: !root.busy
                onClicked: root.beginCommit(repoRow.modelData.path)
              }
            }

            RowLayout {
              visible: root.activeCommitPath === repoRow.modelData.path
              Layout.fillWidth: true
              spacing: Style.space(6)

              TextField {
                Layout.fillWidth: true
                placeholderText: "Commit message"
                text: root.commitMessage
                enabled: !root.busy
                onTextChanged: root.commitMessage = text
                onAccepted: root.submitCommit()
              }

              Button {
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
        }

        Button {
          text: root.manageOpen ? "Hide" : "Show"
          bordered: true
          onClicked: root.manageOpen = !root.manageOpen
        }
      }

      ColumnLayout {
        visible: root.manageOpen
        Layout.fillWidth: true
        spacing: Style.space(6)

        Repeater {
          model: root.repos

          RowLayout {
            id: manageRow
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: manageRow.modelData.name + (manageRow.modelData.error ? " — " + manageRow.modelData.error : "")
              elide: Text.ElideMiddle
              color: manageRow.modelData.error ? Color.urgent : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              text: "Remove"
              bordered: true
              enabled: !root.busy
              onClicked: root.hostWidget && root.hostWidget.removeRepo(manageRow.modelData.path)
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          TextField {
            Layout.fillWidth: true
            placeholderText: "/path/to/repo"
            text: root.newRepoPath
            enabled: !root.busy
            onTextChanged: root.newRepoPath = text
            onAccepted: root.submitAddRepo()
          }

          Button {
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

