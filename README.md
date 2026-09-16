# Cronos

Bar widget and service for Omarchy with tasks and deadline reminders.

> **Best with [Cronos Calendar](https://github.com/angelherman0130-cell/omarchy-calendar)**
> — the same tasks light up in a full month calendar (dots on busy days and a
> "CRONOS TASKS" agenda). Install both for the best experience:
>
> ```
> omarchy plugin add https://github.com/angelherman0130-cell/omarchy-cronos.git --enable
> omarchy plugin add https://github.com/angelherman0130-cell/omarchy-calendar.git --enable
> ```

![Cronos panel in the Omarchy bar](docs/screenshot.png?v=3)

![Cronos date picker](docs/screenshot-date.png?v=3)

![Cronos time picker](docs/screenshot-time.png?v=3)

![Cronos reminder settings](docs/screenshot-reminder.png?v=3)

A quick access in the bar lets you add a task (title, optional note, due date
and time) and choose when to be reminded:

- **Day mode**: reminds you on the due day itself (e.g. "1 day before"), five
  minutes after each login and every five hours until you acknowledge it.
- **Exact mode**: reminds you at the exact configured time ("At deadline",
  "1 h", "3 h", "6 h", "12 h"), plus the custom fields "Remind before the
  deadline" (min/h) or "Remind me in" (min/h).
- If the machine was off when a reminder was due, it is notified five minutes
  after the next login.
- A task due within the next hour (or already overdue) fires a **critical**
  notification, distinct from the normal ones.

It includes a completed-tasks section, loss-proof persistence (atomic writes
+ backup file) and automatic migration from the previous plugin version
(`angelherman.taskboard`).

## Editing and organizing

- **Edit** any pending task (✎) to change its title, note, deadline, reminder
  or tags — the form reopens pre-filled and "Add" becomes "Save".
- **Undo** a deleted task (it is kept in memory until you delete another one).
- **Tags** (comma separated) show as `#tag` and can be used as a filter.
- Sort the pending list: near first, overdue first, by name, or newest.
- Days that carry open tasks are **underlined with an accent dot in the date
  picker**, so you can spot a busy month at a glance.

## Import / Export

Buttons at the bottom of the panel exchange tasks with plain files in a
`~/CronosBaul/` folder (created automatically on first export) — nothing is
written into other apps or the shell clock:

| Action  | File                         | Notes                                        |
|---------|------------------------------|----------------------------------------------|
| Export  | `~/CronosBaul/Cronos-export.json` | Round-trip copy (tags, reminders, notes) |
| Export  | `~/CronosBaul/Cronos-export.ics`  | Standard calendar file, openable in GNOME |
|         |                              | Calendar/Evolution/Google (double-click)     |
| Import  | `~/CronosBaul/Cronos-import.json` | Merges new tasks (duplicates skipped)    |
| Import  | `~/CronosBaul/Cronos-import.ics`  | Merges VEVENTs (date, title, notes, reminder) |

Import is on demand (no auto-load at boot); duplicates are kept out by title
+ due date. ICS files use RFC 5545 with a `VALARM` reminder and `CATEGORIES`
tags.

## Companion calendar

[Cronos Calendar](https://github.com/angelherman0130-cell/omarchy-calendar) is a
bar clock (date and time) that replaces `omarchy.clock` and shows your Cronos
tasks on their due days: accent dots in the month grid and the next tasks in a
"CRONOS TASKS" agenda. Install it together for the full experience:

```
omarchy plugin add https://github.com/angelherman0130-cell/omarchy-cronos.git --enable
omarchy plugin add https://github.com/angelherman0130-cell/omarchy-calendar.git --enable
```

## Installation

From the marketplace:

```
omarchy plugin install angelherman.cronos --enable
```

Or from the repository:

```
omarchy plugin add https://github.com/angelherman0130-cell/omarchy-cronos.git --enable
```

## Usage

1. Click the Cronos icon in the bar (or the urgent-task counter).
2. Type a title, an optional note, the due date/time and the reminder.
3. Press **＋ Add**.

Overdue, unacknowledged tasks are highlighted with the urgent color in the
bar. Completing a task moves it to "Completed"; the ✕ removes it and **← Undo**
restores the last removal; ✎ reopens the task in the form for editing.

State is stored in `~/.local/state/omarchy/cronos/tasks.json`
(plus `tasks.json.bak`).

## Development

```
omarchy plugin validate ~/.config/omarchy/plugins/angelherman.cronos
qmllint -I "$OMARCHY_PATH/shell" Panel.qml BarWidget.qml Service.qml TaskRow.qml
```

## License

[MIT](LICENSE) © Angel Herman