// Pure timezone/formatting logic for the timezones widget. All math works on
// UTC-offset minutes fetched from tzdata via `date`; no Date-local calls, so
// the same instant renders consistently for every configured zone.

// "+0200" / "-0930" → signed minutes east of UTC.
function parseUtcOffset(text) {
  var m = /^([+-])(\d{2}):?(\d{2})$/.exec(String(text || "").trim())
  if (!m) return null
  var minutes = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
  return m[1] === "-" ? -minutes : minutes
}

// Output of the offsets probe: one "<key> <±HHMM> <ABBR>" line per zone.
function parseOffsetLines(text) {
  var result = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length < 2) continue
    var offset = parseUtcOffset(parts[1])
    if (offset === null) continue
    result[parts[0]] = { offsetMin: offset, abbr: parts.length > 2 ? parts[2] : "" }
  }
  return result
}

// UTC ms of the home zone's most recent local midnight — column 0 of the grid.
function homeDayStartUtc(nowUtcMs, homeOffsetMin) {
  var dayMs = 24 * 3600000
  var localMs = nowUtcMs + homeOffsetMin * 60000
  return localMs - (((localMs % dayMs) + dayMs) % dayMs) - homeOffsetMin * 60000
}

// Local wall-clock fields of a UTC instant in a fixed-offset zone.
function localFields(utcMs, offsetMin) {
  var d = new Date(utcMs + offsetMin * 60000)
  return {
    hour: d.getUTCHours(),
    day: d.getUTCDate(),
    weekday: d.getUTCDay(),
    month: d.getUTCMonth(),
    minute: d.getUTCMinutes()
  }
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// One grid cell: the zone-local hour and minute at home-day column `col`.
function cell(col, dayStartUtcMs, offsetMin) {
  var f = localFields(dayStartUtcMs + col * 3600000, offsetMin)
  return {
    hour: f.hour,
    minute: f.minute,
    isMidnight: f.hour === 0,
    dayLabel: WEEKDAYS[f.weekday] + " " + f.day,
    tint: tintFor(f.hour)
  }
}

// Visual band for a cell: business hours pop, waking hours mid, night dark.
function tintFor(hour) {
  if (hour >= 8 && hour < 18) return "work"
  if (hour >= 6 && hour < 23) return "day"
  return "night"
}

// Configurable strings (icon, labels, abbreviations) are rendered by Text
// elements whose default AutoText format detects rich text — strip the
// characters that could smuggle markup (e.g. <img src=...>) into the
// long-lived shell process.
function plainText(value) {
  return String(value === null || value === undefined ? "" : value).replace(/[<>&]/g, "")
}

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// 0 → 12, 13 → 1: the hour as a 12-hour clock reads it.
function hour12(hour) {
  var h = hour % 12
  return h === 0 ? 12 : h
}

// "07:12" for a zone right now, or "7:12 AM" in 12-hour mode.
function timeLabel(nowUtcMs, offsetMin, use12Hour) {
  var f = localFields(nowUtcMs, offsetMin)
  if (!use12Hour) return pad2(f.hour) + ":" + pad2(f.minute)
  return hour12(f.hour) + ":" + pad2(f.minute) + (f.hour < 12 ? " AM" : " PM")
}

// One grid cell's hour. The 12-hour form stays as short as worldtimebuddy's
// ("1p", "11a") because a cell is only wide enough for three characters.
function hourLabel(hour, use12Hour) {
  if (!use12Hour) return String(hour)
  return hour12(hour) + (hour < 12 ? "a" : "p")
}

// Minutes under the hour for a zone offset by :30/:45; "" on the hour.
function minuteLabel(minute) {
  return minute === 0 ? "" : pad2(minute)
}

// Display modes, in the order the `t` key cycles them: 24-hour, AM/PM, and
// 24-hour with a UTC reference row pinned under home.
var HOUR_FORMATS = ["24h", "12h", "utc"]

function normalizeHourFormat(value) {
  var s = String(value === null || value === undefined ? "" : value).trim().toLowerCase()
  return HOUR_FORMATS.indexOf(s) === -1 ? "24h" : s
}

function nextHourFormat(mode) {
  var i = HOUR_FORMATS.indexOf(normalizeHourFormat(mode))
  return HOUR_FORMATS[(i + 1) % HOUR_FORMATS.length]
}

// The reference row "utc" mode adds. Offset 0 needs no probing.
function utcZone() {
  return { label: "UTC", shortLabel: "UTC", abbr: "", home: false, utc: true, offsetMin: 0 }
}

// Zone rows with the UTC reference inserted right after the home row (or
// first, when no row is home) — the anchor and its reference read together.
function withUtcRow(zones) {
  var out = zones.slice()
  var at = 0
  for (var i = 0; i < out.length; i++) if (out[i].home) { at = i + 1; break }
  out.splice(at, 0, utcZone())
  return out
}

// "Thu 21 Aug" style date for the row header.
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
function dateLabel(nowUtcMs, offsetMin) {
  var f = localFields(nowUtcMs, offsetMin)
  return WEEKDAYS[f.weekday] + " " + f.day + " " + MONTHS[f.month]
}

// Offset relative to home: "+6h", "−9h", "+5:30", "" for home itself.
function diffLabel(offsetMin, homeOffsetMin) {
  var diff = offsetMin - homeOffsetMin
  if (diff === 0) return ""
  var sign = diff < 0 ? "−" : "+"
  var abs = Math.abs(diff)
  var h = Math.floor(abs / 60)
  var m = abs % 60
  return sign + (m === 0 ? h + "h" : h + ":" + pad2(m))
}

// Fractional column position of "now" for the vertical indicator, in [0, 24).
function nowColumn(nowUtcMs, dayStartUtcMs) {
  return (nowUtcMs - dayStartUtcMs) / 3600000
}

// Compact bar label shown on hover: "NY 07:12 · SF 04:12 · CDO 19:12".
function compactLabel(zones, nowUtcMs, use12Hour) {
  var parts = []
  for (var i = 0; i < zones.length; i++) {
    var z = zones[i]
    if (z.home || z.offsetMin === undefined || z.offsetMin === null) continue
    parts.push(plainText(z.shortLabel) + " " + timeLabel(nowUtcMs, z.offsetMin, use12Hour))
  }
  return parts.join(" · ")
}

// Fallback when the widget entry in shell.json carries no "zones" array —
// the real configuration belongs there. The home row (zone: "") tracks the
// system timezone, so travel updates it.
function defaultZones() {
  return [
    { label: "Home", shortLabel: "HOME", zone: "", home: true },
    { label: "East Coast", shortLabel: "NY", zone: "America/New_York" },
    { label: "West Coast", shortLabel: "SF", zone: "America/Los_Angeles" }
  ]
}

if (typeof module !== "undefined") {
  module.exports = {
    parseUtcOffset: parseUtcOffset,
    parseOffsetLines: parseOffsetLines,
    homeDayStartUtc: homeDayStartUtc,
    localFields: localFields,
    cell: cell,
    tintFor: tintFor,
    hour12: hour12,
    timeLabel: timeLabel,
    hourLabel: hourLabel,
    minuteLabel: minuteLabel,
    normalizeHourFormat: normalizeHourFormat,
    nextHourFormat: nextHourFormat,
    utcZone: utcZone,
    withUtcRow: withUtcRow,
    dateLabel: dateLabel,
    diffLabel: diffLabel,
    nowColumn: nowColumn,
    compactLabel: compactLabel,
    plainText: plainText,
    defaultZones: defaultZones
  }
}
