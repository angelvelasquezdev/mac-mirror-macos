# Contribuir a MacMirror para macOS 🍏

<p align="center">
  <a href="CONTRIBUTING.md">English</a> • <a href="CONTRIBUTING.es.md">Español</a>
</p>

¡Gracias por tu interés en contribuir a **MacMirror para macOS**! Agradecemos reportes de errores, propuestas de nuevas funcionalidades, traducciones y pull requests.

---

## 🗺️ Hoja de Ruta y Por Dónde Empezar

¿Buscas algo en lo que trabajar?
- Revisa las issues abiertas etiquetadas con [`good first issue`](https://github.com/angelvelasquezdev/mac-mirror-macos/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) y [`help wanted`](https://github.com/angelvelasquezdev/mac-mirror-macos/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).
- Funcionalidades planificadas:
  - 🔋 Indicador de porcentaje de batería del teléfono Android emparejado.
  - ⌨️ Atajo de teclado global para abrir/cerrar el popover de la barra de menús.
  - 🗑️ Borrar entradas individuales o todo el historial de notificaciones.
  - 🌐 Localizaciones adicionales (francés, alemán, portugués, italiano, japonés).
  - 💬 Acciones rápidas / descartar notificaciones en línea.

---

## 🛠️ Configuración del Entorno de Desarrollo

### Requisitos previos
- macOS 14.0 (Sonoma) o macOS 15.0+ (Sequoia).
- Xcode 15.0 o posterior.
- Swift 5.9+.

### Obtener el código
```bash
git clone https://github.com/angelvelasquezdev/mac-mirror-macos.git
cd mac-mirror-macos
open MacMirror.xcodeproj
```

### Ejecutar localmente sin una cuenta de pago de Apple Developer
1. Abre el proyecto en Xcode.
2. En **Signing & Capabilities**:
   - Cambia el Bundle Identifier o selecciona tu **Personal Team** en el menú desplegable Team.
   - Elige **Sign to Run Locally**.
3. Selecciona tu Mac como destino de ejecución.
4. Presiona `Cmd + R` para compilar e iniciar la aplicación en la barra de menús.

---

## 📐 Arquitectura del Proyecto

- `MacMirrorApp.swift`: Ciclo de vida de la aplicación y gestión de `MenuBarExtra` / Status Item.
- `ContentView.swift`: Interfaz de usuario SwiftUI glassmorphic en popover siguiendo las Apple Human Interface Guidelines.
- `UI/MenuBarViewModel.swift`: Almacén de estado que vincula eventos de red, PIN de emparejamiento e historial de notificaciones.
- `Network/BonjourPublisher.swift`: Descubrimiento local mDNS que transmite `_macmirror._tcp`.
- `Network/HTTPServer.swift`: Servidor HTTP integrado para la negociación de emparejamiento (`/pair/start`, `/pair/verify`).
- `Network/WebSocketServer.swift`: Receptor de stream WebSocket para notificaciones cifradas en tiempo real.
- `Security/macOSCrypto.swift`: Motor de acuerdo de claves ECDH P-256 y descifrado AES-256-GCM usando `CryptoKit` nativo.
- `Notifications/NotificationManager.swift`: Envía alertas de banner nativas a través de `UNUserNotificationCenter`.

---

## 🌐 Internacionalización (i18n)

MacMirror prohíbe estrictamente cadenas de texto hardcodeadas en la interfaz de usuario:
- Todo texto visible para el usuario debe declararse en los catálogos de cadenas:
  - `en.lproj/Localizable.strings` (Inglés por defecto)
  - `es.lproj/Localizable.strings` (Español)
- Al agregar nuevas claves, actualiza todos los archivos de idiomas soportados.

---

## 🔀 Enviar un Pull Request

1. **Haz un fork del repositorio** y crea tu rama a partir de `main`:
   ```bash
   git checkout -b feat/nombre-de-tu-funcionalidad
   ```
2. **Sigue las guías de estilo de Apple Swift**:
   - Patrones limpios de SwiftUI, evita el desempaquetado forzado (`!`), prefiere tipado fuerte.
3. **Realiza commits claros**:
   - Sigue los Conventional Commits: `feat: ...`, `fix: ...`, `docs: ...`, `refactor: ...`.
4. **Prueba tus cambios**:
   - Asegúrate de que el proyecto compile limpiamente (`Cmd + B`) y que las pruebas unitarias pasen (`Cmd + U`).
5. **Abre un Pull Request**:
   - Haz referencia a cualquier issue relacionada (ej. `Closes #1`).
