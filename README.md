# Cronos

Bar widget y servicio para Omarchy con tareas y recordatorios con fecha límite.

![Captura de Cronos en la barra](docs/screenshot.png)

Un acceso rápido en la barra te deja anotar una tarea (título, nota opcional,
fecha y hora límite) y elegir cuándo avisarte:

- **Modo día**: avisa el mismo día del vencimiento (por ejemplo "1 día antes"),
  5 minutos después de cada inicio de sesión y cada 5 horas hasta que la avises.
- **Modo exacto**: avisa en el momento exacto configurado ("Momento", "1 h",
  "3 h", "6 h", "12 h"), con los campos personalizados "Recordar antes de la
  hora límite" (min/h) o "Recuérdame en" (min/h).
- Si la máquina estaba apagada cuando tocaba avisar, los recordatorios se
  notifican 5 minutos después del siguiente inicio de sesión.

Incluye una sección de tareas completadas, persistencia a prueba de pérdidas
(escritura atómica + copia de seguridad) y migración automática desde la
versión anterior del plugin (`angelherman.taskboard`).

## Instalación

Desde el marketplace:

```
omarchy plugin install angelherman.cronos --enable
```

O desde el repositorio:

```
omarchy plugin add https://github.com/angelherman/omarchy-cronos.git --enable
```

## Uso

1. Haz clic en el icono de Cronos en la barra (o en el contador de tareas
   urgentes).
2. Escribe el título, una nota opcional, la fecha/hora límite y el aviso.
3. Pulsa **＋ Añadir**.

Las tareas vencidas y sin avisar se marcan con color de urgencia en la barra.
Completar una tarea la mueve a "Completadas"; la ✕ la elimina.

El estado se guarda en `~/.local/state/omarchy/cronos/tasks.json`
(más `tasks.json.bak`).

## Desarrollo

```
omarchy plugin validate ~/.config/omarchy/plugins/angelherman.cronos
qmllint -I "$OMARCHY_PATH/shell" Panel.qml BarWidget.qml Service.qml TaskRow.qml
```

## Licencia

[MIT](LICENSE) © Angel Herman