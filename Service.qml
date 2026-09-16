import QtQuick
import Quickshell
import Quickshell.Io
import "TaskModel.js" as Model

// Single-instance task store + reminder scheduler. Mounted once at shell
// startup (kind "service"), so the "5 minutes after login" rule works even
// if the bar widget or panel are never opened. The per-monitor bar widgets
// and panels read state off this via shell.serviceFor().
//
// Persistence is write-safe so a plugin update can never lose tasks:
//   - the store atomically swaps the new content in (write .tmp, then rename),
//     so a partial write can never corrupt tasks.json,
//   - the last good content is copied to tasks.json.bak before each write,
//   - the store refuses to write until it has loaded the file once, so a
//     hot reload of the service can never clobber the store with an empty
//     list mid-reload.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/cronos"
  readonly property string statePath: root.stateDir + "/tasks.json"
  readonly property string backupPath: root.statePath + ".bak"
  readonly property string legacyStatePath: Quickshell.env("HOME") + "/.local/state/omarchy/taskboard/tasks.json"

  readonly property date bootTime: new Date()
  readonly property int reminderDelayMs: 5 * 60 * 1000

  property var tasks: Model.parse("")
  property bool storeReady: false

  property real nowMs: Date.now()
  readonly property string today: Model.todayStamp()
  readonly property int openCount: Model.openTasks(root.tasks).length
  readonly property bool urgent: Model.needsAttention(root.tasks, root.nowMs)
  readonly property var sortedTasks: Model.sortByDue(root.tasks)
  readonly property var sortedOpenTasks: Model.sortByDue(Model.openTasks(root.tasks))
  readonly property var sortedDoneTasks: Model.sortByDue(Model.closedTasks(root.tasks))

  // Backup is declared (and preloaded) before the main store so the failure
  // handler below can read it synchronously.
  FileView {
    id: storeBackup
    path: root.backupPath
    watchChanges: false
    preload: true
    printErrors: false
  }

  FileView {
    id: store
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.tasks = Model.parse(text())
      root.storeReady = true
    }
    onLoadFailed: {
      // Missing file (first launch) -> empty store. Corrupt/unreadable main
      // file -> fall back to the last good backup if there is one.
      root.storeReady = true
      var t = storeBackup.text()
      root.tasks = Model.parse(t)
    }
  }

  // One tick per minute; notifications are gated to "5 minutes after this
  // service started" (service starts with the shell, i.e. at login).
  Timer {
    id: scheduler
    interval: 60 * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  function tick() {
    // FileView stops watching a path that did not exist when it mounted, so
    // re-read the store every minute. Reminders are minute-granular anyway;
    // reload() lands a tick later, which is fine.
    store.reload()
    root.nowMs = Date.now()
    if (root.nowMs - root.bootTime.getTime() >= root.reminderDelayMs) root.fireDue()
  }

  // Report each open task whose reminder moment has arrived exactly once per
  // task. The rule is now >= max(reminderMs, boot + grace): a reminder still
  // in the future fires at its minute; one that passed while the machine was
  // off is picked up 5 minutes after the next login.
  function fireDue() {
    var now = root.nowMs
    var due = Model.openTasks(root.tasks).filter(function(t) {
      return Model.isReminderPending(t, now, root.bootTime.getTime(), root.reminderDelayMs)
    })
    if (due.length === 0) return
    var changed = false
    for (var i = 0; i < due.length; i++) {
      var task = due[i]
      root.tasks = Model.openTasks(root.tasks).map(function(t) {
        if (t.id !== task.id) return t
        changed = true
        var copy = {}
        for (var k in t) copy[k] = t[k]
        copy.firedAt = Model.localIso(now)
        return copy
      })
      root.notify(task, now)
    }
    if (changed) root.save()
  }

  function notify(task, nowMs) {
    var dueMs = Model.dueMs(task)
    var line = "Due " + (isNaN(dueMs) ? task.due : Model.humanDue(task.due, nowMs))
    var lead = Number(task.leadHours) || 0
    if (lead > 0) line += " · reminder " + Model.leadLabel(lead) + " before"

    Quickshell.execDetached([
      root.omarchyPath + "/bin/omarchy-notification-send",
      "--app-name", "cronos",
      "-g", "",
      "-u", "normal",
      "Task due",
      task.title + "\n" + line
    ])
  }

  // ---- mutations (called from the panel) --------------------------------

  // Do not mutate before the store has loaded once, otherwise a hot reload of
  // the service could overwrite the file with an empty task list. Returns
  // false while the initial read is still in flight (a few ms at startup);
  // the panel just retries on the next user action.
  function ensureStoreReady() {
    return root.storeReady
  }

  // dueInput is a bare date ("2026-09-30", "hoy", "+3", ...) resolved against
  // today; timeInput is optional "HH:MM". leadHours is the advance warning.
  function add(title, dueInput, timeInput, leadHours, notes, leadMode) {
    if (!root.ensureStoreReady()) return false
    var t = String(title || "").trim()
    var iso = Model.parseDue(dueInput, root.today)
    if (!t || !iso) return false
    root.tasks = root.tasks.concat([Model.makeTask(t, Model.composeDue(iso, timeInput), leadHours, Date.now(), notes, leadMode)])
    root.save()
    return true
  }

  function removeTask(id) {
    if (!root.ensureStoreReady()) return
    root.tasks = root.tasks.filter(function(t) { return t.id !== id })
    root.save()
  }

  function toggleDone(id) {
    if (!root.ensureStoreReady()) return
    root.tasks = root.tasks.map(function(t) {
      if (t.id !== id) return t
      var copy = {}
      for (var k in t) copy[k] = t[k]
      copy.done = !copy.done
      // Reopening a task re-arms its reminder (if the day has passed, the
      // next check reports it again).
      if (!copy.done) copy.firedAt = null
      return copy
    })
    root.save()
  }

  function save() {
    if (!root.storeReady) return
    // The JSON is passed straight through the argv (UTF-8) so accents and the
    // like survive byte-for-byte; no base64 round-trip that could re-encode.
    // Write to .tmp, snapshot the current file to .bak, atomically rename in.
    var payload = Model.serialize(root.tasks)
    Quickshell.execDetached([
      "bash", "-c",
      "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3.tmp\" && (cp -f \"$3\" \"$3.bak\" 2>/dev/null || true) && mv -f \"$3.tmp\" \"$3\"",
      "cronos",
      root.stateDir, payload, root.statePath
    ])
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
    // One-off migration for installs that had the plugin under its former id
    // ("angelherman.taskboard" stored in ~/.local/state/omarchy/taskboard).
    // Only copies if no cronos store exists yet, so data is never clobbered.
    Quickshell.execDetached([
      "bash", "-c",
      "if [ ! -e \"$2\" ] && [ -s \"$3\" ]; then mkdir -p \"$1\" && cp -f \"$3\" \"$2\"; fi",
      "cronos",
      root.stateDir, root.statePath, root.legacyStatePath
    ])
  }
}