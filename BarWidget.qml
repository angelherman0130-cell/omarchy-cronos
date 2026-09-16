import QtQuick
import qs.Commons
import qs.Ui
import "TaskModel.js" as Model

// Bar slot for Cronos. One instance per monitor; the service holds all
// state, this only renders the count and opens the panel.
BarWidget {
  id: root
  moduleName: "angelherman.cronos"

  // nf-fa-hourglass - a deadline reads as time running out at bar size.
  readonly property string icon: "\uF254"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("angelherman.cronos")
    : null

  readonly property int openCount: service ? service.openCount : 0
  readonly property bool urgent: service ? service.urgent === true : false

  readonly property string tooltip: !service
    ? "Cronos — aún no cargado"
    : (openCount === 0 ? "Cronos — sin tareas"
      : "Cronos — " + openCount + (openCount === 1 ? " tarea pendiente" : " tareas pendientes")
        + (urgent ? "\nAlguna vence pronto" : ""))

  // Vertical bars are icon-only.
  readonly property string label: root.vertical ? root.icon : root.icon + (openCount > 0 ? "  " + openCount : "")

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Always keep the slot visible so the panel can always be opened, even
  // with zero tasks.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    active: root.urgent
    activeColor: bar ? bar.urgent : Color.urgent
    tooltipText: root.tooltip

    // The glyph is always shown, so the slot always has content.
    hasVisualContent: true

    onPressed: function(b) {
      if (b !== Qt.LeftButton) return
      root.togglePanel()
    }
  }
}