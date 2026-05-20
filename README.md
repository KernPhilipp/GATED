# GATED

Garage Access Technology for Entry Detection

GATED ist eine Flutter-Web/PWA-App fuer Garagenzugang, Kennzeichenverwaltung
und Torsteuerung im lokalen Netzwerk. Die App wird am Raspberry Pi gehostet und
von Geraeten im gleichen Netzwerk ueber den Browser geoeffnet.

## Bestandteile

- `gated`: Flutter Web/PWA Frontend
- `gated/backend`: Dart Shelf Backend
- `deploy`: Raspberry Pi Deployment
- `informationen`: interne Projekt- und Betriebsnotizen

## Kernfunktionen

- Login und Registrierung ueber erlaubte E-Mail-Adressen
- Adminbereich fuer Nutzer und erlaubte E-Mails
- Kennzeichenverwaltung mit Live-Aktualisierung
- Dashboard fuer sensorbasierten Garagentorstatus und Torsteuerung

## Weiterfuehrende Doku

- Lokale Befehle: `informationen/Befehle.txt`
- Projektfakten: `informationen/Informationen.txt`
- Raspberry Pi Setup: `informationen/PiSetupBefehle.txt`
- Deployment-Konzept: `deploy/README.md`

Echte Secrets, lokale Datenbanken und Runtime-Dateien werden nicht committed.
