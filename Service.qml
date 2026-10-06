import QtQuick
import Quickshell
import Quickshell.Io

// One per shell (bar widgets run once per monitor). Runs bin/bw-guard, which
// locks the vault on screen lock and before sleep, and answers the keyboard
// shortcut: `omarchy-shell adami.bitwarden-vault menu`. Going through IPC keeps
// the binding free of the plugin's path, so it's inert once the plugin is gone.
Scope {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string binDir: decodeURIComponent(String(Qt.resolvedUrl("bin")).replace(/^file:\/\//, ""))

  // Restart a failed guard after 5s, doubling up to 5 minutes. A run that
  // lasted a minute counts as healthy and resets the delay.
  property int restartDelay: 5000
  property double startedAt: 0

  IpcHandler {
    target: "adami.bitwarden-vault"
    function menu(): void { Quickshell.execDetached([root.binDir + "/bw-menu"]) }
  }

  Process {
    id: guard
    running: true
    command: [root.binDir + "/bw-guard"]
    onRunningChanged: if (running) root.startedAt = Date.now()
    onExited: {
      if (Date.now() - root.startedAt > 60000) root.restartDelay = 5000
      restart.interval = root.restartDelay
      restart.start()
      root.restartDelay = Math.min(root.restartDelay * 2, 300000)
    }
  }

  Timer {
    id: restart
    onTriggered: guard.running = true
  }
}
