const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const {spawnSync} = require("node:child_process")
const vm = require("node:vm")

const plugin = process.argv[2] || path.resolve(__dirname, "..")
for (const [name, handler] of [["Service.qml", "loadModeState"], ["BarWidget.qml", "loadMode"]]) {
  const source = fs.readFileSync(path.join(plugin, name), "utf8")
  assert.match(source, new RegExp(`ModeFile \\{[^}]*path: root\\.modePath[^}]*root\\.${handler}\\(content\\)`))
  assert.doesNotMatch(source, /FileView \{[^}]*path: root\.modePath/)
}

const source = fs.readFileSync(path.join(plugin, "ModeFile.qml"), "utf8")
assert.match(source, /preload: false/)
assert.match(source, /watchChanges: true/)
assert.match(source, /atomicWrites: true/)
assert.doesNotMatch(source, /(?:watcher|writer)\.(?:text|data|reload)\(/)
assert.match(source, /onSaved: Qt\.callLater\(root\.finishWrite\)/)
assert.match(source, /onSaveFailed: Qt\.callLater\(root\.finishWrite\)/)
assert.match(source, /if \(!reader\.running\) root\.finishRead\(1, ""\)/)

// Exercise the actual QML JavaScript methods, with only the IO objects mocked.
function harness() {
  const delivered = [], deferred = [], writes = []
  const root = {
    path: "/config/mode.json", ready: true, requestedGeneration: 0,
    runningGeneration: 0, readBusy: false, readPending: false,
    writing: false, writeQueued: false,
    pendingText: "", retryParent: false, watchVerified: true,
    hasResult: false, lastSucceeded: false, lastContent: "",
    loaded: content => delivered.push(content),
    loadFailed: () => delivered.push(null)
  }
  let filePath = "", cached = null, liveWrite = false, watchResets = 0
  const watcher = {
    set path(value) { if (!value) watchResets++ }
  }
  const writer = {
    set path(value) {
      assert.equal(liveWrite, false, "must not reenter a live FileView write")
      filePath = value
      if (!value) {
        cached = null
      }
    },
    get path() { return filePath },
    setText(content) {
      assert.equal(liveWrite, false)
      if (cached === content) return
      cached = content
      liveWrite = true
      writes.push(content)
    }
  }
  const reader = {running: false}
  const context = vm.createContext({root, watcher, writer, reader,
    Qt: {callLater: (fn, ...args) => deferred.push(() => fn(...args))}})
  for (const match of source.matchAll(/^  function (\w+)\(([^)]*)\) \{([\s\S]*?)^  \}/gm))
    root[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
  return {
    root, reader, delivered, writes,
    get watchResets() { return watchResets },
    flush() { while (deferred.length) deferred.shift()() },
    finish(code, content) { reader.running = false; root.finishRead(code, content) },
    saved(succeeded = true) {
      // The source handlers defer until FileView clears its live operation.
      deferred.push(() => root.finishWrite(succeeded))
      liveWrite = false
    }
  }
}

let h = harness()
h.root.reload()
assert.equal(h.reader.running, true)
h.root.reload()
h.root.reload()
h.finish(0, "stale")
assert.deepEqual(h.delivered, [])
h.flush()
assert.equal(h.reader.running, true)
h.finish(0, "latest")
assert.deepEqual(h.delivered, ["latest"])

h = harness()
h.root.reload()
h.root.setText("true")
h.root.setText("false")
assert.deepEqual(h.writes, ["true"])
h.finish(0, "old true")
h.flush()
assert.deepEqual(h.delivered, [])
assert.equal(h.reader.running, false)
h.saved()
h.flush()
assert.deepEqual(h.writes, ["true", "false"])
h.root.reload() // the target's atomic-write event arrives while still writing
h.saved()
h.flush()
h.finish(0, "false")
assert.deepEqual(h.delivered, ["false"])
// A repeated repair must not be deduplicated against FileView's old cache.
h.root.setText("false")
assert.deepEqual(h.writes, ["true", "false", "false"])

h = harness()
h.root.reload()
assert.equal(h.watchResets, 0)
h.finish(3, "")
assert.equal(h.root.retryParent, true)
assert.deepEqual(h.delivered, [null])
h.root.reload()
const watchesBeforeParentAppears = h.watchResets
h.finish(0, "recovered")
assert.equal(h.watchResets, watchesBeforeParentAppears + 1,
  "rearm after a parent appears between starting and completing a read")
assert.equal(h.root.retryParent, false)
assert.deepEqual(h.delivered, [null], "do not deliver pre-rearm data")
h.finish(0, "recovered")
assert.deepEqual(h.delivered, [null, "recovered"])
h.root.reload()
h.finish(1, "")
assert.equal(h.root.retryParent, false)
assert.deepEqual(h.delivered, [null, "recovered", null])

h = harness()
h.root.loadFailed = () => h.root.setText("repair active mode")
h.root.reload()
h.finish(1, "")
assert.deepEqual(h.writes, ["repair active mode"])
h.saved(false)
h.flush()
assert.equal(h.root.writing, false)
assert.equal(h.reader.running, false, "failed repair must not reread in a busy loop")
assert.equal(h.root.readPending, false)
// A later external event can recover after the failed repair.
h.root.reload()
h.finish(0, "repaired externally")
assert.deepEqual(h.delivered, ["repaired externally"])

h = harness()
h.root.loadFailed = () => h.root.setText("repair active mode")
h.root.reload()
h.finish(1, "")
h.root.reload() // successful repair emits a real file change
h.saved()
h.flush()
h.finish(1, "") // reader/dependency remains unavailable
assert.deepEqual(h.writes, ["repair active mode"])
assert.equal(h.reader.running, false, "repeated read failures must settle")

h = harness()
h.root.loaded = content => {
  h.delivered.push(content)
  if (content === "false") h.root.setText("true")
}
h.root.reload()
h.finish(0, "false")
// Even if Quickshell reports saved on a failed commit, no target event means
// no synthetic reread/repair loop. A later external event is still delivered.
h.saved()
h.flush()
assert.equal(h.reader.running, false)
h.root.reload()
h.finish(0, "false")
assert.deepEqual(h.writes, ["true", "true"])

h = harness()
h.root.setText("true")
h.root.reload() // external repair arrives during a write that then fails
h.saved(false)
h.flush()
assert.equal(h.reader.running, true)
h.finish(0, "external repair")
assert.deepEqual(h.delivered, ["external repair"])

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "kids-mode-file-"))
const target = path.join(dir, "mode with spaces.json")
const helper = path.join(plugin, "read-mode-state")
const valid = '{"version":1,"enabled":true}'
function read(file = target, env = process.env) {
  const result = spawnSync("bash", [helper, file], {encoding: "utf8", timeout: 5000, env})
  assert.ifError(result.error)
  assert.equal(result.signal, null)
  assert.ok(Buffer.byteLength(result.stdout) <= 32, "only canonical state reaches QML")
  return result
}
function reject(content) {
  fs.writeFileSync(target, content)
  const result = read()
  assert.notEqual(result.status, 0)
  assert.equal(result.stdout, "")
}
try {
  assert.equal(read().status, 1)
  assert.equal(read(path.join(dir, "absent", "mode.json")).status, 3)
  fs.writeFileSync(target, valid)
  assert.deepEqual(JSON.parse(read().stdout), {version: 1, enabled: true})
  fs.writeFileSync(target, valid + " ".repeat(4096 - Buffer.byteLength(valid)))
  assert.equal(read().status, 0)
  reject(valid + " ".repeat(4097 - Buffer.byteLength(valid)))
  reject(valid + " ".repeat(1024 * 1024))
  const invalidUtf8 = Buffer.concat([Buffer.from('{"version":1,"enabled":true,"padding":"'),
    Buffer.from([0xf0, 0x80, 0x80, 0x80]), Buffer.from('"}')])
  reject(Buffer.concat([invalidUtf8, Buffer.alloc(4097 - invalidUtf8.length, 32)]))
  reject(Buffer.concat([invalidUtf8, Buffer.alloc(1024 * 1024, 32)]))
  reject('{"version":1,"enabled":true,"padding":"' + "é".repeat(2048) + '"}')
  for (const invalid of ["", "not json", "{}", "null", "[]",
    '{"version":2,"enabled":true}', '{"version":1,"enabled":"true"}',
    valid + valid, valid + "\0", '{"version":1,"enabled":true\0}']) reject(invalid)

  const fifo = path.join(dir, "fifo")
  assert.equal(spawnSync("mkfifo", [fifo]).status, 0)
  assert.equal(read(fifo).status, 1)
  assert.equal(read(dir).status, 1)
  assert.equal(read("/dev/zero").status, 1)
  fs.writeFileSync(target, valid)
  const link = path.join(dir, "link")
  fs.symlinkSync(target, link)
  assert.equal(read(link).status, 1)

  const replacement = path.join(dir, "replacement")
  fs.writeFileSync(replacement, '{"version":1,"enabled":false}')
  fs.renameSync(replacement, target)
  assert.deepEqual(JSON.parse(read().stdout), {version: 1, enabled: false})

  // A stalled open/read must be contained in the subprocess, not the shell.
  const bin = path.join(dir, "bin")
  fs.mkdirSync(bin)
  fs.writeFileSync(path.join(bin, "head"), "#!/bin/bash\nsleep 10\n", {mode: 0o755})
  assert.equal(read(target, {...process.env, PATH: bin + ":" + process.env.PATH}).status, 124)
} finally {
  fs.rmSync(dir, {recursive: true, force: true})
}

console.log("Mode file read and lifecycle checks passed")
