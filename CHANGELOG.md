# Änderungen

## 1.0.3 – 23.11.2026

- Download lädt nach einem Verbindungsabbruch ab der erreichten Stelle weiter, bis zu sechs Versuche. Vorher war der ganze Download (tomedo rund 1,8 GB) bei jeder kurzen Unterbrechung verloren.
- Der Mac geht während der Installation nicht in den Ruhezustand.
- Protokoll unter `~/Library/Logs/MeduPro Mac-Installer.log`; die Fehlermeldung nennt Ursache, erreichte Größe und Zahl der Versuche.
- Selbstaktualisierung: Beim Start prüft der Installer die GitHub-Releases, lädt eine neuere Fassung (SHA-256 geprüft), ersetzt sich und startet neu.

## 1.0.0 – unveröffentlicht

- Erste Version: tomedo und optional Arzeko vom eigenen tomedo-Server installieren
- Automatische Suche nach tomedo-Servern im Praxisnetz, Auswahl per Liste
- Sofortige Serverprüfung bei der Eingabe
- Fortschritt je Schritt mit Download-Anzeige, Abbrechen und erneut versuchen
- SHA-512-Prüfung des Arzeko-Downloads
- Atomare Ablage in ~/Applications, vorhandene Apps bleiben unangetastet
- Serveradresse für tomedo und Arzeko, Dock-Eintrag (abschaltbar)
- Hinweise auf medupro.de und support@medupro.de, Support-Mail mit Fehlerdetails
