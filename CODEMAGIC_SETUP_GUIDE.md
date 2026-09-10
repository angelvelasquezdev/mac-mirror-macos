# Guía de Configuración de Codemagic CI/CD para MacMirror

Esta guía contiene los pasos exactos que debes realizar en la consola web de [Codemagic](https://codemagic.io/) y en [GitHub](https://github.com/) para dejar completamente operativo el sistema de despliegue continuo de **MacMirror** (Android y macOS).

---

## Estructura General

Dado que tu proyecto está dividido en dos repositorios independientes:
1. `mac-mirror-android`
2. `mac-mirror-macos`

En la web de Codemagic tendrás **dos aplicaciones separadas**, cada una con su respectivo `codemagic.yaml`.

---

## Paso 1: Generar el Token de Acceso de GitHub (PAT)

El token permite a Codemagic crear las **GitHub Releases** y subir automáticamente los archivos `.apk`, `.aab` y `.dmg`.

1. En GitHub, haz clic en tu avatar (arriba a la derecha) $\rightarrow$ **Settings**.
2. Al final de la barra lateral izquierda, entra en **Developer settings** $\rightarrow$ **Personal access tokens** $\rightarrow$ **Tokens (classic)** (o *Fine-grained tokens*).
3. Selecciona **Generate new token (classic)**:
   - **Note**: `Codemagic CI/CD Releases`
   - **Expiration**: Elige la duración deseada (ej. *No expiration* o *90 days*).
   - **Scopes (Permisos)**: Marca la casilla `repo` (Full control of private repositories).
4. Haz clic en **Generate token** y copia el valor generado (`ghp_...`). *(Guárdalo en un lugar seguro; no se volverá a mostrar).*

---

## Paso 2: Configurar la Aplicación Android en Codemagic

### 2.1 Conectar el Repositorio
1. En Codemagic, ve a **Applications** $\rightarrow$ **Add application**.
2. Selecciona **GitHub** como proveedor git y escoge tu repositorio `mac-mirror-android`.
3. Selecciona tipo de proyecto **Android** y elige **codemagic.yaml** como modo de configuración.

### 2.2 Configurar la Firma de Android (Keystore)
1. Dentro de la app en Codemagic, ve a la pestaña **Code signing identities** $\rightarrow$ **Android code signing**.
2. Sube tu archivo Keystore (`.jks` o `.keystore`).
3. Llena los campos:
   - **Keystore password**: Contraseña del keystore.
   - **Key alias**: Alias de la clave privada.
   - **Key password**: Contraseña de la clave privada.
4. En **Reference name**, escribe exactamente:
   ```text
   macmirror_signing_credentials
   ```
5. Haz clic en **Save**.

### 2.3 Configurar las Variables de Entorno
Ve a la pestaña **Environment variables** y crea los siguientes dos grupos:

#### Grupo 1: `github_credentials`
* **Variable name**: `GITHUB_TOKEN`
* **Variable value**: Pega tu token de GitHub (`ghp_...`).
* **Group**: `github_credentials`
* Marca la casilla **Secure** (candado).
* Haz clic en **Add**.

#### Grupo 2: `google_play_credentials`
* **Variable name**: `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`
* **Variable value**: Pega el contenido JSON completo de la clave de tu cuenta de servicio de Google Cloud con acceso a Google Play Console.
* **Group**: `google_play_credentials`
* Marca la casilla **Secure** (candado).
* Haz clic en **Add**.

---

## Paso 3: Configurar la Aplicación macOS en Codemagic

### 3.1 Conectar el Repositorio
1. En Codemagic, ve a **Applications** $\rightarrow$ **Add application**.
2. Selecciona **GitHub** y escoge tu repositorio `mac-mirror-macos`.
3. Selecciona tipo de proyecto **macOS** y elige **codemagic.yaml**.

### 3.2 Configurar Variables de Entorno
Ve a la pestaña **Environment variables**:

#### Grupo: `github_credentials`
* **Variable name**: `GITHUB_TOKEN`
* **Variable value**: Pega tu token de GitHub (`ghp_...`). Asegúrate de que este token tenga permisos sobre `mac-mirror-macos` y `homebrew-tap` (para actualizar Homebrew automáticamente).
* **Group**: `github_credentials`
* Marca la casilla **Secure** (candado).
* Haz clic en **Add**.

### 3.3 Verificar el Webhook de Activación Automática (GitHub)
Para que Codemagic se active de manera 100% automática al hacer `push` o crear un `tag`, el repositorio de GitHub debe tener registrado el webhook:
1. En Codemagic, entra a la aplicación **MacMirror (macOS)** y abre los ajustes de la app (**App settings** / **Webhooks**).
2. Copia la URL del webhook asignada a tu app (`https://api.codemagic.io/hooks/<APP_ID>`). *(También puedes obtener el `<APP_ID>` directamente de la barra de dirección del navegador: `https://codemagic.io/app/<APP_ID>/...`)*.
3. En GitHub, abre: `https://github.com/angelvelasquezdev/mac-mirror-macos/settings/hooks/new`.
4. Configura el webhook:
   - **Payload URL**: `https://api.codemagic.io/hooks/<APP_ID>`
   - **Content type**: `application/json`
   - **Events**: *Let me select individual events* $\rightarrow$ Marca **Pushes**, **Branch or tag creation** y **Pull requests**.
5. Haz clic en **Add webhook**.

> [!NOTE]
> Para macOS no necesitas configurar certificados en Codemagic en este momento, ya que configuramos la firma ad-hoc para código abierto (`CODE_SIGN_IDENTITY="-"`).

---

## Paso 4: Cómo Disparar los Despliegues

### 1. Android: Despliegue Continuo Interno (Google Play Internal Track)
Se dispara automáticamente cada vez que haces un `push` a la rama `develop`:
```bash
git checkout develop
git commit -m "feat: nueva funcionalidad"
git push origin develop
```
* **Resultado**: Codemagic incrementará el build number, generará el `.aab`, lo firmará y lo publicará en el track **Internal** de Google Play Console.

---

### 2. Versiones Beta (Pre-releases en GitHub)

Crea un tag que empiece por `v` y contenga `-beta` en el repositorio respectivo:

#### Para Android:
```bash
cd android
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```
* **Resultado**:
  * Publica el `.aab` en el track **Beta** de Google Play.
  * Crea una **Pre-release** en GitHub con las notas generadas automáticamente.
  * Adjunta tanto el `.aab` como el instalador directo `.apk` en los assets de la release en GitHub.

#### Para macOS:
```bash
cd macos
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```
* **Resultado**:
  * Compila el `.app` con firma local ad-hoc.
  * Empaqueta el instalador comprimido `MacMirror-v1.0.0-beta.1.dmg`.
  * Crea una **Pre-release** en GitHub y adjunta el archivo `.dmg`.

---

### 3. Versiones Oficiales de Producción (Releases Estables)

Crea un tag que empiece por `v` (sin `-beta`):

#### Para Android:
```bash
cd android
git tag v1.0.0
git push origin v1.0.0
```
* **Resultado**: Publica en el track **Production** de Google Play y crea la **Release oficial** en GitHub con el `.aab` y `.apk`.

#### Para macOS:
```bash
cd macos
git tag v1.0.0
git push origin v1.0.0
```
* **Resultado**: Crea la **Release oficial** en GitHub con el instalador `MacMirror-v1.0.0.dmg`.

---

## Verificación Rápida y Solución de Problemas

| Síntoma | Causa probable | Solución |
| :--- | :--- | :--- |
| `Resource not accessible by integration` al ejecutar `gh release` | El token `GITHUB_TOKEN` no tiene permisos de escritura | Verifica que el token tenga permiso `repo` (o `Contents: Read and write`). |
| `Signing credentials not found: macmirror_signing_credentials` | El nombre de referencia en Codemagic no coincide | Revisa en *Android code signing* que el *Reference name* sea exactamente `macmirror_signing_credentials`. |
| `Variable GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS is missing` | Variable no agregada o nombre de grupo incorrecto | Verifica que el grupo se llame `google_play_credentials` y esté asociado a la variable encriptada. |
