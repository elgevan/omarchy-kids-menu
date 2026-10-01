import QtQuick
import Quickshell.Io

// FileView only watches and atomically writes here. In particular, never call
// its text(), data() or reload(): those would read unbounded bytes in the shell.
Item {
  id: root

  property string path: ""
  property bool ready: false
  property int requestedGeneration: 0
  property int runningGeneration: 0
  property bool readBusy: false
  property bool readPending: false
  property bool writing: false
  property bool writeQueued: false
  property string pendingText: ""
  property bool retryParent: false
  property bool watchVerified: false
  property bool hasResult: false
  property bool lastSucceeded: false
  readonly property string readerPath: {
    var url = String(Qt.resolvedUrl("read-mode-state"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  signal loaded(string content)
  signal loadFailed()

  function rearmWatch() {
    watcher.path = ""
    watcher.path = root.path
  }

  function reload() {
    root.requestedGeneration++
    root.readPending = true
    if (!root.ready) return
    root.startRead()
  }

  function startRead() {
    if (!root.ready || !root.readPending || root.readBusy || reader.running
        || root.writing || root.writeQueued) return
    root.runningGeneration = root.requestedGeneration
    root.readPending = false
    root.readBusy = true
    reader.running = true
  }

  function finishRead(exitCode, content) {
    if (!root.readBusy) return
    root.readBusy = false
    // A file event or local write invalidates an older subprocess result.
    if (root.runningGeneration === root.requestedGeneration && !root.writing) {
      root.retryParent = exitCode === 3
      if (root.retryParent) root.watchVerified = false
      else if (!root.watchVerified) {
        // A parent may have appeared since startup. Rearm once, then verify
        // with a new read while that watch is live. Never tear down a normal
        // watch just before delivering a result: it could lose a queued edit.
        root.rearmWatch()
        root.watchVerified = true
        root.reload()
        return
      }
      var succeeded = exitCode === 0
      // A missing reader/dependency must not cause an active service to repair
      // state forever. A later successful read still delivers even when its
      // value is unchanged, so fixing permissions can trigger another repair.
      if (succeeded || !root.hasResult || root.lastSucceeded) {
        root.hasResult = true
        root.lastSucceeded = succeeded
        if (succeeded) root.loaded(content)
        else root.loadFailed()
      }
    }
    if (root.runningGeneration !== root.requestedGeneration)
      Qt.callLater(root.startRead)
  }

  function setText(content) {
    root.requestedGeneration++
    root.readPending = false
    root.pendingText = content
    root.writeQueued = true
    root.startWrite()
  }

  function startWrite() {
    if (root.writing || !root.writeQueued) return
    root.writing = true
    root.writeQueued = false
    // Clear the write cache without disturbing the independent live watch.
    // Otherwise a repeated repair can be skipped after an external edit.
    writer.path = ""
    writer.path = root.path
    writer.setText(root.pendingText)
  }

  function finishWrite() {
    root.writing = false
    if (root.writeQueued) root.startWrite()
    else {
      // The independent watcher already queues real target-file changes.
      // Do not manufacture an event: some Quickshell versions report saved
      // even when QSaveFile's final commit failed without changing the file.
      // Drain real events after failures too; they may be an external repair.
      if (root.readPending) Qt.callLater(root.startRead)
    }
  }

  FileView {
    id: watcher
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: root.reload()
  }

  FileView {
    id: writer
    preload: false
    atomicWrites: true
    printErrors: false
    // FileView still owns its live write job while these signals are emitted.
    // Rearming/writing synchronously here would re-enter that job's completion.
    onSaved: Qt.callLater(root.finishWrite)
    onSaveFailed: Qt.callLater(root.finishWrite)
  }

  Process {
    id: reader
    command: ["bash", root.readerPath, root.path]
    stdout: StdioCollector { id: output; waitForEnd: true }
    onExited: function(exitCode) { root.finishRead(exitCode, output.text) }
  }

  Timer {
    interval: 4000
    running: root.readBusy
    onTriggered: {
      // FailedToStart has no exited signal on Quickshell 0.2.1.
      if (!reader.running) root.finishRead(1, "")
      else reader.signal(9)
    }
  }

  // QFileSystemWatcher cannot watch a parent directory that does not exist.
  // Retry only that startup case; normal edits use the file/parent watches.
  Timer {
    interval: 1000
    repeat: true
    running: root.retryParent
    onTriggered: root.reload()
  }

  onPathChanged: {
    root.watchVerified = false
    root.hasResult = false
    if (root.ready) root.rearmWatch()
    root.reload()
  }
  Component.onCompleted: {
    root.ready = true
    root.rearmWatch()
    root.reload()
  }
}
