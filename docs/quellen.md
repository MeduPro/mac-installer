# Quellen

Woher der MeduPro Mac-Installer weiß, wie tomedo, Arzeko und das Dock arbeiten. Jede Angabe ist an
einer Primärquelle geprüft: an der tomedo-App, an Arzeko, an einem tomedo-Server oder an
macOS selbst. Geprüft am 07.11.2026 mit tomedo 1.172 und Arzeko 1.171.0.

## tomedo

| Angabe | Quelle |
|---|---|
| Archiv `…/tomedo_live/filebyname/serverinternal/tomedo.app.tar` | Die tomedo-App enthält die Zeichenketten `filebyname/serverinternal/` und `%@/tomedo.app.tar` (`strings tomedo.app/Contents/MacOS/tomedo`). Ein tomedo-Server liefert das Archiv dort aus (HTTP 200, rund 1,85 GB). |
| Standardport 8080 und Pfad `tomedo_live` | Serveradresse einer bestehenden tomedo-Installation (`defaults read com.zollsoft.tomedo-macOS ZS_ServerAdress`) und Standardwerte in Arzeko (`httpPort: 8080`, `basePath: 'tomedo_live'`). |
| Serveradresse in `com.zollsoft.tomedo-macOS`, Schlüssel `ZS_ServerAdress` | Die tomedo-App enthält die Zeichenkette `ZS_ServerAdress`. Arzeko liest die Adresse genau dort aus (`plutil -extract ZS_ServerAdress raw ~/Library/Preferences/com.zollsoft.tomedo-macOS.plist`, siehe unten). |
| `Accept-Encoding: identity` | Antwort eines tomedo-Servers: Mit `Accept-Encoding: gzip` kommt das Archiv als `Content-Encoding: gzip` ohne Größenangabe, mit `identity` unkomprimiert mit `Content-Length`. |
| Arbeitsplatz nach dem ersten Start einrichten | tomedo-Handbuch, [Arbeitsplatz](https://support.tomedo.de/handbuch/tomedo/praxisverwaltung/arbeitsplatz/). |

## Arzeko

Arzeko ist eine Electron-App. Die Angaben stammen aus ihrem eigenen Code in
`Arzeko.app/Contents/Resources/app.asar`. Version 1.171.0 wurde vom tomedo-Server geladen
(siehe unten) und mit `npx @electron/asar extract` entpackt.

| Angabe | Quelle |
|---|---|
| Versionsabfrage `…/arzeko/latestmac?version=<Version>&aarch=<arm\|intel>` | `main-process/settings/user.setting.mjs` (`autoUpdatePath: 'arzeko/latestmac?version='`) und `main-process/auto-update/app.updater.mjs` (`baseUrl + currentVersion + '&aarch=' + currentArch`). Mit Version `0.0.0` liefert der Server die neueste Version. |
| `arm` oder `intel` über `hw.optional.arm64` | `main-process/auto-update/get-aarch.mjs` (`sysctl hw.optional.arm64`). |
| Antwort mit `url`, `name`, `sha512`, `filesize` | Antwort eines tomedo-Servers. `main-process/auto-update/custom.provider.mjs` liest dieselben Felder. |
| Download-Adresse aus dem Host-Header | Antwort eines tomedo-Servers: Mit `Host: 127.0.0.1:9901` meldet er `http://127.0.0.1:9901/resteasy/…`. Deshalb übernimmt die App aus der Antwort nur Pfad und Abfrage und setzt Schema, Host und Port der gewählten Serveradresse. |
| Einstellungen in `~/Library/Application Support/Arzeko/usersetting.json` | `user.setting.mjs`: `app.getPath('userData') + '/usersetting.json'`. |
| Nur Verbindungsangaben schreiben | `user.setting.mjs`: `mergeWithDefault` ergänzt beim Start jeden fehlenden Schlüssel mit Arzekos eigenen Standardwerten. `parseConnectionSettingsFromUrl` bildet aus einer Serveradresse `protocol`, `ipAddress`, `<protocol>Port` und `basePath`. Der MeduPro Mac-Installer schreibt genau diese vier Werte. Eine Datei nur mit ihnen ergibt nach Arzekos Merge dieselbe Datei, die Arzeko beim ersten Start selbst anlegt (mit Arzekos `mergeWithDefault` in Node nachgeprüft). Vorhandene Einstellungen bleiben erhalten. |
| Start aus tomedo, Serveradresse | tomedo-Handbuch, [Arzeko: tomedo einbinden](https://support.tomedo.de/handbuch/arzeko/allgemeines/tomedo-einbinden/). |

## macOS

| Angabe | Quelle |
|---|---|
| Ablage in `~/Applications` | Vorgabe von MeduPro: Der Programme-Ordner des Benutzers ist ohne Administratorpasswort beschreibbar. `.localized` im Ordner lässt den Finder „Programme“ anzeigen, wie bei den Ordnern, die macOS selbst anlegt. |
| Dock-Eintrag in `com.apple.dock`, `persistent-apps` | Einträge, die das Dock selbst angelegt hat (`defaults export com.apple.dock`): `tile-type` `file-tile`, `tile-data` → `file-data` mit `_CFURLString` (Datei-URL) und `_CFURLStringType` 15. Danach `killall Dock`, damit das Dock die Einstellung neu liest. |
| Einstellungen anderer Apps schreiben | Apple, [CFPreferences](https://developer.apple.com/documentation/corefoundation/preferences_utilities): `CFPreferencesSetAppValue` und `CFPreferencesAppSynchronize`. |
| Prozessor über `hw.optional.arm64` | `sysctlbyname` meldet 1 auf Apple Silicon, auch wenn die App unter Rosetta läuft. Arzeko verwendet denselben Wert. |
