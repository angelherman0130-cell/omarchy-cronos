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

// Tags arrive as an array of strings or as a comma/space separated string in
// imports; always ends up as a sorted array of unique trimmed lowercase tags.
function normalizeTags(value) {
  var list = []
  if (Array.isArray(value)) list = value
  else if (value !== null && value !== undefined) list = String(value).split(/[,\s]+/)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var tag = String(list[i]).trim().toLowerCase()
    if (tag !== "" && out.indexOf(tag) === -1) out.push(tag)
  }
  return out.sort()
}

function normalizeTask(t) {
  if (!t || typeof t !== "object") return null
  var lead = t.leadHours !== null && t.leadHours !== undefined
    ? Number(t.leadHours)
    : (t.leadDays !== null && t.leadDays !== undefined ? Number(t.leadDays) * 24 : 0)
  var out = {
    id: String(t.id || ""),
    title: String(t.title || ""),
    notes: t.notes !== null && t.notes !== undefined ? String(t.notes) : "",
    tags: normalizeTags(t.tags),
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

function normalizeTagsPublic(value) { return normalizeTags(value) }

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

// Distinct tags present on the given tasks, sorted alphabetically.
function tagsOf(tasks) {
  var seen = []
  for (var i = 0; i < tasks.length; i++) {
    var tags = tasks[i].tags || []
    for (var j = 0; j < tags.length; j++) {
      if (seen.indexOf(tags[j]) === -1) seen.push(tags[j])
    }
  }
  return seen.sort()
}

// Sort an open-task list for the panel. Modes:
//   "due"     — soonest deadline first, no-deadline tasks last
//   "overdue" — overdue first (by deadline), then reminders due, then the rest
//   "title"   — alphabetical
//   "created" — most recently created first
// An empty tag keeps every task; otherwise only tasks carrying that tag.
function orderTasks(tasks, mode, tag) {
  function hasTag(t) {
    return !tag || (t.tags || []).indexOf(tag) !== -1
  }
  var filtered = tasks.filter(hasTag)
  if (mode === "title") {
    return filtered.slice().sort(function(a, b) {
      return String(a.title).localeCompare(String(b.title))
    })
  }
  if (mode === "created") {
    return filtered.slice().sort(function(a, b) {
      return (b.createdAt || 0) - (a.createdAt || 0)
    })
  }
  if (mode === "overdue") {
    return filtered.slice().sort(function(a, b) {
      var sa = rank(a), sb = rank(b)
      if (sa !== sb) return sa - sb
      return (dueMs(a) || Infinity) - (dueMs(b) || Infinity)
    })
  }
  return filtered.slice().sort(function(a, b) {
    return (dueMs(a) || Infinity) - (dueMs(b) || Infinity)
  })
  function rank(t) {
    if (t.done === true) return 4
    var due = dueMs(t)
    if (!isNaN(due) && due < Date.now()) return 0
    if (reminderDueNow(t, Date.now())) return 1
    if (!isNaN(due)) return 2
    return 3
  }
}

// Map of "YYYY-MM-DD" -> count of open tasks due on that day. Drives the
// "has tasks" mark in the panel's date-picker calendar.
function tasksAtDayMap(tasks) {
  var map = {}
  tasks.forEach(function(t) {
    if (t.done === true) return
    var d = datePart(t.due)
    if (!d) return
    map[d] = (map[d] || 0) + 1
  })
  return map
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

function makeTask(title, dueValue, leadHours, createdAt, notes, leadMode, tags) {
  return {
    id: newId(),
    title: String(title || "").trim(),
    notes: String(notes || "").trim(),
    tags: normalizeTags(tags),
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
// Monday-first six-row month grid. Returns weeks of day cells. Pass a map
// from tasksAtDayMap() to flag days that carry open tasks ("hasTasks").
function monthGrid(year, month, dayMap) {
  var first = new Date(year, month, 1)
  var leading = (first.getDay() - 1 + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = todayStamp()
  var map = dayMap || {}
  var weeks = []
  for (var w = 0; w < 6; w++) {
    var days = []
    for (var d = 0; d < 7; d++) {
      var key = localDateOf(cursor.getTime())
      days.push({
        key: key,
        day: cursor.getDate(),
        inMonth: cursor.getMonth() === month && cursor.getFullYear() === year,
        today: key === today,
        hasTasks: (map[key] || 0) > 0,
        taskCount: map[key] || 0
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

// ---- calendar interop (ICS / RFC 5545) -------------------------------

function icsEscape(s) {
  return String(s || "").replace(/\\/g, "\\\\").replace(/;/g, "\\;")
    .replace(/,/g, "\\,").replace(/\n/g, "\\n")
}

// Fold lines to <= 75 octets as RFC 5545 wants ("\r\n " continuation).
function icsFold(text) {
  return text.split(/\r?\n/).map(function(line) {
    var out = []
    while (line.length > 75) {
      out.push(line.slice(0, 75))
      line = " " + line.slice(75)
    }
    out.push(line)
    return out
  }).reduce(function(a, b) { return a.concat(b) }, []).join("\r\n")
}

function icsStamp(dateIso) {
  var m = dateIso.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$/)
  if (!m) return ""
  var base = m[1] + m[2] + m[3]
  return m[4] ? base + "T" + m[4] + m[5] + "00" : base
}

// Negative ISO-8601 duration from an advance in hours, e.g. -PT90M.
function icsTrigger(leadHours) {
  var totalMin = Math.round((Number(leadHours) || 0) * 60)
  if (totalMin <= 0) return ""
  var h = Math.floor(totalMin / 60)
  var m = totalMin % 60
  return "-PT" + h + "H" + m + "M"
}

function exportICS(tasks) {
  var lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//omarchy//Cronos//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH"
  ]
  tasks.forEach(function(t) {
    var stamp = icsStamp(t.due)
    if (!stamp) return
    lines.push("BEGIN:VEVENT", "UID:" + (t.id || newId()) + "@cronos")
    lines.push("DTSTAMP:" + icsStamp(localIso(Date.now()).replace(" ", "T")))
    if (stamp.indexOf("T") === -1) {
      lines.push("DTSTART;VALUE=DATE:" + stamp)
      lines.push("DTEND;VALUE=DATE:" + shiftDate(t.due, 1))
    } else {
      var endMs = dueMs(t)
      var plus = isNaN(endMs) ? Date.now() + 3600000 : endMs + 3600000
      lines.push("DTSTART:" + stamp)
      lines.push("DTEND:" + icsStamp(localIso(plus).replace(" ", "T")))
    }
    lines.push("SUMMARY:" + icsEscape(t.title))
    if (t.notes) lines.push("DESCRIPTION:" + icsEscape(t.notes))
    if (t.tags && t.tags.length) lines.push("CATEGORIES:" + t.tags.map(icsEscape).join(","))
    lines.push("STATUS:" + (t.done === true ? "CANCELLED" : "CONFIRMED"))
    var lead = Number(t.leadHours) || 0
    if (lead > 0) {
      var trig = icsTrigger(lead)
      if (trig) {
        lines.push(
          "BEGIN:VALARM",
          "ACTION:DISPLAY",
          "TRIGGER:" + trig,
          "DESCRIPTION:" + icsEscape(t.title),
          "END:VALARM"
        )
      }
    }
    lines.push("END:VEVENT")
  })
  lines.push("END:VCALENDAR")
  return icsFold(lines.join("\r\n"))
}

// Minimal VEVENT reader: date, title, notes, STATUS and the VALARM lead.
// Produces task-like objects (without ids) ready for importTasks().
function parseICS(text) {
  var out = []
  var blocks = String(text || "").split(/BEGIN:VEVENT/i).slice(1)
  for (var i = 0; i < blocks.length; i++) {
    var end = blocks[i].indexOf("END:VEVENT")
    var block = end >= 0 ? blocks[i].slice(0, end) : blocks[i]
    var raw = block.replace(/\r\n[ \t]/g, "").split(/\r?\n/)
    var props = {}
    for (var j = 0; j < raw.length; j++) {
      var line = raw[j]
      var ci = line.indexOf(":")
      if (ci < 0) continue
      var key = line.slice(0, ci).toUpperCase().split(";")[0]
      if (key === "BEGIN" || key === "END" || key === "ACTION") continue
      var val = line.slice(ci + 1)
      if (props[key] !== undefined) props[key] += "\n" + val
      else props[key] = val
    }
    var title = (props.SUMMARY || "").replace(/\\n/g, "\n").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\").trim()
    var dt = String(props.DTSTART || "").replace(/^[^:]*:/, "").split(";")[0]
    var m = dt.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2}))?/)
    if (!m || !title) continue
    var dueDate = m[1] + "-" + m[2] + "-" + m[3]
    var due = m[4] ? dueDate + "T" + m[4] + ":" + m[5] : dueDate
    var notes = (props.DESCRIPTION || "").replace(/\\n/g, "\n").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\").trim()
    var status = String(props.STATUS || "").toUpperCase()
    var categories = String(props.CATEGORIES || "").split(",")
      .map(function(s) { return s.replace(/\\,/g, ",").trim().toLowerCase() })
      .filter(function(s) { return s !== "" })
    var dur = String(props.TRIGGER || "").match(/^-?P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/)
    var leadHours = 0
    if (dur) leadHours = (+(dur[1] || 0)) * 24 + (+(dur[2] || 0)) + (+(dur[3] || 0)) / 60 + (+(dur[4] || 0)) / 3600
    out.push({
      title: title,
      notes: notes,
      tags: categories,
      due: due,
      done: status === "CANCELLED",
      leadHours: leadHours
    })
  }
  return out
}

// Import a round-tripped JSON dump: normalize, drop empties, and re-id so the
// incoming ids can never collide with tasks that already exist.
function importList(text) {
  return parse(text).map(function(t) {
    t.id = newId()
    return t
  })
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
    normalizeTags: normalizeTagsPublic,
    tagsOf: tagsOf,
    orderTasks: orderTasks,
    tasksAtDayMap: tasksAtDayMap,
    leadLabel: leadLabel,
    humanDue: humanDue,
    newId: newId,
    makeTask: makeTask,
    parseDue: parseDue,
    parseTime: parseTime,
    composeDue: composeDue,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    exportICS: exportICS,
    parseICS: parseICS,
    importList: importList,
    utf8Base64: utf8Base64
  }
}