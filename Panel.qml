import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "TaskModel.js" as Model

// Taskboard popup: add a task (title + due date via inline calendar or text +
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
  readonly property var openTasks: service ? service.sortedOpenTasks : []
  readonly property var doneTasks: service ? service.sortedDoneTasks : []

  readonly property string summary: {
    var parts = root.dueInput
      ? ["Vence " + Model.humanDue(root.dueInput, root.nowMs)]
      : ["Sin fecha límite"]
    if (root.dueTime) parts[0] += " · " + root.dueTime
    var lead = Number(root.leadValue) || 0
    parts.push("aviso " + Model.leadLabel(lead))
    return parts.join(" · ")
  }

  property string titleText: ""
  property string notesText: ""
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
  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()

  readonly property var timePresets: [
    "07:00", "09:00", "12:00", "15:00", "18:00", "21:00", "23:59"
  ]

  readonly property var leadPresets: [
    { value: "0",   label: "Momento", mode: "exact" },
    { value: "1",   label: "1 h",     mode: "exact" },
    { value: "3",   label: "3 h",     mode: "exact" },
    { value: "6",   label: "6 h",     mode: "exact" },
    { value: "12",  label: "12 h",    mode: "exact" },
    { value: "24",  label: "1 día",   mode: "day" },
    { value: "48",  label: "2 días",  mode: "day" },
    { value: "72",  label: "3 días",  mode: "day" },
    { value: "120", label: "5 días",  mode: "day" },
    { value: "168", label: "1 sem",   mode: "day" },
    { value: "336", label: "2 sem",   mode: "day" }
  ]

  readonly property var unitOptions: [
    { value: "min", label: "min" },
    { value: "h",   label: "horas" }
  ]

  readonly property var viewWeeks: Model.monthGrid(root.viewYear, root.viewMonth)

  // Resolves whatever the user typed ("hoy", "+3", an ISO date) so the
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
      root.formNotice = "Escribe un número mayor que 0 en recordatorio personalizado"
      return
    }
    root.leadValue = String(root.customLeadUnit === "min" ? n / 60 : n)
    root.leadMode = "exact"
  }

  function applyRemindIn() {
    var n = Number(root.remindInValue)
    if (!isFinite(n) || n <= 0) {
      root.formNotice = "Escribe un número mayor que 0 en 'Recuérdame en'"
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
    root.formNotice = "Se añadirá con aviso en " + n + (root.remindInUnit === "min" ? " min" : " h") + " (vence hoy " + root.dueTime + ")"
  }

  function resetForm() {
    root.titleText = ""
    root.notesText = ""
    root.dueInput = ""
    root.dueTime = ""
    root.customLeadValue = ""
    root.remindInValue = ""
    root.formNotice = ""
    root.activeCard = ""
    root.resetCalendarView()
  }

  function submit() {
    if (!root.service) return
    if (root.service.add(root.titleText, root.dueInput, root.dueTime, root.leadValue, root.notesText, root.leadMode)) {
      root.resetForm()
      titleField.forceActiveFocus()
    } else {
      root.formNotice = "Revisa el título y elige una fecha"
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
          text: "Cronos"
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
          placeholderText: "Título de la tarea"
          text: root.titleText
          onTextChanged: root.titleText = text
          onAccepted: root.submit()
        }

        TextField {
          id: notesField
          Layout.fillWidth: true
          placeholderText: "Descripción o apuntes (opcional)"
          text: root.notesText
          onTextChanged: root.notesText = text
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          Button {
            id: dateButton
            Layout.fillWidth: true
            text: "Fecha"
            foreground: root.fg
            accent: root.accent
            active: root.activeCard === "date"
            focusable: true
            tooltipText: "Elegir la fecha de vencimiento"
            onClicked: root.toggleCard("date")
          }

          Button {
            id: timeButton
            Layout.fillWidth: true
            text: "Hora"
            foreground: root.fg
            accent: root.accent
            active: root.activeCard === "time"
            focusable: true
            tooltipText: "Elegir la hora límite de entrega"
            onClicked: root.toggleCard("time")
          }

          Button {
            id: leadButton
            Layout.fillWidth: true
            text: "Recordatorio"
            foreground: root.fg
            accent: root.accent
            active: root.activeCard === "lead"
            focusable: true
            tooltipText: "Cuánto antes avisarte"
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
                tooltipText: "Mes anterior"
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
                tooltipText: "Volver al mes actual"
              }

              PanelActionButton {
                iconText: "›"
                foreground: root.accent
                tooltipText: "Mes siguiente"
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
                model: ["L", "M", "X", "J", "V", "S", "D"]

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
                text: "Selecciona un día del mes"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
              }

              Button {
                text: "Hoy"
                foreground: root.fg
                accent: root.accent
                onClicked: root.pickDate(Model.todayStamp())
                tooltipText: "Elegir el día de hoy"
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
                text: "Quitar"
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

            PanelSeparator { Layout.fillWidth: true }

            Text {
              textFormat: Text.PlainText
              text: "Recordar antes de la hora límite"
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
                placeholderText: "Número"
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
                text: "Usar"
                accent: root.accent
                foreground: root.fg
                focusable: true
                onClicked: root.applyCustomLead()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "min = minutos antes · horas = horas antes del vencimiento"
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            PanelSeparator { Layout.fillWidth: true }

            Text {
              textFormat: Text.PlainText
              text: "Recuérdame en"
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
                placeholderText: "Número"
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
                text: "Usar"
                accent: root.accent
                foreground: root.fg
                focusable: true
                onClicked: root.applyRemindIn()
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "min = minutos · horas = horas desde ahora: crea la tarea con el aviso dentro de ese tiempo"
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
            text: "＋ Añadir"
            accent: root.accent
            foreground: root.fg
            focusable: true
            onClicked: root.submit()
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "Tareas"
          foreground: root.fg
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
                }
              }
            }
          }

          Text {
            id: openEmpty
            visible: !listArea.openVisible
            textFormat: Text.PlainText
            text: "No hay tareas pendientes."
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.right: parent.right
          }
        }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "Completadas"
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
            text: "Sin tareas completadas."
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.right: parent.right
          }
        }
      }
    }
  }
}