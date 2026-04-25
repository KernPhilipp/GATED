# GATED

Garage Access Technology for Entry Detection

GATED ist eine Flutter-Web-App fuer Garagenzugang, Kennzeichenverwaltung und
Torsteuerung im lokalen Netzwerk.

## Bestandteile

- `gated`: Flutter Frontend
- `gated/backend`: Dart Shelf Backend
- `deploy`: Raspberry Pi Deployment
- `informationen`: interne Projekt- und Betriebsnotizen

## Kernfunktionen

- Login und Registrierung ueber erlaubte E-Mail-Adressen
- Adminbereich fuer Nutzer und erlaubte E-Mails
- Kennzeichenverwaltung mit Live-Aktualisierung
- Dashboard fuer Garagentorstatus und Torsteuerung

## Weiterfuehrende Doku

- Lokale Befehle: `informationen/Befehle.txt`
- Projektfakten: `informationen/Informationen.txt`
- Raspberry Pi Setup: `informationen/PiSetupBefehle.txt`
- Deployment-Konzept: `deploy/README.md`

Echte Secrets, lokale Datenbanken und Runtime-Dateien werden nicht committed.
