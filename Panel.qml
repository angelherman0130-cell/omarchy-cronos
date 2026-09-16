import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "TaskModel.js" as Model

// Cronos panel: add a task (title + due date via inline calendar or text +
// optional time + reminder lead in hours), see the upcoming list, toggle done,
// delete. All state lives in the service.
Panel {
  id: root
  moduleName: "angelherman.cronos"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("angelherman.cronos")
    : null

  readonly property color fg: Color.popups.text
  readonly property color muted: Qt.darker(fg, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent

  readonly property string today: service ? service.today : Model.todayStamp()
  readonly property int defaultLeadHours: parseInt(setting("defaultLeadHours", 24), 10) || 24
  readonly property real nowMs: service ? service.nowMs : Date.now()
  readonly property var openTasks: service
    ? Model.orderTasks(Model.openTasks(service.tasks), root.sortMode, root.tagFilter)
    : []
  readonly property var doneTasks: service ? service.sortedDoneTasks : []

  readonly property var sortOptions: [
    { value: "due",     label: "Near first"     },
    { value: "overdue", label: "Overdue first"  },
    { value: "title",   label: "Name"           },
    { value: "created", label: "Newest"         }
  ]

  readonly property var tagOptions: {
    var tags = service ? Model.tagsOf(Model.openTasks(service.tasks)) : []
    var opts = [{ value: "", label: "All tags" }]
    for (var i = 0; i < tags.length; i++) opts.push({ value: tags[i], label: tags[i] })
    return opts
  }

  readonly property var dayMap: service
    ? Model.tasksAtDayMap(Model.openTasks(service.tasks))
    : {}

  readonly property string summary: {
    var parts = root.dueInput
      ? ["Due " + Model.humanDue(root.dueInput, root.nowMs)]
      : ["No deadline"]
    if (root.dueTime) parts[0] += " · " + root.dueTime
    var lead = Number(root.leadValue) || 0
    parts.push("reminder " + Model.leadLabel(lead))
    return parts.join(" · ")
  }

  property string titleText: ""
  property string notesText: ""
  property string tagsText: ""
  property string dueInput: ""
  property string dueTime: ""
  property string leadValue: String(defaultLeadHours)
  property string leadMode: "day"
  property string customLeadValue: ""
  property string customLeadUnit: "h"
  property string remindInValue: ""
  property string remindInUnit: "min"
  property string formNotice: ""
  property string activeCard: ""
  property bool editingTask: false
  property string editingId: ""
  property string sortMode: "due"
  property string tagFilter: ""
  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()

  readonly property var timePresets: [
    "07:00", "09:00", "12:00", "15:00", "18:00", "21:00", "23:59"
  ]

  readonly property var leadPresets: [
    { value: "0",   label: "At deadline", mode: "exact" },
    { value: "1",   label: "1 h",         mode: "exact" },
    { value: "3",   label: "3 h",         mode: "exact" },
    { value: "6",   label: "6 h",         mode: "exact" },
    { value: "12",  label: "12 h",        mode: "exact" },
    { value: "24",  label: "1 day",       mode: "day" },
    { value: "48",  label: "2 days",      mode: "day" },
    { value: "72",  label: "3 days",      mode: "day" },
    { value: "120", label: "5 days",      mode: "day" },
    { value: "168", label: "1 week",      mode: "day" },
    { value: "336", label: "2 weeks",     mode: "day" }
  ]

  readonly property var unitOptions: [
    { value: "min", label: "min" },
    { value: "h",   label: "hours" }
  ]

  readonly property var viewWeeks: Model.monthGrid(root.viewYear, root.viewMonth, root.dayMap)

  // Resolves whatever the user typed (e.g. "today", "+3", an ISO date) so the
  // calendar can highlight it; "" means "not on a real date yet".
  readonly property string selection: Model.parseDue(root.dueInput, root.today)

  function refresh() {}

  function resetCalendarView() {
    if (root.selection) {
      var parts = root.selection.split("-")
      root.viewYear = +parts[0]
      root.viewMonth = +parts[1] - 1
    } else {
      var d = new Date()
      root.viewYear = d.getFullYear()
      root.viewMonth = d.getMonth()
    }
  }

  function toggleCard(name) {
    if (root.activeCard === name) {
      root.activeCard = ""
    } else {
      if (name === "date") root.resetCalendarView()
      root.activeCard = name
    }
    root.formNotice = ""
  }

  function pickDate(key) {
    root.dueInput = key
    root.activeCard = ""
  }

  function applyCustomLead() {
    var n = Number(root.customLeadValue)
    if (!isFinite(n) || n <= 0) {
      root.formNotice = "Enter a number greater than 0 in the custom reminder"
      return
    }
    root.leadValue = String(root.customLeadUnit === "min" ? n / 60 : n)
    root.leadMode = "exact"
  }

  function applyRemindIn() {
    var n = Number(root.remindInValue)
    if (!isFinite(n) || n <= 0) {
      root.formNotice = "Enter a number greater than 0 in 'Remind me in'"
      return
    }
    var unitMs = root.remindInUnit === "min" ? 60000 : 3600000
    var when = new Date(Date.now() + n * unitMs)
    function pad(v) { return (v < 10 ? "0" : "") + v }
    root.dueInput = when.getFullYear() + "-" + pad(when.getMonth() + 1) + "-" + pad(when.getDate())
    root.dueTime = pad(when.getHours()) + ":" + pad(when.getMinutes())
    root.leadValue = "0"
    root.leadMode = "exact"
    root.activeCard = ""
    root.formNotice = "Will be added with a reminder in " + n + (root.remindInUnit === "min" ? " min" : " h") + " (due today " + root.dueTime + ")"
  }

  function resetForm() {
    root.titleText = ""
    root.notesText = ""
    root.tagsText = ""
    root.dueInput = ""
    root.dueTime = ""
    root.customLeadValue = ""
    root.remindInValue = ""
    root.formNotice = ""
    root.activeCard = ""
    root.editingTask = false
    root.editingId = ""
    root.resetCalendarView()
  }

  // Reopens the panel with an existing task's fields loaded; "Add" becomes
  // "Save" and saves back into the same task.
  function startEdit(task) {
    root.editingId = task.id
    root.editingTask = true
    root.titleText = task.title
    root.notesText = task.notes || ""
    root.tagsText = (task.tags || []).join(", ")
    root.dueInput = Model.datePart(task.due)
    root.dueTime = Model.timePart(task.due)
    root.leadValue = String(task.leadHours || 0)
    root.leadMode = task.leadMode === "day" ? "day" : "exact"
    root.customLeadValue = ""
    root.remindInValue = ""
    root.formNotice = ""
    root.activeCard = ""
    root.resetCalendarView()
    root.open()
    Qt.callLater(function() {
      titleField.forceActiveFocus()
      titleField.selectAll()
    })
  }

  function submit() {
    if (!root.service) return
    var ok = root.editingTask
      ? root.service.editTask(root.editingId, root.titleText, root.dueInput, root.dueTime, root.leadValue, root.notesText, root.leadMode, root.tagsText)
      : root.service.add(root.titleText, root.dueInput, root.dueTime, root.leadValue, root.notesText, root.leadMode, root.tagsText)
    if (ok) {
      root.resetForm()
      titleField.forceActiveFocus()
    } else {
      root.formNotice = "Check the title and pick a date"
    }
  }

  KeyboardPanel {
    id: card
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: card.fittedContentWidth(Style.space(380))
    contentHeight: card.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: titleField.activeFocus || timeField.activeFocus
        || customField.activeFocus || remindInField.activeFocus
        || tagsField.activeFocus
        || unitField.popupOpen || remindUnit.popupOpen
      onCloseRequested: root.close()
    }

    Item {
      id: content
      implicitWidth: parent.width
      implicitHeight: layout.implicitHeight

      ColumnLayout {
        id: layout
        width: parent.width
        spacing: Style.spacing.controlGap

        Text {
          textFormat: Text.PlainText
          text: root.editingTask ? "Edit task" : "Cronos"
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: root.summary
          color: root.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        TextField {
          id: titleField
          Layout.fillWidth: true
          placeholderText: "Task title"
          text: root.titleText
          onTextChanged: root.titleText = text
          onAccepted: root.submit()
        }

        TextField {
          id: notesField
          Layout.fillWidth: true
          placeholderText: "Description or notes (optional)"
          text: root.notesText
          onTextChanged: root.notesText = text
        }

        TextField {
          id: tagsField
          Layout.fillWidth: true
          placeholderText: "Tags (comma separated, optional)"
          text: root.tagsText
          onTextChanged: root.tagsText = text
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          Button {
            id: dateButton
            Layout.fillWidth: true
            text: "Date"
            foreground: root.fg
            accent: root.accent
            active: root.activeCard === "date"
            focusable: true
            tooltipText: "Choose the due date"
            onClicked: root.toggleCard("date")
          }

          Button {
            id: timeButton
            Layout.fillWidth: true
            text: "Time"
            foreground: root.fg
            accent: root.accent
            active: root.activeCard === "time"
            focusable: true
            tooltipText: "Pick the deadline time"
            onClicked: root.toggleCard("time")
          }

          Button {
            id: leadButton
            Layout.fillWidth: true
            text: "Reminder"
            foreground: root.fg
            accent: root.accent
            active: root.activeCard === "lead"
            focusable: true
            tooltipText: "How far in advance to remind you"
            onClicked: root.toggleCard("lead")
          }
        }

        Rectangle {
          id: calendarCard
          visible: root.activeCard === "date"
          Layout.fillWidth: true
          Layout.preferredHeight: cardLayout.implicitHeight + Style.spacing.panelPadding * 2
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: Qt.alpha(root.accent, 0.4)
          border.width: 1

          ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            spacing: Style.spacing.controlGap

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap

              PanelActionButton {
                iconText: "‹"
                foreground: root.accent
                tooltipText: "Previous month"
                onClicked: {
                  var m = Model.stepMonth(root.viewYear, root.viewMonth, -1)
                  root.viewYear = m.year
                  root.viewMonth = m.month
                }
              }

              Button {
                Layout.fillWidth: true
                text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                foreground: root.fg
                accent: root.accent
                onClicked: root.resetCalendarView()
                tooltipText: "Back to current month"
              }

              PanelActionButton {
                iconText: "›"
                foreground: root.accent
                tooltipText: "Next month"
                onClicked: {
                  var m = Model.stepMonth(root.viewYear, root.viewMonth, 1)
                  root.viewYear = m.year
                  root.viewMonth = m.month
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 2

              Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                Text {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(18)
                  text: modelData
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                  color: root.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2

              Repeater {
                model: root.viewWeeks

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  Repeater {
                    model: modelData

                    delegate: Item {
                      id: cell
                      required property var modelData
                      Layout.fillWidth: true
                      Layout.preferredHeight: Style.space(34)

                      readonly property bool selected: root.selection === modelData.key
                      readonly property bool hovered: hoverArea.containsMouse

                      Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: cell.selected ? Style.selectedAccentFill
                          : (modelData.inMonth && cell.hovered ? Style.hoverFill : "transparent")
                        border.width: cell.selected ? 1 : (modelData.today ? 1 : 0)
                        border.color: cell.selected ? Style.selectedBorderColor
                          : Qt.alpha(root.accent, 0.55)

                        Text {
                          text: modelData.day
                          textFormat: Text.PlainText
                          anchors.centerIn: parent
                          color: !modelData.inMonth ? Qt.alpha(root.muted, 0.45)
                            : (cell.selected ? root.accent : root.fg)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.bold: modelData.today
                          // Days with open tasks get an accent underline.
                          style: (modelData !== undefined && modelData.hasTasks && !cell.selected)
                            ? Text.Underline : Text.Normal
                          styleColor: root.accent
                        }

                        Rectangle {
                          width: 4
                          height: 4
                          radius: 2
                          color: root.accent
                          anchors.horizontalCenter: parent.horizontalCenter
                          anchors.bottom: parent.bottom
                          anchors.bottomMargin: 2
                          visible: modelData.hasTasks
                        }
                      }

                      MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (modelData.inMonth) root.pickDate(modelData.key)
                        }
                      }
                    }
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap

              Text {
                textFormat: Text.PlainText
                text: "Select a day of the month"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
              }

              Button {
                text: "Today"
                foreground: root.fg
                accent: root.accent
                onClicked: root.pickDate(Model.todayStamp())
                tooltipText: "Pick today"
              }
            }
          }
        }

        Rectangle {
          id: timeCard
          visible: root.activeCard === "time"
          Layout.fillWidth: true
          Layout.preferredHeight: timeLayout.implicitHeight + Style.spacing.panelPadding * 2
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: Qt.alpha(root.accent, 0.4)
          border.width: 1

          ColumnLayout {
            id: timeLayout
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            spacing: Style.spacing.controlGap

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap

              TextField {
                id: timeField
                Layout.fillWidth: true
                placeholderText: "13:00"
                text: root.dueTime
                onTextChanged: root.dueTime = text
                onAccepted: root.activeCard = ""
              }

              Button {
                text: "Clear"
                foreground: root.fg
                accent: root.accent
                onClicked: root.dueTime = ""
              }
            }

            GridLayout {
              Layout.fillWidth: true
              columns: 4
              columnSpacing: Style.spacing.controlGap
              rowSpacing: Style.spacing.controlGap

              Repeater {
                model: root.timePresets

                Button {
                  Layout.fillWidth: true
                  text: modelData
                  foreground: root.fg
                  accent: root.accent
                  active: root.dueTime === modelData
                  onClicked: root.dueTime = modelData
                }
              }
            }
          }
        }

        Rectangle {
          id: leadCard
          visible: root.activeCard === "lead"
          Layout.fillWidth: true
          Layout.preferredHeight: leadLayout.implicitHeight + Style.spacing.panelPadding * 2
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: Qt.alpha(root.accent, 0.4)
          border.width: 1

          ColumnLayout {
            id: leadLayout
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            spacing: Style.spacing.controlGap

            GridLayout {
              Layout.fillWidth: true
              columns: 4
              columnSpacing: Style.spacing.controlGap
              rowSpacing: Style.spacing.controlGap

              Repeater {
                model: root.leadPresets

                Button {
                  Layout.fillWidth: true
                  text: modelData.label
                  foreground: root.fg
                  accent: root.accent
                  active: root.leadValue === modelData.value
                  onClicked: {
                    root.leadValue = modelData.value
                    root.leadMode = modelData.mode
                  }
                }
              }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.muted, 0.35) }

            Text {
              textFormat: Text.PlainText
              text: "Remind before the deadline"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap

              TextField {
                id: customField
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                placeholderText: "Number"
                text: root.customLeadValue
                onTextChanged: root.customLeadValue = text
                onAccepted: root.applyCustomLead()
              }

              Dropdown {
                id: unitField
                Layout.preferredWidth: Style.space(110)
                Layout.alignment: Qt.AlignVCenter
                showLabel: false
                options: root.unitOptions
                value: root.customLeadUnit
                onChanged: function(v) { root.customLeadUnit = v }
              }

              Button {
                text: "Use"
                accent: root.accent
                foreground: root.fg
                focusable: true
                onClicked: root.applyCustomLead()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "min = minutes before · h = hours before the deadline"
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.muted, 0.35) }

            Text {
              textFormat: Text.PlainText
              text: "Remind me in"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap

              TextField {
                id: remindInField
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                placeholderText: "Number"
                text: root.remindInValue
                onTextChanged: root.remindInValue = text
                onAccepted: root.applyRemindIn()
              }

              Dropdown {
                id: remindUnit
                Layout.preferredWidth: Style.space(110)
                Layout.alignment: Qt.AlignVCenter
                showLabel: false
                options: root.unitOptions
                value: root.remindInUnit
                onChanged: function(v) { root.remindInUnit = v }
              }

              Button {
                text: "Use"
                accent: root.accent
                foreground: root.fg
                focusable: true
                onClicked: root.applyRemindIn()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "min = minutes · h = hours from now: creates the task with the reminder within that time"
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          Text {
            textFormat: Text.PlainText
            visible: root.formNotice !== ""
            text: root.formNotice
            color: root.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          Button {
            text: root.editingTask ? "Save" : "＋ Add"
            accent: root.accent
            foreground: root.fg
            focusable: true
            onClicked: root.submit()
          }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.muted, 0.35) }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "Tasks"
          foreground: root.fg
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          Dropdown {
            id: sortField
            Layout.preferredWidth: Style.space(130)
            Layout.alignment: Qt.AlignVCenter
            showLabel: false
            options: root.sortOptions
            value: root.sortMode
            onChanged: function(v) { root.sortMode = v }
          }

          Dropdown {
            id: tagField
            Layout.preferredWidth: Math.max(
              Style.space(90),
              layout.width - sortField.implicitWidth - Style.spacing.controlGap)
            Layout.alignment: Qt.AlignVCenter
            showLabel: false
            options: root.tagOptions
            value: root.tagFilter
            onChanged: function(v) { root.tagFilter = v }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.service && root.service.canUndo
          spacing: Style.spacing.controlGap

          Text {
            textFormat: Text.PlainText
            text: root.service && root.service.lastDeleted
              ? "Deleted \"" + root.service.lastDeleted.title + "\""
              : ""
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Button {
            text: "Undo"
            accent: root.accent
            foreground: root.fg
            onClicked: root.service.restoreLast()
            tooltipText: "Restore the last deleted task"
          }
        }

        Item {
          id: listArea
          Layout.fillWidth: true
          implicitHeight: openVisible ? openFlick.height : openEmpty.height

          readonly property bool openVisible: root.openTasks.length > 0

          Flickable {
            id: openFlick
            visible: listArea.openVisible
            width: parent.width
            height: Math.min(openColumn.implicitHeight, Style.space(220))
            contentHeight: openColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: openColumn
              width: openFlick.width
              spacing: Style.spacing.rowGap

              Repeater {
                model: root.openTasks

                delegate: TaskRow {
                  width: openColumn.width
                  nowMs: root.nowMs
                  service: root.service
                  onEditRequested: root.startEdit(modelData)
                }
              }
            }
          }

          Text {
            id: openEmpty
            visible: !listArea.openVisible
            textFormat: Text.PlainText
            text: "No pending tasks."
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.right: parent.right
          }
        }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "Completed"
          foreground: root.fg
        }

        Item {
          id: doneArea
          Layout.fillWidth: true
          implicitHeight: doneVisible ? doneFlick.height : doneEmpty.height

          readonly property bool doneVisible: root.doneTasks.length > 0

          Flickable {
            id: doneFlick
            visible: doneArea.doneVisible
            width: parent.width
            height: Math.min(doneColumn.implicitHeight, Style.space(160))
            contentHeight: doneColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: doneColumn
              width: doneFlick.width
              spacing: Style.spacing.rowGap

              Repeater {
                model: root.doneTasks

                delegate: TaskRow {
                  width: doneColumn.width
                  nowMs: root.nowMs
                  service: root.service
                }
              }
            }
          }

          Text {
            id: doneEmpty
            visible: !doneArea.doneVisible
            textFormat: Text.PlainText
            text: "No completed tasks."
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.right: parent.right
          }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(root.muted, 0.35) }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          Button {
            Layout.fillWidth: true
            text: "Export .ics"
            foreground: root.fg
            accent: root.accent
            onClicked: root.service.exportIcs()
            tooltipText: "Writes ~/Cronos-export.ics for any calendar app"
          }

          Button {
            Layout.fillWidth: true
            text: "Export .json"
            foreground: root.fg
            accent: root.accent
            onClicked: root.service.exportJson()
            tooltipText: "Writes ~/Cronos-export.json"
          }

          Button {
            Layout.fillWidth: true
            text: "Import .ics"
            foreground: root.fg
            accent: root.accent
            onClicked: root.service.importIcs()
            tooltipText: "Reads ~/Cronos-import.ics"
          }

          Button {
            Layout.fillWidth: true
            text: "Import .json"
            foreground: root.fg
            accent: root.accent
            onClicked: root.service.importJson()
            tooltipText: "Reads ~/Cronos-import.json"
          }
        }

        Text {
          visible: root.service && root.service.sideMessage !== ""
          textFormat: Text.PlainText
          text: root.service ? root.service.sideMessage : ""
          color: root.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }
      }
    }
  }
}