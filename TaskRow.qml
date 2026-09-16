import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "TaskModel.js" as Model

// One task row: toggle-done circle, title + status line, delete. Shared by
// the open ("Tareas") and completed ("Completadas") lists in the panel.
Item {
  id: row

  required property var modelData
  required property real nowMs
  required property var service

  readonly property var task: modelData

  readonly property bool done: task.done === true
  readonly property bool hasNotes: typeof row.task.notes === "string" && row.task.notes !== ""
  readonly property bool reminderDue: Model.reminderDueNow(task, row.nowMs)
  readonly property bool overdue: !done && !isNaN(Model.dueMs(task)) && row.nowMs > Model.dueMs(task)

  readonly property color fg: Color.popups.text
  readonly property color muted: Qt.darker(fg, 1.55)

  implicitHeight: rowContent.implicitHeight
  width: parent ? parent.width : 0

  RowLayout {
    id: rowContent
    width: parent.width
    spacing: Style.spacing.controlGap

    Button {
      text: row.done ? "◉" : "○"
      foreground: row.done ? row.muted : (row.overdue ? Color.urgent : Color.accent)
      Layout.preferredWidth: Style.space(24)
      Layout.preferredHeight: Style.space(26)
      onClicked: row.service.toggleDone(task.id)
      tooltipText: row.done ? "Reabrir" : "Completar"
    }

    Column {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs

      Text {
        textFormat: Text.PlainText
        text: row.task.title
        color: row.done ? row.muted : row.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.strikeout: row.done
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        visible: row.hasNotes && !row.done
        textFormat: Text.PlainText
        text: row.task.notes
        color: row.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: row.statusLine
        color: row.reminderDue ? Color.urgent : row.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        width: parent.width
        elide: Text.ElideRight
      }
    }

    PanelActionButton {
      iconText: "✕"
      foreground: row.muted
      hoverColor: Color.urgent
      tooltipText: "Eliminar"
      onClicked: row.service.removeTask(task.id)
    }
  }

  readonly property string statusLine: {
    if (row.done) return "Completada"
    var line = "Vence " + Model.humanDue(task.due, row.nowMs)
    var lead = Number(task.leadHours) || 0
    if (lead > 0) line += " · aviso " + Model.leadLabel(lead) + " antes"
    if (row.overdue) line += " · ¡vencida!"
    else if (row.reminderDue) line += " · ¡avisar ahora!"
    return line
  }
}