<p align="center">
  <a href="https://medupro.de"><img src="docs/medupro-logo.png" width="260" alt="MeduPro"></a>
</p>

<p align="center">
  <img src="Resources/AppIcon-1024.png" width="112" alt="Tomato-Installer Symbol">
</p>

<h1 align="center">Tomato-Installer</h1>

<p align="center">
  <b>Installiert tomedo® und Arzeko auf einem Mac direkt vom tomedo-Server der Praxis.</b>
</p>

<p align="center">
  <a href="https://medupro.de/tomato-installer/"><img alt="Download auf medupro.de" src="https://img.shields.io/badge/Download-medupro.de-6D3FD9?style=for-the-badge"></a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-1F2A44?logo=apple&logoColor=white">
  <img alt="Apple Silicon und Intel" src="https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-1F2A44">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="Kostenlos" src="https://img.shields.io/badge/Preis-kostenlos-2EA44F">
  <img alt="Lizenz" src="https://img.shields.io/badge/Lizenz-alle%20Rechte%20vorbehalten-6D3FD9">
</p>

<p align="center">
  <a href="https://medupro.de/tomato-installer/">Webseite</a> ·
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

## Wozu

Für einen neuen Arbeitsplatz gibt es bisher drei übliche Wege, den tomedo-Client auf den Mac zu bekommen:

- den Ordner mit tomedo (und Arzeko) von einem vorhandenen Mac kopieren,
- den Client in den Server-Tools unter *Aktionen → Update* herunterladen,
- `http://<server>:8080/tomedo_live/filebyname/serverinternal/tomedo.app.tar` im Browser
  aufrufen und das Archiv entpacken.

Danach muss tomedo an seinen Platz und die Serveradresse eingetragen werden. Arzeko fragt
beim ersten Start ebenfalls nach der Serveradresse
([Handbuch](https://support.tomedo.de/handbuch/arzeko/allgemeines/tomedo-einbinden/)).

Tomato-Installer nimmt den dritten Weg und erledigt den Rest gleich mit:

- sucht im Praxisnetz nach tomedo-Servern und zeigt sie in einer Liste
- lädt tomedo und auf Wunsch Arzeko vom gewählten Server, also die Version, die dort läuft
- legt beide in `~/Applications` des angemeldeten Benutzers ab
- trägt die Serveradresse für tomedo und Arzeko ein
- legt beide auf Wunsch ins Dock
- braucht kein Administratorpasswort
- überspringt Apps, die schon installiert sind
- prüft den Arzeko-Download per SHA-512

Die App überträgt keine Daten an MeduPro oder Dritte, sie spricht nur mit dem gewählten
tomedo-Server. Updates holt sich tomedo danach wie gewohnt selbst.

## Voraussetzungen

- macOS 14 Sonoma oder neuer, Apple Silicon oder Intel
- Der Mac erreicht den tomedo-Server (Praxisnetz oder VPN)

## Installation

1. **Tomato-Installer** kostenlos auf **[medupro.de/tomato-installer](https://medupro.de/tomato-installer/)** herunterladen und das DMG öffnen.
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
3. **Installieren**, danach **tomedo öffnen**.
4. In tomedo unter *Einstellungen → Arbeitsplatz → Grundeinstellungen* den Arbeitsplatz
   auswählen oder anlegen ([Handbuch](https://support.tomedo.de/handbuch/tomedo/praxisverwaltung/arbeitsplatz/)).
   Arzeko startet aus tomedo über *Aktion → Arzeko – Arbeitszeitkonto*.

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
- **„Server nicht erreichbar“:** Startet ein Download, wenn man
  `http://<server>:8080/tomedo_live/filebyname/serverinternal/tomedo.app.tar` im Browser aufruft?
  Wenn nicht, ist der Server von diesem Mac aus nicht erreichbar.
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
