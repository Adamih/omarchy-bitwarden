import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon plus popup: a guided setup until rbw is installed, configured and
// logged in, then vault controls. All secrets are entered in rbw's own
// pinentry window, never in this panel, since plugins share one QML scene.
Panel {
  id: root
  moduleName: "adami.bitwarden"
  ipcTarget: "adami.bitwarden"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string binDir: decodeURIComponent(String(Qt.resolvedUrl("bin")).replace(/^file:\/\//, ""))

  property string statusJson: ""
  property var status: ({ installed: false, missing: [], email: "", baseUrl: "", official: true, registered: false,
                          loggedIn: false, unlocked: false, items: 0, keybind: false })
  property bool statusLoaded: false
  property string busyAction: ""
  property string message: ""
  property bool messageIsError: false
  property bool showSetup: false
  property string serverChoice: "com"

  readonly property bool busy: busyAction !== ""
  readonly property bool hasAccount: status.installed && status.email !== ""
  readonly property bool setupComplete: hasAccount && status.loggedIn && status.keybind
  readonly property int loginStep: status.official ? 4 : 3

  readonly property string statusLine: {
    if (!statusLoaded) return "Checking…"
    if (!status.installed) return "Not set up"
    if (!status.loggedIn) return status.email !== "" ? "Not logged in · " + status.email : "Not set up"
    return (status.unlocked ? "Unlocked" : "Locked") + " · " + status.items + " items · " + status.email
  }

  readonly property var busyText: ({
    "install": "Installing… approve the authentication prompt",
    "account": "Saving account…",
    "api-key-page": "Opening the web vault…",
    "register": "Enter your API key's client_id and client_secret in the prompt…",
    "login": "Enter your master password, then your 2FA code, in the prompt…",
    "unlock": "Enter your master password in the prompt…",
    "lock": "Locking…",
    "sync": "Syncing…",
    "logout": "Logging out…",
    "keybind-add": "Adding shortcut…",
    "keybind-remove": "Removing shortcut…"
  })

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function run(action, args) {
    if (busy) return
    busyAction = action
    message = busyText[action] || "Working…"
    messageIsError = false
    actionProc.command = [binDir + "/bw-setup", action].concat(args || [])
    actionProc.running = true
  }

  function applyStatus(text) {
    text = String(text || "").trim()
    if (text === "" || text === statusJson) return
    var parsed
    try { parsed = JSON.parse(text) } catch (e) { return }
    statusJson = text
    status = parsed
    statusLoaded = true
    // Only fill the form from config when the user isn't editing it.
    if (!emailField.activeFocus) emailField.text = parsed.email
    if (!urlField.activeFocus) {
      var base = String(parsed.baseUrl || "").replace(/\/$/, "")
      serverChoice = base === "" ? "com" : base === "https://api.bitwarden.eu" ? "eu" : "custom"
      if (serverChoice === "custom") urlField.text = base
    }
  }

  function searchVault() {
    close()
    Quickshell.execDetached([binDir + "/bw-menu"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: root.opened || root.busy ? 3000 : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: [root.binDir + "/bw-status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }

  Process {
    id: actionProc
    property string out: ""
    property string err: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: actionProc.out = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: actionProc.err = text }
    onExited: function(exitCode) {
      var ok = exitCode === 0
      var text = String(ok ? actionProc.out : actionProc.err).trim()
      root.message = text !== "" ? text : (ok ? "Done" : "Something went wrong")
      root.messageIsError = !ok
      // Prompts steal focus and close the panel, so report long actions here too.
      if (!root.opened && ["install", "register", "login", "unlock"].indexOf(root.busyAction) !== -1) {
        Quickshell.execDetached(["omarchy", "notification", "send", "--app-name", "Bitwarden", "-t", "4000",
                                 ok ? "Bitwarden" : "Bitwarden: failed", root.message])
      }
      root.busyAction = ""
      actionProc.out = ""
      actionProc.err = ""
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.status.unlocked ? "󰌿" : "󰌾"
    active: root.statusLoaded && !root.status.loggedIn
    dimmed: root.statusLoaded && root.status.loggedIn && !root.status.unlocked
    tooltipText: "Bitwarden · " + root.statusLine
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton && root.status.loggedIn) root.run(root.status.unlocked ? "lock" : "unlock")
      else root.toggle()
    }
  }

  // One numbered setup step: title, explanation, and its controls.
  component StepRow: Row {
    id: step
    property int number: 0
    property string title: ""
    property string detail: ""
    property string doneText: ""
    property bool done: false
    property bool available: true
    default property alias content: controls.data

    width: parent ? parent.width : 0
    spacing: Style.space(10)
    opacity: available || done ? 1.0 : 0.45

    Text {
      width: Style.space(18)
      text: step.done ? "󰄬" : String(step.number)
      color: step.done ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
    }

    Column {
      width: step.width - Style.space(28)
      spacing: Style.space(6)

      Text {
        width: parent.width
        text: step.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: !step.done
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: step.done ? step.doneText : step.detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Column {
        id: controls
        width: parent.width
        spacing: Style.space(6)
        visible: !step.done && step.available
        enabled: !root.busy
      }
    }
  }

  component ActionButton: Button {
    bordered: true
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.status.loggedIn || root.busy) return
        if (t === "s" || t === "S") root.searchVault()
        else if (t === "l" || t === "L") root.run(root.status.unlocked ? "lock" : "unlock")
        else if (t === "y" || t === "Y") root.run("sync")
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Bitwarden"
            meta: root.statusLine
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.status.unlocked ? 1.0 : 0.6
            iconComponent: Component {
              Text {
                text: root.status.unlocked ? "󰌿" : "󰌾"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            width: parent.width
            visible: root.message !== ""
            text: root.message
            color: root.messageIsError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---------------------------------------------------------- vault
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.status.loggedIn

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader { text: "VAULT"; foreground: root.foreground; fontFamily: root.fontFamily }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              enabled: !root.busy

              ActionButton { text: "Search"; iconText: "󰍉"; tooltipText: "Copy a password, username or code (S)"; onClicked: root.searchVault() }
              ActionButton {
                text: root.status.unlocked ? "Lock" : "Unlock"
                iconText: root.status.unlocked ? "󰌾" : "󰌿"
                tooltipText: "L"
                onClicked: root.run(root.status.unlocked ? "lock" : "unlock")
              }
              ActionButton { text: "Sync"; iconText: "󰑐"; tooltipText: "Fetch latest changes (Y)"; onClicked: root.run("sync") }
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              enabled: !root.busy

              ActionButton { text: root.showSetup ? "Hide setup" : "Setup"; onClicked: root.showSetup = !root.showSetup }
              ActionButton { text: "Log out"; tooltipText: "Remove the local vault copy from this machine"; onClicked: root.run("logout") }
            }
          }

          // ---------------------------------------------------------- setup
          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: !root.setupComplete || root.showSetup

            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader { text: "SETUP"; foreground: root.foreground; fontFamily: root.fontFamily }

            StepRow {
              number: 1
              title: (root.status.missing || []).indexOf("rbw") !== -1 || root.status.installed ? "Install rbw" : "Install missing tools"
              detail: "rbw is a lightweight, unofficial Bitwarden client that replaces the desktop app. "
                      + "Installs from Arch's repositories: " + (root.status.missing || []).join(", ") + "."
              doneText: "Installed"
              done: root.status.installed

              ActionButton { text: "Install"; onClicked: root.run("install") }
            }

            StepRow {
              number: 2
              title: "Bitwarden account"
              detail: root.status.loggedIn
                      ? "Saving a different account or server logs this one out and removes its local vault copy."
                      : "Your vault stays in Bitwarden. This tells rbw where to find it, and sets a graphical "
                        + "password prompt and a 15-minute auto-lock unless you've already changed those in rbw."
              doneText: root.status.email + " · " + (root.serverChoice === "com" ? "bitwarden.com"
                        : root.serverChoice === "eu" ? "bitwarden.eu" : root.status.baseUrl)
              done: root.hasAccount && !editAccount.checked
              available: root.status.installed

              TextField {
                id: emailField
                width: parent.width
                placeholderText: "Email address"
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onAccepted: saveAccount.clicked()
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: [{ id: "com", label: "bitwarden.com" }, { id: "eu", label: "bitwarden.eu" }, { id: "custom", label: "Self-hosted" }]
                  ActionButton {
                    required property var modelData
                    text: modelData.label
                    selected: root.serverChoice === modelData.id
                    onClicked: root.serverChoice = modelData.id
                  }
                }
              }

              TextField {
                id: urlField
                width: parent.width
                visible: root.serverChoice === "custom"
                placeholderText: "https://vault.example.com"
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onAccepted: saveAccount.clicked()
              }

              ActionButton {
                id: saveAccount
                text: "Save"
                onClicked: {
                  editAccount.checked = false
                  root.run("account", [emailField.text.trim(), root.serverChoice === "custom" ? urlField.text.trim() : root.serverChoice])
                }
              }
            }

            // Lets the done account step be reopened for editing.
            QtObject { id: editAccount; property bool checked: false }

            StepRow {
              number: 3
              visible: root.status.official
              title: "Register this device"
              detail: "Bitwarden's servers require a one-time device registration with your personal API key. "
                      + "rbw uses it once and doesn't store it; you still log in with your master password. "
                      + "In the web vault, choose \"View API key\", then press Register."
              doneText: "Registered"
              done: root.status.registered || root.status.loggedIn
              available: root.hasAccount

              Flow {
                width: parent.width
                spacing: Style.space(6)
                ActionButton { text: "Open API key page"; onClicked: root.run("api-key-page") }
                ActionButton { text: "Register"; onClicked: root.run("register") }
              }
            }

            StepRow {
              number: root.loginStep
              title: "Log in"
              detail: "A prompt asks for your master password, then your two-factor code if you use one. "
                      + "Supported: authenticator app, email, YubiKey OTP. Not supported: passkeys/WebAuthn, Duo."
              doneText: root.status.items + " items synced"
              done: root.status.loggedIn
              available: root.hasAccount

              ActionButton { text: "Log in"; onClicked: root.run("login") }
            }

            StepRow {
              number: root.loginStep + 1
              title: "Keyboard shortcut"
              detail: "SUPER + ALT + P opens a searchable vault menu."
              doneText: "SUPER + ALT + P opens your vault"
              done: root.status.keybind
              available: root.status.installed

              ActionButton { text: "Add shortcut"; onClicked: root.run("keybind-add") }
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              visible: root.hasAccount || root.status.keybind
              enabled: !root.busy

              ActionButton {
                visible: root.hasAccount && !editAccount.checked
                text: "Change account"
                onClicked: editAccount.checked = true
              }
              ActionButton {
                visible: root.status.keybind
                text: "Remove shortcut"
                onClicked: root.run("keybind-remove")
              }
            }
          }
        }
      }
    }
  }
}
