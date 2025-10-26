# 🎮 Arcade / Beamer / Steam Automations-Setup

## Ziel
Dieser Rechner kann per **MQTT** aus Home Assistant in den **„Zocken“-Modus** gebracht werden.

Dabei passiert automatisch:

1. Die **Arcade-Session** wird sichtbar gemacht (`tscon`)
2. **Anzeige & Audio** werden auf den **Beamer** umgestellt
3. **Steam Big Picture** wird im Benutzerkontext *Arcade* gestartet
4. Beim Ausschalten wird alles wieder sauber zurückgesetzt
5. Zum Schluss wird die **Arcade-Session getrennt**, sodass wieder der Login-Bildschirm erscheint

Der Hauptnutzer bleibt **sicher getrennt**.  
Der Rechner kann dauerhaft laufen und *Arcade* kann im Hintergrund eingeloggt bleiben.

---

## Benutzer / Sessions

| Benutzer | Zweck | Status |
|---|---|---|
| **Arcade** | Spiel-Desktop | Bleibt dauerhaft angemeldet (meist „Getr.“) |
| **Hauptnutzer** | Normalarbeiten / Admin | Taucht nach `disable` wieder am Login-Screen auf |

Falls nötig: Autologon für *Arcade* → `Autologon.exe` (Sysinternals).

---

## Ablaufsteuerung

| Schritt | Wer führt es aus | Wie |
|---|---|---|
| Session sichtbar machen | SYSTEM | `tscon <SID> /dest:console` |
| Anzeige + Audio setzen | SYSTEM **in** Arcade-Session | `PsExec -i <SID> -s zocken.ps1 -Enable -NoSteam` |
| Steam starten | Arcade (User-Kontext) | `schtasks /Run /TN "Arcade-StartSteam"` |
| Ausschalten | Arcade & SYSTEM | `Arcade-StopSteam` + `zocken.ps1 -Disable -NoSteam` |
| Zurück zum Login-Screen | SYSTEM in Arcade-Session | `PsExec -i <SID> -s tsdiscon` |

---

## Dateien

| Datei | Zweck |
|---|---|
| `zocken.ps1` | Schaltet Display + Audio (optional Steam) |
| `Start-ZockenListener.ps1` | MQTT Listener + gesamte Ablaufsteuerung |
| `start-steam.ps1` | Startet Steam Big Picture (Arcade-Kontext) |
| `stop-steam.ps1` | Stoppt Steam (Arcade-Kontext) |

---

## Scheduled Tasks (müssen existieren)

| Taskname | Benutzer | Ruft auf |
|---|---|---|
| `Arcade-StartSteam` | **Arcade** | `start-steam.ps1` |
| `Arcade-StopSteam`  | **Arcade** | `stop-steam.ps1` |
| `Start-ZockenListener` | **SYSTEM** (beim Systemstart) | `Start-ZockenListener.ps1` |

---

## MQTT

| Topic | Payload | Wirkung |
|---|---|---|
| `windows/klose-xmg/zocken` | `enable` | Zocken **AN** |
| `windows/klose-xmg/zocken` | `disable` | Zocken **AUS** |

---

## Sequenzen

### `enable`
```
Arcade-SID ermitteln
tscon <SID> /dest:console
zocken.ps1 -Enable -NoSteam
schtasks /Run /TN "Arcade-StartSteam"
```

### `disable`
```
schtasks /Run /TN "Arcade-StopSteam"
zocken.ps1 -Disable -NoSteam
tsdiscon   # zurück zum Login
```

---

## Fazit
✅ Hauptbenutzer bleibt geschützt  
✅ Arcade läuft sichtbar für Spiele  
✅ Start/Stop zuverlässig per MQTT  
✅ Rückkehr zum Login nach dem Spielen automatisiert  


# Home Assistant Integration – Zocken Modus

Der PC kann über MQTT aus Home Assistant gesteuert werden.

## MQTT Topics

| Topic | Payload | Beschreibung |
|---|---|---|
| `windows/klose-xmg/zocken` | `enable` | Aktiviert den Zocken-Modus |
| `windows/klose-xmg/zocken` | `disable` | Deaktiviert den Zocken-Modus |

## Home Assistant: Schalter einrichten

**Einstellungen → Geräte & Dienste → MQTT → Gerät hinzufügen → Manuell**

1. Gerät anlegen, z. B. Name: `klose-xmg Gamemode`
2. Entität hinzufügen → **Art der Entität: Schalter**

Dann folgende Werte setzen:

| Feld | Wert |
|---|---|
| **Command Topic** | `windows/klose-xmg/zocken` |
| **Payload einschalten** | `enable` |
| **Payload ausschalten** | `disable` |
| **Retain** | aus |

Speichern → Fertig.

Nun gibt es in Home Assistant die Entität:

```
switch.klose_xmg_gamemode
```

## Beispiel Automation

```yaml
alias: Zocken nach Beamer-Einschalten
trigger:
  - platform: state
    entity_id: switch.beamer
    to: "on"
action:
  - service: switch.turn_on
    target:
      entity_id: switch.klose_xmg_gamemode
```

## 🧠 Automationen Übersicht

### 🎬 HE Sync – Film & Spiele (Harmony ⇆ Gamemode ⇆ Beamer)
Hält **Harmony-Aktivität**, **Beamer-Helper** und **Gamemode/XMG** sauber synchron.
- Erkennt Zustände ausschließlich über `current_option_changed` der Harmony-Select-Entität.
- Schaltet XMG **nur**, wenn das wirklich nötig ist (idempotent).
- Verhindert Endlos-Schleifen mittels `media_sync_guard`.

**Datei:** `automations/he_sync_final_ha_compatible.yaml`  
*(oder in Home Assistant unter den Automationen importiert)*

**Ablauf (vereinfacht):**
| Auslöser | Ergebnis |
|---|---|
| Apple TV → Beamer | Beamer-Helper **AN**, Gamemode **AUS**, XMG **AUS** |
| Computer → Beamer | Gamemode **AN**, Beamer **AUS**, XMG **AN** |
| Harmony PowerOff | Gamemode **AUS**, Beamer **AUS**, XMG **AUS** |
| Manuelle Helper-Änderung | Harmony wird bei Bedarf nachgezogen |

---

### 💡 Lichtsteuerung – Film & Gaming
Steuert automatisch die passende Lichtstimmung abhängig von Film, TV oder Gaming.

**Datei:** `automations/light_sync.yaml`

**Ablauf (vereinfacht):**
| Auslöser | Szene |
|---|---|
| Film startet (Apple TV → Beamer) | `scene.kinolicht` (mit Verzögerung) |
| Film endet / zurück zum TV | `scene.entspannen` |
| Gamemode wird aktiviert | `scene.gaming` |

*(Aktiv nur bei Dunkelheit: nach Sonnenuntergang bis vor Sonnenaufgang mit Offset)*

---
