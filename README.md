<p align="center">
  <a href="https://medupro.de"><img src="docs/medupro-logo.png" width="260" alt="MeduPro"></a>
</p>

<p align="center">
  <img src="Resources/AppIcon-1024.png" width="112" alt="Tomato-Installer Symbol">
</p>

<h1 align="center">Tomato-Installer</h1>

<p align="center">
  <b>tomedo® und Arzeko auf dem Mac in einem Schritt einrichten.</b><br>
  Server finden, herunterladen, verbinden, ins Dock legen. Fertig.
</p>

<p align="center">
  <a href="https://medupro.de"><img alt="Download auf medupro.de" src="https://img.shields.io/badge/Download-medupro.de-6D3FD9?style=for-the-badge"></a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2A44?logo=apple&logoColor=white">
  <img alt="Apple Silicon und Intel" src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-1F2A44">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="Kostenlos" src="https://img.shields.io/badge/Preis-kostenlos-2EA44F">
  <img alt="Lizenz" src="https://img.shields.io/badge/Lizenz-alle%20Rechte%20vorbehalten-6D3FD9">
</p>

<p align="center">
  <a href="https://medupro.de">Webseite</a> ·
  <a href="mailto:support@medupro.de">Support</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#benutzung">Benutzung</a> ·
  <a href="#fehlerbehebung">Hilfe</a> ·
  <a href="LICENSE">Lizenz</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
    <img src="docs/screenshot-light.png" width="440" alt="Tomato-Installer mit zwei gefundenen tomedo-Servern">
  </picture>
</p>

---

## Warum?

Ein neuer Mac in der Praxis braucht tomedo. Von Hand heißt das: Ordner anlegen,
tomedo.app irgendwo herunterladen, Serveradresse eintippen, ins Dock ziehen, auf das
erste Update warten. Für Arzeko dasselbe noch einmal.

**Tomato-Installer macht das mit einem Klick.**

| | |
|---|---|
| 🔎 **Findet eure Server selbst** | Sucht beim Start im Praxisnetz und zeigt jeden tomedo-Server als Liste zum Anklicken |
| ⬇️ **Immer die richtige Version** | Lädt tomedo und auf Wunsch Arzeko direkt von eurem Server, also genau die Version, die eure Praxis nutzt |
| 🔌 **Sofort verbunden** | Trägt die Serveradresse ein, tomedo fragt beim ersten Start nicht mehr danach. Arzeko bekommt seine Verbindung gleich mit |
| 📂 **Am richtigen Ort** | Legt die Apps in `~/Applications` ab, dort wo tomedo hingehört, und auf Wunsch ins Dock |
| 🔐 **Ohne Admin-Passwort** | Installiert für den angemeldeten Benutzer, kein Terminal, keine Systemrechte |
| 🛡️ **Sorgfältig** | Prüft Arzeko per SHA-512, legt Apps erst vollständig entpackt ab, lässt Vorhandenes in Ruhe |
| 🙈 **Keine Daten an uns** | Spricht ausschließlich mit eurem tomedo-Server, kein Tracking, keine Telemetrie |

Updates übernehmen tomedo und Arzeko danach wie gewohnt selbst.

## Voraussetzungen

- macOS 14 Sonoma oder neuer, Apple Silicon oder Intel
- Der Mac erreicht den tomedo-Server (Praxisnetz oder VPN)

## Installation

1. **Tomato-Installer** kostenlos auf **[medupro.de](https://medupro.de)** herunterladen und das DMG öffnen.
2. **Tomato-Installer** doppelklicken. Die App kann direkt aus dem DMG laufen.
3. Beim ersten Öffnen meldet macOS, dass die App nicht überprüft werden konnte. Sie ist
   nicht bei Apple notarisiert, sondern nur ad-hoc signiert. So gibst du sie einmalig frei:
   - Meldung mit **Fertig** schließen.
   - **Systemeinstellungen › Datenschutz & Sicherheit** öffnen und ganz nach unten scrollen.
   - Bei „Tomato-Installer wurde blockiert“ auf **Dennoch öffnen** klicken und bestätigen.
4. Fragt macOS nach dem **lokalen Netzwerk**, bitte **Erlauben**. Sonst findet die App
   den tomedo-Server nicht.

> [!TIP]
> Prüfsumme kontrollieren: `shasum -a 256 Tomato-Installer-*.dmg` und mit der
> `.sha256`-Datei vergleichen.

## Benutzung

1. **Server wählen.** Nach wenigen Sekunden stehen alle tomedo-Server im Praxisnetz in der
   Liste. Gibt es genau einen, ist er schon ausgewählt. Steht dein Server nicht dabei, etwa
   weil er über VPN oder auf einem anderen Port läuft, die Adresse eingeben:
   `192.168.1.10`, `server.praxis:8080/tomedo_live/` oder `https://tomedo.praxis.de:8443`.
2. **Nur tomedo** oder **tomedo + Arzeko** wählen.
3. **Installieren** und danach mit **tomedo öffnen** direkt loslegen.

Die App installiert für den **angemeldeten Benutzer**. Für weitere Benutzer einfach unter
deren Konto erneut starten.

<details>
<summary><b>Was genau passiert</b></summary>

| Schritt | Ort |
|---|---|
| Server suchen | HEAD-Anfrage an jede Adresse im eigenen privaten Netz (höchstens /22, sonst /24), Port 8080 |
| tomedo laden | `http://<server>:8080/tomedo_live/filebyname/serverinternal/tomedo.app.tar` |
| Arzeko-Version abfragen | `…/arzeko/latestmac?version=0.0.0&aarch=arm\|intel` |
| Apps ablegen | `~/Applications/tomedo.app`, `~/Applications/Arzeko.app` |
| Server für tomedo | `defaults read com.zollsoft.tomedo-macOS ZS_ServerAdress` |
| Server für Arzeko | `~/Library/Application Support/Arzeko/usersetting.json` |
| Dock | `com.apple.dock persistent-apps` (vorhandene Einträge bleiben) |
| Eigene Einstellungen | `~/Library/Preferences/de.medupro.tomato-installer.plist` |

</details>

## Fehlerbehebung

- **Kein Server in der Liste:** Ist der Mac im Praxisnetz? Wurde der Zugriff auf das
  lokale Netzwerk erlaubt (Systemeinstellungen › Datenschutz & Sicherheit › Lokales
  Netzwerk)? Server per VPN bitte von Hand eingeben.
- **„Server nicht erreichbar“:** Lässt sich `http://<server>:8080/tomedo_live/` im Browser öffnen?
- **„liefert kein tomedo aus (HTTP 404)“:** Port oder Pfad stimmen nicht.
- **Neu installieren:** `~/Applications/tomedo.app` in den Papierkorb legen und erneut starten.
- **Protokoll:** Konsole.app öffnen und nach `de.medupro.tomato-installer` filtern.

Hilfe gibt es unter **[support@medupro.de](mailto:support@medupro.de)**. Im Fehlerfall füllt
der Knopf **Support kontaktieren** die Mail schon mit den nötigen Angaben.

## Entwicklung

```bash
swift test                                              # Tests
TOMATO_TEST_SERVER=192.168.1.10 swift test              # zusätzlich gegen echten Server (installiert nichts)
TOMATO_TEST_SERVER=… TOMATO_TEST_INSTALL=1 swift test   # Ende-zu-Ende in Wegwerf-Ordner
swift run TomatoInstaller                               # App ohne Bundle starten
TOMATO_EXTRA_NETWORKS=192.168.10.0/24 swift run TomatoInstaller   # zusätzlich ein entferntes Netz durchsuchen
TOMATO_DEMO=1 TOMATO_APPEARANCE=dark swift run TomatoInstaller    # Vorführmodus für Bildschirmfotos
scripts/build-app.sh                                    # dist/: .app, .zip, .dmg, .sha256
swift scripts/make-icon.swift Resources/AppIcon-1024.png   # Symbol neu zeichnen
```

| Ordner | Inhalt |
|---|---|
| `Sources/TomatoCore` | Installationslogik ohne Oberfläche: Adressen, Serversuche, Download, Entpacken, Konfiguration, Dock |
| `Sources/TomatoInstaller` | SwiftUI-Oberfläche |
| `Tests/TomatoCoreTests` | Swift Testing, inklusive optionaler Echttests |
| `scripts/` | Build, Signatur, DMG und App-Symbol |

## Lizenz und Marken

Quelltext einsehbar, **alle Rechte vorbehalten**. Die veröffentlichte App ist kostenlos
nutzbar, auch in Praxen. Weitergabe und Änderungen nur mit Zustimmung, siehe [LICENSE](LICENSE).

Teile der Logik stammen aus [tomi](https://github.com/bjoernalbers/tomi) von Björn Albers
(MIT-Lizenz), siehe [NOTICE](NOTICE). Danke!

tomedo® ist eine eingetragene Marke der zollsoft GmbH. Tomato-Installer ist ein
unabhängiges Projekt von MeduPro und steht in keiner Verbindung zur zollsoft GmbH.

---

<p align="center">
  <a href="https://medupro.de"><img src="docs/medupro-logo.png" width="120" alt="MeduPro"></a><br>
  <sub>Ein kostenloses Angebot von <a href="https://medupro.de">MeduPro</a> · <a href="mailto:support@medupro.de">support@medupro.de</a> · <a href="https://github.com/MeduPro">github.com/MeduPro</a></sub>
</p>
