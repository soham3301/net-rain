pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Net Rain - a purely visual network monitor for the Omarchy bar.
// Download dots fall from the top, upload dots rise from the bottom, both
// mixed in one black panel. More traffic = more dots, faster dots, hotter
// colour (green > yellow > red > purple). No text, no mouse handling.
Item {
  id: root

  // Set by the bar after load.
  property var bar: null
  property string moduleName: ""
  property var settings: null

  function setting(key: string, fallback: var): var {
    const value = root.settings ? root.settings[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ---- geometry -----------------------------------------------------------
  readonly property bool vertical: root.bar ? root.bar.vertical === true : false
  readonly property int barSize: root.bar ? Math.round(Number(root.bar.barSize)) : 26
  readonly property int dot: Math.max(1, Math.round(Number(root.setting("dotSize", 4))))
  readonly property int gap: Math.max(0, Math.round(Number(root.setting("dotGap", 2))))
  readonly property int pitch: root.dot + root.gap
  readonly property int inset: Math.floor(root.gap / 2)
  readonly property int longSide: Math.max(root.pitch * 4, Math.round(Number(root.setting("width", 90))))
  readonly property int crossCells: Math.max(2, Math.min(Math.round(Number(root.setting("maxRows", 5))), Math.floor((root.barSize - 2) / root.pitch)))
  readonly property int cols: Math.floor((root.vertical ? root.crossCells * root.pitch : root.longSide) / root.pitch)
  readonly property int rows: Math.floor((root.vertical ? root.longSide : root.crossCells * root.pitch) / root.pitch)
  readonly property int viewW: root.cols * root.pitch
  readonly property int viewH: root.rows * root.pitch
  readonly property int margin: 4

  implicitWidth: root.vertical ? root.barSize : root.viewW + root.margin * 2
  implicitHeight: root.vertical ? root.viewH + root.margin * 2 : root.barSize

  // ---- state --------------------------------------------------------------
  property var grid: []          // colour per cell, undefined = empty
  property var blocks: []        // live dots {x, y, dir, color}
  property var prevBytes: ({})   // per-interface [rx, tx] from the last sample
  property double lastSample: 0
  property double lastTick: 0
  property real dlMbps: 0        // measured
  property real ulMbps: 0
  property real dlShown: 0.001   // smoothed, drives the animation
  property real ulShown: 0.001
  property real accDown: 0
  property real accUp: 0

  onColsChanged: { root.blocks = []; root.grid = [] }
  onRowsChanged: { root.blocks = []; root.grid = [] }

  // ---- network sampling (/proc/net/dev) -----------------------------------
  function wanted(name: string, want: string): bool {
    if (want === "auto")
      return /^(en|eth|wl|ww)/.test(name)
    return want.split(",").map(s => s.trim()).indexOf(name) >= 0
  }

  function sample(content: string) {
    const now = Date.now()
    const want = String(root.setting("interface", "auto"))
    const prev = root.prevBytes
    const next = ({})
    let rx = 0
    let tx = 0
    const lines = content.split("\n")
    for (let i = 0; i < lines.length; i++) {
      const colon = lines[i].indexOf(":")
      if (colon < 0)
        continue
      const name = lines[i].slice(0, colon).trim()
      if (!root.wanted(name, want))
        continue
      const f = lines[i].slice(colon + 1).trim().split(/\s+/)
      const r = Number(f[0])
      const t = Number(f[8])
      if (isNaN(r) || isNaN(t))
        continue
      next[name] = [r, t]
      if (prev[name]) {
        if (r > prev[name][0]) rx += r - prev[name][0]
        if (t > prev[name][1]) tx += t - prev[name][1]
      }
    }
    const secs = (now - root.lastSample) / 1000
    if (root.lastSample > 0 && secs > 0.05) {
      root.dlMbps = rx * 8 / 1e6 / secs
      root.ulMbps = tx * 8 / 1e6 / secs
    }
    root.lastSample = now
    root.prevBytes = next
  }

  // ---- speed -> look ------------------------------------------------------
  // 0..1 on a log scale: ~50 kb/s = 0, ~100 Mb/s = 1
  function level(mbps: real): real {
    return Math.max(0, Math.min(1, Math.log(mbps / 0.05) / Math.LN10 / 3.3))
  }

  // green (kb/s) > yellow (1-9) > red (10-50) > purple (50+), blended smoothly
  function colorFor(mbps: real): var {
    const stops = [
      [0.3, [40, 225, 95]],
      [1.5, [255, 220, 0]],
      [8, [255, 220, 0]],
      [15, [255, 50, 35]],
      [45, [255, 50, 35]],
      [60, [185, 70, 255]]
    ]
    if (mbps <= stops[0][0])
      return stops[0][1]
    for (let i = 1; i < stops.length; i++) {
      if (mbps <= stops[i][0]) {
        const a = stops[i - 1]
        const b = stops[i]
        const f = (Math.log(mbps) - Math.log(a[0])) / (Math.log(b[0]) - Math.log(a[0]))
        return [0, 1, 2].map(j => a[1][j] + (b[1][j] - a[1][j]) * f)
      }
    }
    return stops[stops.length - 1][1]
  }

  function makeBlock(dir: int, mbps: real): var {
    const c = root.colorFor(mbps)
    const shade = 0.6 + 0.4 * Math.random()
    return {
      x: Math.floor(Math.random() * root.cols),
      y: dir > 0 ? -1 : root.rows,
      dir: dir,
      color: Qt.rgba(c[0] * shade / 255, c[1] * shade / 255, c[2] * shade / 255, 1)
    }
  }

  // ---- animation step -----------------------------------------------------
  function step() {
    const now = Date.now()
    const dt = root.lastTick > 0 ? Math.min(0.1, (now - root.lastTick) / 1000) : 0.04
    root.lastTick = now

    const k = 1 - Math.exp(-dt / 0.7)
    root.dlShown = Math.max(0.001, root.dlShown + (root.dlMbps - root.dlShown) * k)
    root.ulShown = Math.max(0.001, root.ulShown + (root.ulMbps - root.ulShown) * k)
    const ld = root.level(root.dlShown)
    const lu = root.level(root.ulShown)

    root.accDown += (0.6 + 22 * Math.pow(ld, 1.5)) * dt
    root.accUp += (0.5 + 18 * Math.pow(lu, 1.5)) * dt
    const list = root.blocks
    while (root.accDown >= 1) { root.accDown -= 1; list.push(root.makeBlock(1, root.dlShown)) }
    while (root.accUp >= 1) { root.accUp -= 1; list.push(root.makeBlock(-1, root.ulShown)) }
    if (list.length > 600)
      list.splice(0, list.length - 600)

    const cols = root.cols
    const rows = root.rows
    const alive = []
    const cells = new Array(cols * rows)
    for (let i = 0; i < list.length; i++) {
      const b = list[i]
      b.y += b.dir * (1.2 + 11 * (b.dir > 0 ? ld : lu)) * dt
      if (b.y <= -1.5 || b.y >= rows + 0.5)
        continue
      alive.push(b)
      const r = Math.floor(b.y)
      if (r >= 0 && r < rows && b.x < cols)
        cells[r * cols + b.x] = b.color
    }
    root.blocks = alive
    root.grid = cells
  }

  FileView {
    id: netdev
    path: "/proc/net/dev"
    onLoaded: root.sample(netdev.text())
  }

  Timer {
    interval: 500
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: netdev.reload()
  }

  Timer {
    interval: 40
    repeat: true
    running: root.visible && root.cols > 0 && root.rows > 0
    onTriggered: root.step()
  }

  // ---- drawing ------------------------------------------------------------
  // Background never changes colour: black, with a barely-there green CRT tint.
  Rectangle {
    id: screen
    anchors.centerIn: parent
    width: root.viewW
    height: root.viewH
    color: "#040807"
    clip: true

    Repeater {
      model: root.cols * root.rows
      delegate: Rectangle {
        required property int index
        x: (index % root.cols) * root.pitch + root.inset
        y: Math.floor(index / root.cols) * root.pitch + root.inset
        width: root.dot
        height: root.dot
        color: root.grid[index] || "transparent"
      }
    }

    Repeater {
      model: Math.ceil(screen.height / 3)
      delegate: Rectangle {
        required property int index
        y: index * 3
        width: screen.width
        height: 1
        color: Qt.rgba(0, 0.16, 0.04, 0.18)
      }
    }
  }
}
