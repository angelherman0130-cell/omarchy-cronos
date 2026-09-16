// Taskboard data helpers: datetime math, persistence shape, reminder rules,
// and the month grid for the date picker. Pure JS so the same logic serves
// the service, the bar widget, and the panel.
//
// Dates live as naive local values with two shapes:
//   - "YYYY-MM-DD"        — a day (due without a time = end of that day)
//   - "YYYY-MM-DDTHH:MM"  — a day and a time
// Reminders are scheduled as due − leadHours, in absolute local time, and
// fire on the minute; a missed reminder is picked up at the next session.

function pad(n) {
  return n < 10 ? "0" + n : "" + n
}

// ---- calendar stamps ------------------------------------------------

function todayStamp() {
  var d = new Date()
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function localDateOf(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function localTimeOf(ms) {
  var d = new Date(ms)
  return pad(d.getHours()) + ":" + pad(d.getMinutes())
}

function shiftDate(iso, days) {
  var d = String(iso || "")
  var m = d.match(/^(\d{4})-(\d{2})-(\d{2})$/)
  if (!m) return ""
  var t = new Date(+m[1], +m[2] - 1, +m[3]).getTime()
  if (isNaN(t)) return ""
  var shifted = new Date(t + days * 86400000)
  return shifted.getFullYear() + "-" + pad(shifted.getMonth() + 1) + "-" + pad(shifted.getDate())
}

function daysBetween(fromDateIso, toDateIso) {
  return Math.round((dateMs(toDateIso) - dateMs(fromDateIso)) / 86400000)
}

// Epoch ms of a calendar day (00:00, tz-consistent with the stamps above).
function dateMs(dateIso) {
  var m = String(dateIso || "").match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return NaN
  return new Date(+m[1], +m[2] - 1, +m[3]).getTime()
}

// ---- full datetimes ------------------------------------------------

// Parse "YYYY-MM-DD", "YYYY-MM-DDTHH:MM[:SS]", "YYYY-MM-DD HH:MM", or an
// epoch number. A bare date means end of that day (23:59:59); a bare time
// is rejected.
function parseDateTime(value) {
  var v = String(value || "").trim()
  if (v === "") return NaN
  if (/^\d+(\.\d+)?$/.test(v)) {
    var n = Number(v)
    return isFinite(n) ? n : NaN
  }
  var m = v.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?$/)
  if (!m) return NaN
  var y = +m[1], mo = +m[2], d = +m[3]
  var check = new Date(y, mo - 1, d)
  if (check.getFullYear() !== y || check.getMonth() !== mo - 1 || check.getDate() !== d)
    return NaN
  if (m[4]) {
    var hh = +m[4], mm = +m[5], ss = m[6] ? +m[6] : 0
    if (hh > 23 || mm > 59 || ss > 59) return NaN
    return new Date(y, mo - 1, d, hh, mm, ss).getTime()
  }
  return new Date(y, mo - 1, d, 23, 59, 59).getTime()
}

function datePart(value) {
  var m = String(value || "").match(/^(\d{4}-\d{2}-\d{2})/)
  return m ? m[1] : ""
}

function timePart(value) {
  var m = String(value || "").match(/(\d{2}:\d{2})/)
  return m ? m[1] : ""
}

function localIso(ms) {
  return localDateOf(ms) + " " + localTimeOf(ms) + ":" + pad(new Date(ms).getSeconds())
}

function dueMs(task) {
  return parseDateTime(task.due)
}

function reminderMs(task) {
  var due = dueMs(task)
  if (isNaN(due)) return NaN
  return due - (Number(task.leadHours) || 0) * 3600000
}

function firedMs(task) {
  if (task.firedAt === null || task.firedAt === undefined || task.firedAt === "")
    return NaN
  var v = parseDateTime(task.firedAt)
  return isNaN(v) ? NaN : v
}

// ---- reminder rules ------------------------------------------------

// Day-based reminders ("1 day", "5 days", "1 week", ...) ignore the clock and
// fire on the reminder DAY — the due date shifted back by the whole lead days:
//   - 5 minutes after each system start that day,
//   - and at each 5-hour slot of the day (00:00, 05:00, 10:00, 15:00, 20:00)
//     while the machine is on.
// Firing is de-duplicated with firedAt holding the LATEST fire of the day.
var DAY_SLOT_HOURS = [0, 5, 10, 15, 20]

function isDayMode(task) {
  return task.leadMode === "day"
}

function reminderDayStartMs(task) {
  var due = dueMs(task)
  if (isNaN(due)) return NaN
  var days = Math.round((Number(task.leadHours) || 0) / 24)
  var d = new Date(due - days * 24 * 3600000)
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

function dayReminderPending(task, nowMs, bootMs, graceMs) {
  var start = reminderDayStartMs(task)
  if (isNaN(start)) return false
  var end = start + 24 * 3600000 - 1
  if (nowMs > end) return false
  var last = firedMs(task)
  if (isNaN(last)) last = -Infinity
  var gate = last
  var bt = isNaN(bootMs) ? NaN : (bootMs || 0) + (graceMs || 0)
  if (!isNaN(bt) && bt >= start && bt <= end && bt > last) {
    // A boot on the reminder day owns the moment: don't replay old slots
    // from before it; fire 5 minutes after boot, then back to the slots.
    if (bt <= nowMs) return true
    gate = Math.max(gate, bt)
  }
  for (var i = 0; i < DAY_SLOT_HOURS.length; i++) {
    var s = start + DAY_SLOT_HOURS[i] * 3600000
    if (!(s > gate)) continue
    if (s <= nowMs) return true
    break
  }
  return false
}

// Pending when the reminder moment has arrived and the task has not been
// reported on or after that moment. The caller passes the session's grace
// (null/NaN disables it) so late logins catch missed reminders shortly after
// boot rather than at 00:00 — but an on-time reminder fires at its exact
// minute regardless.
function isReminderPending(task, nowMs, bootMs, graceMs) {
  if (task.done === true) return false
  if (isDayMode(task)) return dayReminderPending(task, nowMs, bootMs, graceMs)
  var rms = reminderMs(task)
  if (isNaN(rms)) return false
  var fms = firedMs(task)
  if (!isNaN(fms) && fms >= rms) return false
  var target = rms
  if (!isNaN(bootMs)) target = Math.max(target, (bootMs || 0) + (graceMs || 0))
  return nowMs >= target
}

// Waiting-for-the-minute view: reminder moment arrived, not yet fired,
// ignoring the boot grace. Drives the "remind now" tag in the panel.
function reminderDueNow(task, nowMs) {
  if (task.done === true) return false
  if (isDayMode(task)) return dayReminderPending(task, nowMs, NaN, 0)
  var rms = reminderMs(task)
  if (isNaN(rms)) return false
  var fms = firedMs(task)
  return (isNaN(fms) || fms < rms) && nowMs >= rms
}

function needsAttention(tasks, nowMs) {
  return tasks.some(function(task) {
    if (task.done === true) return false
    if (reminderDueNow(task, nowMs)) return true
    var due = dueMs(task)
    return !isNaN(due) && nowMs > due
  })
}

// ---- persistence ---------------------------------------------------

function normalizeTask(t) {
  if (!t || typeof t !== "object") return null
  var lead = t.leadHours !== null && t.leadHours !== undefined
    ? Number(t.leadHours)
    : (t.leadDays !== null && t.leadDays !== undefined ? Number(t.leadDays) * 24 : 0)
  var out = {
    id: String(t.id || ""),
    title: String(t.title || ""),
    notes: t.notes !== null && t.notes !== undefined ? String(t.notes) : "",
    due: String(t.due || ""),
    leadHours: isFinite(lead) ? Math.max(0, Math.min(8760, lead)) : 0,
    // "day" = whole-days presets/legacy (reminds on the day, ignoring time);
    // "exact" = minutes/hours (reminds at the precise configured moment).
    leadMode: t.leadMode === "day"
      ? "day"
      : (isFinite(lead) && lead > 0 && Math.abs(lead) % 24 === 0 ? "day" : "exact"),
    // Legacy files kept the fired day in remindedDate; treat it as fired at
    // the end of that day so they don't re-fire.
    firedAt: t.firedAt !== null && t.firedAt !== undefined
      ? t.firedAt
      : (t.remindedDate ? t.remindedDate + "T23:59" : null),
    done: t.done === true,
    createdAt: t.createdAt || 0
  }
  if (out.firedAt === null) out.firedAt = null
  return out
}

function parse(text) {
  try {
    var v = JSON.parse(text)
    if (Array.isArray(v)) return v.map(normalizeTask).filter(function(t) { return t !== null })
  } catch (e) {}
  return []
}

function serialize(tasks) {
  return JSON.stringify(tasks, null, 2)
}

// ---- queries -------------------------------------------------------

function sortByDue(tasks) {
  return tasks.slice().sort(function(a, b) {
    return dueMs(a) - dueMs(b)
  })
}

function openTasks(tasks) {
  return tasks.filter(function(t) { return t.done !== true })
}

function closedTasks(tasks) {
  return tasks.filter(function(t) { return t.done === true })
}

// ---- labels --------------------------------------------------------

function leadLabel(hours) {
  var h = Math.max(0, Number(hours) || 0)
  if (h <= 0.001) return "at the deadline"
  var totalMin = Math.round(h * 60)
  if (totalMin < 60) return totalMin + " min"
  if (totalMin % (24 * 60) === 0) {
    var d = totalMin / (24 * 60)
    return d === 1 ? "1 day" : d + " days"
  }
  var hh = Math.floor(totalMin / 60)
  var mm = totalMin % 60
  if (mm === 0) return hh === 1 ? "1 h" : hh + " h"
  return hh + " h " + mm + " min"
}

function humanDue(dueValue, nowMs) {
  var due = parseDateTime(dueValue)
  if (isNaN(due)) return ""
  var n = daysBetween(localDateOf(nowMs), localDateOf(due))
  var base
  if (n === 0) base = "today"
  else if (n === 1) base = "tomorrow"
  else if (n === -1) base = "yesterday"
  else if (n < 0) base = (-n) + "d ago"
  else base = "in " + n + "d"
  var t = timePart(dueValue)
  return t ? base + " " + t : base
}

// ---- mutations -----------------------------------------------------

function newId() {
  return Date.now().toString(36) + Math.floor(Math.random() * 1e9).toString(36)
}

function makeTask(title, dueValue, leadHours, createdAt, notes, leadMode) {
  return {
    id: newId(),
    title: String(title || "").trim(),
    notes: String(notes || "").trim(),
    due: String(dueValue || ""),
    leadHours: Math.max(0, Math.min(8760, parseFloat(leadHours) || 0)),
    leadMode: leadMode === "day" ? "day" : "exact",
    firedAt: null,
    done: false,
    createdAt: createdAt || Date.now()
  }
}

// Accepts "2026-09-30", "today"/"hoy", "tomorrow"/"mañana"/"+1", or "+N".
// Returns a bare date stamp or "" when the input cannot be read.
function parseDue(input, today) {
  var v = String(input || "").trim().toLowerCase()
  if (v === "") return ""
  if (v === "today" || v === "hoy") return today
  if (v === "tomorrow" || v === "manana" || v === "mañana" || v === "+1")
    return shiftDate(today, 1)
  if (/^\d{4}-\d{2}-\d{2}$/.test(v) && !isNaN(dateMs(v))) return v
  var rel = v.match(/^\+(\d+)$/)
  if (rel) return shiftDate(today, +rel[1])
  return ""
}

function parseTime(input) {
  var v = String(input || "").trim()
  var m = v.match(/^(\d{2}):(\d{2})$/)
  if (m && +m[1] <= 23 && +m[2] <= 59) return m[1] + ":" + m[2]
  return ""
}

function composeDue(dateIso, time) {
  var t = parseTime(time)
  return t ? dateIso + "T" + t : dateIso
}

// ---- date-picker grid -------------------------------------------------
//
// Monday-first six-row month grid. Returns weeks of day cells.
function monthGrid(year, month) {
  var first = new Date(year, month, 1)
  var leading = (first.getDay() - 1 + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = todayStamp()
  var weeks = []
  for (var w = 0; w < 6; w++) {
    var days = []
    for (var d = 0; d < 7; d++) {
      var key = localDateOf(cursor.getTime())
      days.push({
        key: key,
        day: cursor.getDate(),
        inMonth: cursor.getMonth() === month && cursor.getFullYear() === year,
        today: key === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    weeks.push(days)
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ---- encoding ------------------------------------------------------

// UTF-8 aware base64 (Qt.btoa works on Latin-1 byte strings, so non-ASCII
// titles must be encoded to bytes first).
function utf8Bytes(str) {
  var out = []
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i)
    if (c < 0x80) {
      out.push(c)
    } else if (c < 0x800) {
      out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F))
    } else if (c < 0xD800 || c >= 0xE000) {
      out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F))
    } else {
      var c2 = str.charCodeAt(++i)
      var cp = 0x10000 + (((c & 0x3FF) << 10) | (c2 & 0x3FF))
      out.push(
        0xF0 | (cp >> 18),
        0x80 | ((cp >> 12) & 0x3F),
        0x80 | ((cp >> 6) & 0x3F),
        0x80 | (cp & 0x3F)
      )
    }
  }
  return String.fromCharCode.apply(null, out)
}

function utf8Base64(text) {
  var raw = utf8Bytes(text)
  if (typeof Qt !== "undefined" && Qt.btoa) return Qt.btoa(raw)
  return raw
}

if (typeof module !== "undefined") {
  module.exports = {
    todayStamp: todayStamp,
    localDateOf: localDateOf,
    localTimeOf: localTimeOf,
    shiftDate: shiftDate,
    daysBetween: daysBetween,
    dateMs: dateMs,
    parseDateTime: parseDateTime,
    datePart: datePart,
    timePart: timePart,
    localIso: localIso,
    dueMs: dueMs,
    reminderMs: reminderMs,
    firedMs: firedMs,
    isReminderPending: isReminderPending,
    reminderDueNow: reminderDueNow,
    needsAttention: needsAttention,
    parse: parse,
    serialize: serialize,
    sortByDue: sortByDue,
    openTasks: openTasks,
    closedTasks: closedTasks,
    leadLabel: leadLabel,
    humanDue: humanDue,
    newId: newId,
    makeTask: makeTask,
    parseDue: parseDue,
    parseTime: parseTime,
    composeDue: composeDue,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    utf8Base64: utf8Base64
  }
}