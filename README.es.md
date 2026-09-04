# MacMirror para macOS

<p align="center">
  <strong>Aplicación nativa y ligera para la barra de menú de macOS que refleja notificaciones de Android sobre Wi-Fi local.</strong>
</p>

<p align="center">
  <a href="README.md">English</a> • <a href="README.es.md">Español</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Plataforma-macOS%2014.0%2B%20(Sonoma%20%2F%20Sequoia)-000000?style=flat-square&logo=apple&logoColor=white" alt="Versión de macOS" />
  <img src="https://img.shields.io/badge/Lenguaje-Swift%205.9%2B-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-0071e3?style=flat-square&logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Arquitectura-Universal%20(Apple%20Silicon%20%2F%20Intel)-666666?style=flat-square" alt="Arquitectura" />
  <img src="https://img.shields.io/badge/Licencia-MIT-blue?style=flat-square" alt="Licencia: MIT" />
  <a href="https://github.com/angelvelasquezdev/mac-mirror-android"><img src="https://img.shields.io/badge/App%20Compañera-Cliente%20Android-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Repo Android" /></a>
</p>

---

## Descripción General

**MacMirror para macOS** es la aplicación receptora de escritorio de MacMirror. Permanece de forma discreta en la barra de menú de tu Mac, recibe las notificaciones emitidas por tu teléfono Android vinculado y las presenta como alertas nativas del sistema con sonido e íconos de la app correspondiente.

Desarrollada con **SwiftUI** siguiendo las **Pautas de Interfaz Humana de Apple (HIG)**, incluye una ventana emergente translúcida con efecto de cristal, vinculación instantánea, historial de notificaciones y funcionamiento 100% local sin nube.

> [!IMPORTANT]
> Esta aplicación requiere su contraparte móvil para Android para funcionar:
> 👉 **[Repositorio MacMirror para Android](https://github.com/angelvelasquezdev/mac-mirror-android)**

---

## ✨ Características Principales

- 🖥 **Experiencia Nativa en la Barra de Menú**: Siempre accesible desde la barra superior. Un popover elegante muestra el estado del dispositivo vinculado, dirección IP local y el historial cronológico de notificaciones recientes.
- 🔔 **Notificaciones Nativas del Sistema macOS**: Las alertas se presentan mediante `UNUserNotificationCenter` con sonido, banner visual y miniaturas del ícono de la app de Android que originó la notificación.
- 🔒 **Cifrado Extremo a Extremo (E2EE)**:
  - Autenticación mediante PIN criptográfico de 6 dígitos.
  - Negociación de claves efímera con Curva P-256 (ECDH) usando el framework nativo `CryptoKit`.
  - Descifrado de datos con AES-256-GCM al recibir el flujo de eventos.
- ⚡ **100% Local y Privado**: Servidor HTTP integrado (`:50001`) y servidor WebSocket (`:50002`). Publicación de servicio mediante **Bonjour / mDNS** (`_macmirror._tcp`) para detección automática sin configuración previa. Sin servidores de terceros ni cuentas externas.
- 🛡 **Almacenamiento Silencioso y Seguro**: Las claves de sesión se almacenan en el directorio privado de la aplicación (`~/Library/Application Support/MacMirror/`) con permisos estrictos POSIX `0600`, evitando los molestos cuadros de diálogo de contraseña del Keychain durante el desarrollo y actualización de la app.
- 🔄 **Desvinculación Bidireccional**: Al pulsar "Desvincular" en macOS, se desconecta inmediatamente el cliente Android y se genera un nuevo PIN.
- 🌐 **Internacionalización Completa (i18n)**: Soporte nativo para Español e Inglés.

---

## 🏗 Arquitectura y Red

```
┌─────────────────────────────────────────────────────────────┐
│                    MacMirror (macOS)                        │
├────────────────────────┬────────────────────────────────────┤
│ Bonjour (mDNS)         │ Emite servicio _macmirror._tcp:50001│
│ Servidor HTTP (:50001) │ /pair/start, /pair/verify, /status │
│ WebSocket (:50002)     │ Flujo cifrado de eventos en vivo   │
│ CryptoKit              │ Motor ECDH P-256 y AES-256-GCM     │
│ UserNotifications      │ Alertas nativas y sonido en macOS  │
└────────────────────────┴────────────────────────────────────┘
```

1. **Descubrimiento**: Al iniciar, `BonjourPublisher` publica el servicio en la red local utilizando `NetService`.
2. **Acuerdo de Clave**: El cliente Android descubre la Mac, solicita la clave pública efímera y verifica el PIN de 6 dígitos presentado en la barra de menú.
3. **Gestión del Flujo**: `WebSocketServer` acepta la conexión y reenvía los paquetes cifrados a `MacOSCrypto`, descifrando el contenido antes de entregarlo a `NotificationManager` para su presentación en pantalla.

---

## 📋 Requisitos del Sistema

- **Sistema Operativo**: macOS 14.0 (Sonoma) o macOS 15.0+ (Sequoia).
- **Arquitectura**: Compatible con Apple Silicon (M1/M2/M3/M4) e Intel x86_64 (Universal Binary).
- **Herramienta de Desarrollo**: Xcode 15.0 o superior.
- **Red Local**: Mac y teléfono Android deben estar en la misma red Wi-Fi o subred accesible.

---

## 📦 Instalación

### Mediante Homebrew (Recomendado)
Puedes instalar MacMirror directamente usando Homebrew:

```bash
brew install --cask angelvelasquezdev/tap/macmirror
```

> [!NOTE]
> Al ser un proyecto de código abierto sin un certificado de pago de Apple Developer, si macOS Gatekeeper bloquea la app en el primer inicio, simplemente ejecuta:
> ```bash
> xattr -cr /Applications/MacMirror.app
> ```
> O haz clic derecho sobre `MacMirror.app` en `/Applications` y selecciona **Abrir**.

Para actualizar en el futuro:
```bash
brew upgrade --cask macmirror
```

### Descarga Manual (.dmg)
Descarga la última imagen de disco desde la página de [Releases](https://github.com/angelvelasquezdev/mac-mirror-macos/releases), abre `MacMirror-vX.Y.Z.dmg` y arrastra `MacMirror.app` a tu carpeta `/Applications`. Si macOS muestra una advertencia al abrirla, ejecuta `xattr -d com.apple.quarantine /Applications/MacMirror.app` o usa clic derecho -> Abrir.

---

## 🚀 Compilación desde el Código Fuente

### 1. Clonar el Repositorio
```bash
git clone https://github.com/angelvelasquezdev/mac-mirror-macos.git
cd mac-mirror-macos
```

### 2. Abrir y Compilar con Xcode
```bash
open MacMirror.xcodeproj
```
- Selecciona el esquema `MacMirror`.
- Presiona `Cmd + R` para compilar y ejecutar.

### 3. Compilar desde la Terminal
```bash
xcodebuild -project MacMirror.xcodeproj -scheme MacMirror -configuration Release build
```

---

## 🗺️ Hoja de Ruta (Roadmap)

- [ ] 🔋 Mostrar el porcentaje de batería y estado de carga del dispositivo Android en el popover de la barra de menú.
- [ ] ⌨️ Atajo de teclado global para abrir/cerrar el popover rápidamente (`Cmd + Shift + M`).
- [ ] 🗑️ Limpiar el historial completo o descartar notificaciones individuales.
- [ ] 🌐 Nuevas traducciones (Francés, Alemán, Portugués, Italiano, Japonés).
- [ ] 💬 Acciones rápidas y descarte de notificaciones en tiempo real.

---

## 🤝 Cómo Contribuir

¡Las contribuciones son muy bienvenidas! Ya sea reportando errores, sugiriendo mejoras o traduciendo la app:

1. Revisa las issues abiertas etiquetadas con [`good first issue`](https://github.com/angelvelasquezdev/mac-mirror-macos/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) y [`help wanted`](https://github.com/angelvelasquezdev/mac-mirror-macos/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).
2. Consulta la [Guía de Contribución](CONTRIBUTING.md) para conocer el entorno de desarrollo, estilo de código y flujo de Pull Requests.

---

## 🔗 Proyectos Relacionados

| Proyecto | Descripción | Repositorio |
| :--- | :--- | :--- |
| **MacMirror (Android)** | Cliente móvil compañero para Android | [angelvelasquezdev/mac-mirror-android](https://github.com/angelvelasquezdev/mac-mirror-android) |

---

## 📄 Licencia

Este proyecto está bajo la **Licencia MIT**. Consulta el archivo [LICENSE](LICENSE) para más detalles.

Copyright (c) 2026 Ángel Velásquez
