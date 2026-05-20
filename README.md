# GATED

Garage Access Technology for Entry Detection

GATED ist eine Flutter-Web-App für Garagenzugang, Kennzeichenverwaltung und
Torsteuerung im lokalen Netzwerk.

## Bestandteile

- `gated`: Flutter Frontend
- `gated/backend`: Dart Shelf Backend
- `deploy`: Raspberry Pi Deployment
- `informationen`: interne Projekt- und Betriebsnotizen

## Kernfunktionen

- Login und Registrierung über erlaubte E-Mail-Adressen
- Adminbereich für Nutzer und erlaubte E-Mails
- Kennzeichenverwaltung mit Live-Aktualisierung
- Dashboard für Garagentorstatus und Torsteuerung

## Weiterführende Doku

- Lokale Befehle: `informationen/Befehle.txt`
- Projektfakten: `informationen/Informationen.txt`
- Raspberry Pi Setup: `informationen/PiSetupBefehle.txt`
- Deployment-Konzept: `deploy/README.md`

Echte Secrets, lokale Datenbanken und Runtime-Dateien werden nicht committed.
