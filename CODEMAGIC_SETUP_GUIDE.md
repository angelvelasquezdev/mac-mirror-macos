# Codemagic CI/CD Setup Guide for MacMirror

<p align="center">
  <a href="CODEMAGIC_SETUP_GUIDE.md">English</a> • <a href="CODEMAGIC_SETUP_GUIDE.es.md">Español</a>
</p>

This guide contains the exact steps to follow in the [Codemagic](https://codemagic.io/) web console and on [GitHub](https://github.com/) to make the continuous deployment system for **MacMirror** (Android and macOS) fully operational.

---

## General Structure

Since your project is split into two independent repositories:
1. `mac-mirror-android`
2. `mac-mirror-macos`

On the Codemagic web dashboard, you will have **two separate applications**, each with its own `codemagic.yaml`.

---

## Step 1: Generate the GitHub Personal Access Token (PAT)

The token allows Codemagic to create **GitHub Releases** and automatically upload `.apk`, `.aab`, and `.dmg` artifacts.

1. On GitHub, click your avatar (top right) $\rightarrow$ **Settings**.
2. At the bottom of the left sidebar, navigate to **Developer settings** $\rightarrow$ **Personal access tokens** $\rightarrow$ **Tokens (classic)** (or *Fine-grained tokens*).
3. Select **Generate new token (classic)**:
   - **Note**: `Codemagic CI/CD Releases`
   - **Expiration**: Select desired expiration (e.g. *No expiration* or *90 days*).
   - **Scopes (Permissions)**: Check `repo` (Full control of private repositories).
4. Click **Generate token** and copy the generated value (`ghp_...`). *(Store it securely; it will not be shown again).*

---

## Step 2: Configure the Android Application in Codemagic

### 2.1 Connect the Repository
1. In Codemagic, go to **Applications** $\rightarrow$ **Add application**.
2. Select **GitHub** as the Git provider and choose your `mac-mirror-android` repository.
3. Select project type **Android** and choose **codemagic.yaml** as the configuration mode.

### 2.2 Configure Android Code Signing (Keystore)
1. Inside the app in Codemagic, navigate to the **Code signing identities** tab $\rightarrow$ **Android code signing**.
2. Upload your keystore file (`.jks` or `.keystore`).
3. Fill in the fields:
   - **Keystore password**: Keystore password.
   - **Key alias**: Private key alias.
   - **Key password**: Private key password.
4. Under **Reference name**, enter exactly:
   ```text
   macmirror_signing_credentials
   ```
5. Click **Save**.

### 2.3 Configure Environment Variables
Go to the **Environment variables** tab and create the following two groups:

#### Group 1: `github_credentials`
* **Variable name**: `GITHUB_TOKEN`
* **Variable value**: Paste your GitHub token (`ghp_...`).
* **Group**: `github_credentials`
* Check the **Secure** checkbox (lock icon).
* Click **Add**.

#### Group 2: `google_play_credentials`
* **Variable name**: `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`
* **Variable value**: Paste the complete JSON key content of your Google Cloud service account with access to the Google Play Console.
* **Group**: `google_play_credentials`
* Check the **Secure** checkbox (lock icon).
* Click **Add**.

---

## Step 3: Configure the macOS Application in Codemagic

### 3.1 Connect the Repository
1. In Codemagic, go to **Applications** $\rightarrow$ **Add application**.
2. Select **GitHub** and choose your `mac-mirror-macos` repository.
3. Select project type **macOS** and choose **codemagic.yaml**.

### 3.2 Configure Environment Variables
Go to the **Environment variables** tab:

#### Group: `github_credentials`
* **Variable name**: `GITHUB_TOKEN`
* **Variable value**: Paste your GitHub token (`ghp_...`). Make sure this token has permissions for `mac-mirror-macos` and `homebrew-tap` (to automatically update Homebrew).
* **Group**: `github_credentials`
* Check the **Secure** checkbox (lock icon).
* Click **Add**.

### 3.3 Verify Automatic Trigger Webhook (GitHub)
For Codemagic to trigger 100% automatically on `push` or `tag` creation, the GitHub repository must have the webhook registered:
1. In Codemagic, go to the **MacMirror (macOS)** application and open the app settings (**App settings** / **Webhooks**).
2. Copy the webhook URL assigned to your app (`https://api.codemagic.io/hooks/<APP_ID>`). *(You can also get the `<APP_ID>` directly from the browser's address bar: `https://codemagic.io/app/<APP_ID>/...`)*.
3. On GitHub, navigate to: `https://github.com/angelvelasquezdev/mac-mirror-macos/settings/hooks/new`.
4. Configure the webhook:
   - **Payload URL**: `https://api.codemagic.io/hooks/<APP_ID>`
   - **Content type**: `application/json`
   - **Events**: *Let me select individual events* $\rightarrow$ Check **Pushes**, **Branch or tag creation**, and **Pull requests**.
5. Click **Add webhook**.

> [!NOTE]
> For macOS, you do not need to configure certificates in Codemagic at this stage, as we configured ad-hoc signing for open-source builds (`CODE_SIGN_IDENTITY="-"`).

---

## Step 4: How to Trigger Deployments

### 1. Android: Internal Continuous Deployment (Google Play Internal Track)
Triggered automatically whenever you push to the `develop` branch:
```bash
git checkout develop
git commit -m "feat: new feature"
git push origin develop
```
* **Result**: Codemagic will increment the build number, build the `.aab`, sign it, and publish it to the **Internal** track in the Google Play Console.

---

### 2. Beta Releases (GitHub Pre-releases)

Create a tag starting with `v` and containing `-beta` in the respective repository:

#### For Android:
```bash
cd android
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```
* **Result**:
  * Publishes the `.aab` to the **Beta** track in Google Play.
  * Creates a **Pre-release** on GitHub with automatically generated release notes.
  * Attaches both the `.aab` bundle and direct installer `.apk` to the GitHub release assets.

#### For macOS:
```bash
cd macos
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```
* **Result**:
  * Builds the `.app` with local ad-hoc signing.
  * Packages the compressed installer `MacMirror-v1.0.0-beta.1.dmg`.
  * Creates a **Pre-release** on GitHub and attaches the `.dmg` file.

---

### 3. Official Production Releases (Stable Releases)

Create a tag starting with `v` (without `-beta`):

#### For Android:
```bash
cd android
git tag v1.0.0
git push origin v1.0.0
```
* **Result**: Publishes to the **Production** track on Google Play and creates the **Official Release** on GitHub with the `.aab` and `.apk`.

#### For macOS:
```bash
cd macos
git tag v1.0.0
git push origin v1.0.0
```
* **Result**: Creates the **Official Release** on GitHub with the `MacMirror-v1.0.0.dmg` installer.

---

## Quick Verification & Troubleshooting

| Symptom | Probable Cause | Resolution |
| :--- | :--- | :--- |
| `Resource not accessible by integration` when running `gh release` | The `GITHUB_TOKEN` does not have write permissions | Verify that the token has `repo` scope (or `Contents: Read and write`). |
| `Signing credentials not found: macmirror_signing_credentials` | Reference name in Codemagic does not match | Check in *Android code signing* that the *Reference name* is exactly `macmirror_signing_credentials`. |
| `Variable GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS is missing` | Variable not added or group name is incorrect | Verify that the group is named `google_play_credentials` and is associated with the encrypted variable. |
