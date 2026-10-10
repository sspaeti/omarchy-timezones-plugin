import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Worldtimebuddy-style popup: one 24-hour strip per zone, columns aligned on
// the same absolute moment, with a "now" line and hover-a-column conversion.
Panel {
  id: root
  moduleName: "io.github.sspaeti.timezones"
  ipcTarget: "io.github.sspaeti.timezones"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by must be that
  // widget (popout coordinator, switchPanelFrom).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    // Set after showing: showing hands the popout coordinator over, which
    // closes the previously open panel, and that close clears the flag.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // An installed plugin may be handed a PluginBarApi facade rather than the
  // Bar itself (Omarchy 4.x), and there this property is a read-only mirror —
  // assigning to it throws, and the throw aborted close() before it reached
  // controller.hide(), leaving the panel stuck open with its keyboard grab.
  // Prefer the setter the facade exposes; keep the assignment for a host
  // Bar with a writable property. (#8, #9)
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Time state. Offsets come from tzdata via `date`, so DST is always
  //      right; the home row follows the system timezone (travel-proof).
  property double nowUtc: Date.now()
  property var offsets: ({})
  property string systemTz: ""

  // ---- Display mode: "24h" (default), "12h" (AM/PM) or "utc" (24-hour plus
  //      a UTC reference row under home). Seeded from shell.json, then owned
  //      by the session so `t` in the popup cycles it without a config edit.
  readonly property string configuredHourFormat: Model.normalizeHourFormat(setting("hourFormat", "24h"))
  property string hourFormat: configuredHourFormat
  onConfiguredHourFormatChanged: hourFormat = configuredHourFormat
  readonly property bool use12Hour: hourFormat === "12h"
  readonly property bool showUtc: hourFormat === "utc"

  function cycleHourFormat() {
    hourFormat = Model.nextHourFormat(hourFormat)
  }

  // A bar (and so a panel) exists per monitor; route through the host widget
  // so every screen flips together rather than just this one.
  function cycleHourFormatEverywhere() {
    if (hostWidget && typeof hostWidget.cycleHourFormat === "function") hostWidget.cycleHourFormat()
    else cycleHourFormat()
  }

  function openWorldtimebuddy() {
    if (hostWidget && typeof hostWidget.openWorldtimebuddy === "function") hostWidget.openWorldtimebuddy()
  }

  readonly property var zoneConfig: setting("zones", Model.defaultZones())
  // System timezones that keep the configured home label. Outside this list
  // (or with none configured) the home row is labeled by where the system
  // clock actually is, so traveling relabels it automatically.
  readonly property var homeZoneNames: setting("homeZones", [])
  readonly property color fg: bar ? bar.foreground : "#e0e0e0"
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family

  readonly property var zones: buildZones()

  function buildZones() {
    var out = []
    for (var i = 0; i < zoneConfig.length; i++) {
      var cfg = zoneConfig[i]
      var key = cfg.home ? "HOME" : cfg.zone
      var probed = offsets[key] || null
      var label = cfg.label
      // Away from the configured home zone, label the home row by where the
      // system actually is (e.g. "New York" while traveling).
      if (cfg.home && systemTz !== "" && homeZoneNames.indexOf(systemTz) === -1)
        label = systemTz.split("/").pop().replace(/_/g, " ")
      // Config strings are sanitized here — the single source every
      // consumer (panel texts, bar hover label) reads from.
      out.push({
        label: Model.plainText(label),
        shortLabel: Model.plainText(cfg.shortLabel || ""),
        abbr: Model.plainText(cfg.abbr || (probed ? probed.abbr : "")),
        home: cfg.home === true,
        offsetMin: probed ? probed.offsetMin : null
      })
    }
    return showUtc ? Model.withUtcRow(out) : out
  }

  readonly property var homeRow: {
    for (var i = 0; i < zones.length; i++) if (zones[i].home) return zones[i]
    return null
  }
  readonly property bool ready: homeRow !== null && homeRow.offsetMin !== null
  readonly property double dayStart: ready ? Model.homeDayStartUtc(nowUtc, homeRow.offsetMin) : 0
  readonly property double nowCol: ready ? Model.nowColumn(nowUtc, dayStart) : 0
  readonly property string homeDate: ready ? Model.dateLabel(nowUtc, homeRow.offsetMin) : ""
  property int hoverCol: -1

  // ---- Keyboard column selection (h/l, ←/→). Writes the same hoverCol the
  //      mouse does, so a keypress and a hover are indistinguishable to the
  //      rest of the panel. The first press steps off the column "now" sits
  //      in — landing on it would look like nothing happened, since that is
  //      exactly what the unselected headers already show.
  function moveHoverCol(step) {
    if (!ready) return
    var from = hoverCol >= 0 ? hoverCol : Math.floor(nowCol)
    hoverCol = Math.max(0, Math.min(23, from + step))
  }

  // The grid is one home day, so a stale selection would misread as "now"
  // on the next open. Covers every close path, not just root.close().
  onOpenedChanged: if (!opened) hoverCol = -1

  // What the bar pill shows on hover.
  readonly property string compactLabel: ready ? Model.compactLabel(zones, nowUtc, use12Hour, setting("barZones", [])) : ""

  // ---- `p`: copy the popup as a PNG to the clipboard — hovered/selected
  //      column and its converted times included — so a future meeting slot
  //      can be shared as-is. Rendered from the scene, not the screen, so
  //      nothing else on the desktop leaks into the image.
  function copyScreenshot() {
    // Climb from the content to the card (background + border) the panel
    // draws — the first ancestor sized exactly contentWidth × contentHeight.
    // Going any higher lands on Quickshell's window proxy items, which have
    // no QML engine to grab with.
    var card = keyCatcher
    while (card.parent && !(card.width === panel.contentWidth && card.height === panel.contentHeight)) card = card.parent
    if (!card.parent || typeof card.grabToImage !== "function") return
    var dpr = panel.screen && panel.screen.devicePixelRatio > 0 ? panel.screen.devicePixelRatio : 1
    var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    var path = runtimeDir + "/omarchy-timezones-panel.png"
    card.grabToImage(function(result) {
      if (!result || !result.saveToFile(path)) return
      Quickshell.execDetached(["bash", "-c",
        "wl-copy -t image/png < " + Util.shellQuote(path)
        + " && { command -v omarchy-notification-send >/dev/null"
        + " && omarchy-notification-send 'Timezones' 'Panel copied to clipboard' -t 2000"
        + " || notify-send -t 2000 'Timezones' 'Panel copied to clipboard'; }"])
    }, Qt.size(Math.ceil(card.width * dpr), Math.ceil(card.height * dpr)))
  }

  // ---- Grid geometry.
  readonly property real cellW: Style.space(27)
  readonly property real cellH: Style.space(38)
  readonly property real cellGap: 1
  readonly property real headerW: Style.space(168)
  readonly property real headerGap: Style.space(14)
  readonly property real stripW: 24 * cellW + 23 * cellGap
  readonly property real rowGap: Style.space(6)

  function refresh() {
    var script = "echo \"TZNAME $(timedatectl show -p Timezone --value 2>/dev/null)\"; echo \"HOME $(date +'%z %Z')\""
    for (var i = 0; i < zoneConfig.length; i++) {
      var zone = String(zoneConfig[i].zone || "")
      if (zone === "" || !/^[A-Za-z0-9_\/+-]+$/.test(zone)) continue
      script += "; echo \"" + zone + " $(TZ='" + zone + "' date +'%z %Z')\""
    }
    offsetsProc.command = ["bash", "-c", script]
    offsetsProc.running = true
  }

  Process {
    id: offsetsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "")
        if (raw.trim() === "") return
        var m = /(^|\n)TZNAME\s+(\S+)/.exec(raw)
        if (m) root.systemTz = m[2]
        var parsed = Model.parseOffsetLines(raw)
        if (parsed.HOME) root.offsets = parsed
      }
    }
  }

  // Offsets can only change at wall-clock hour boundaries (DST switches) or
  // when the clock jumps (suspend/resume, timezone changed while traveling),
  // so re-probe exactly then rather than on a polling interval.
  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: {
      var previous = root.nowUtc
      root.nowUtc = date.getTime()
      if (date.getMinutes() === 0 || Math.abs(root.nowUtc - previous) > 120000)
        root.refresh()
    }
  }

  Component.onCompleted: root.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // contentWidth is the card's outer width: unlike fittedContentHeight,
    // fittedContentWidth does not add the padding/border inset, so add it
    // here or the last column gets clipped.
    contentWidth: panel.fittedContentWidth(root.headerW + root.headerGap + root.stripW + panel.verticalContentInset)
    contentHeight: panel.fittedContentHeight(rowsCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // ←/→ and h/l both arrive here — the catcher folds them into one signal
      // and never forwards them to onTextKey.
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.moveHoverCol(dx) }
      onTextKey: function(t) {
        if (t === "n" || t === "N") root.hoverCol = -1
        else if (t === "t" || t === "T") root.cycleHourFormatEverywhere()
        else if (t === "p" || t === "P" || t === "y" || t === "Y") root.copyScreenshot()
        else if (t === "r" || t === "R") root.refresh()
        else if (t === "w" || t === "W") root.openWorldtimebuddy()
      }

      Column {
        id: rowsCol
        width: parent.width
        spacing: root.rowGap

        Text {
          visible: !root.ready
          text: "Reading timezones…"
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Repeater {
          model: root.ready ? root.zones : []

          Item {
            id: zoneItem
            required property var modelData
            readonly property var zoneRow: modelData
            readonly property bool rowReady: zoneRow.offsetMin !== null
            readonly property string zoneDate: rowReady ? Model.dateLabel(root.nowUtc, zoneRow.offsetMin) : ""
            width: rowsCol.width
            height: root.cellH

            // ---- Row header: location name, (abbr), current time, offset.
            Column {
              width: root.headerW
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                spacing: Style.space(6)

                Text {
                  text: zoneItem.zoneRow.label
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.body
                  font.bold: zoneItem.zoneRow.home
                }
                Text {
                  visible: zoneItem.zoneRow.abbr !== ""
                  text: "(" + zoneItem.zoneRow.abbr + ")"
                  textFormat: Text.PlainText
                  color: Qt.darker(root.fg, 1.5)
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Row {
                spacing: Style.space(6)

                Text {
                  text: !zoneItem.rowReady ? "—"
                    : root.hoverCol >= 0
                      ? Model.timeLabel(root.dayStart + root.hoverCol * 3600000, zoneItem.zoneRow.offsetMin, root.use12Hour)
                      : Model.timeLabel(root.nowUtc, zoneItem.zoneRow.offsetMin, root.use12Hour)
                  color: root.hoverCol >= 0 ? Color.accent : root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  // Home shows its date; others their offset, plus the date
                  // whenever their calendar day differs from home's.
                  text: zoneItem.zoneRow.home
                    ? zoneItem.zoneDate
                    : (zoneItem.rowReady
                        ? Model.diffLabel(zoneItem.zoneRow.offsetMin, root.homeRow.offsetMin)
                          + (zoneItem.zoneDate !== root.homeDate ? "  " + zoneItem.zoneDate : "")
                        : "")
                  color: Qt.darker(root.fg, 1.5)
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // ---- Hour strip: 24 cells, one home-day left to right.
            Row {
              x: root.headerW + root.headerGap
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.cellGap

              Repeater {
                model: zoneItem.rowReady ? 24 : 0

                Rectangle {
                  required property int index
                  readonly property var c: Model.cell(index, root.dayStart, zoneItem.zoneRow.offsetMin)
                  readonly property bool hot: index === root.hoverCol
                  width: root.cellW
                  height: root.cellH
                  radius: Style.space(3)
                  color: c.tint === "work" ? Qt.alpha(Color.accent, hot ? 0.50 : 0.28)
                       : c.tint === "day" ? Qt.alpha(root.fg, hot ? 0.24 : 0.10)
                       : Qt.alpha(root.fg, hot ? 0.16 : 0.035)

                  Text {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 0.85
                    text: c.isMidnight ? c.dayLabel.replace(" ", "\n") : Model.hourLabel(c.hour, root.use12Hour)
                    color: c.isMidnight ? root.fg
                         : c.tint === "night" ? Qt.darker(root.fg, 1.6)
                         : root.fg
                    font.family: root.fontFam
                    font.pixelSize: c.isMidnight ? Style.font.caption - 2 : Style.font.caption
                    font.bold: c.isMidnight
                  }
                }
              }
            }
          }
        }
      }

      // ---- "Now" line across all rows.
      Rectangle {
        visible: root.ready
        x: root.headerW + root.headerGap + root.nowCol * (root.cellW + root.cellGap) - 1
        y: 0
        width: 2
        height: rowsCol.height
        radius: 1
        color: Color.accent
        opacity: 0.9
      }

      // ---- Hover-a-column conversion: every header time switches to that
      //      column's moment, answering "10am there is what here?" directly.
      MouseArea {
        x: root.headerW + root.headerGap
        y: 0
        width: root.stripW
        height: rowsCol.height
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
          root.hoverCol = Math.max(0, Math.min(23, Math.floor(mouse.x / (root.cellW + root.cellGap))))
        }
        onExited: root.hoverCol = -1
      }
    }
  }
}
