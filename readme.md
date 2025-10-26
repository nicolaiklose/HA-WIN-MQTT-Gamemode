# 🎮 Arcade / Windows / Projector / Steam / Home Assistant - Automation Setup

> **Important Note:**  
> I am **not a programmer**.  
> The **majority of the code and logic in this project was generated with the assistance of *ChatGPT‑5***.  
> My primary contribution was the **concept, integration work, testing, troubleshooting, and guiding the Chat GPT** to produce a working solution.  
> This repository should be viewed as **inspiration or reference**, *not* as production‑ready or generally reusable code.  
> The implementation is **highly specific** to my environment and use case.

This project provides a **fully automated gaming mode** for a Windows PC that can be controlled from **Home Assistant via MQTT**.  
When Gaming Mode is enabled, the system switches to a dedicated **Arcade user session**, routes **audio and display to a projector**, and starts **Steam Big Picture**.  
When Gaming Mode is disabled, everything is reliably reverted and the system returns to a **locked login screen**, keeping the main desktop isolated and secure.

---

## 🎯 Goals

- Use a separate **Arcade account** for gaming, isolated from the main user
- Automatically switch **display and audio output** to a projector
- Reliably start & stop **Steam Big Picture**
- Control the whole workflow using **MQTT** from Home Assistant
- Keep the system secure and stable even when left running continuously

---

## 👤 Users / Sessions

| User | Purpose | Behavior |
|---|---|---|
| **Arcade** | Dedicated gaming desktop | Stays logged in (often disconnected) |
| **Main User** | Normal desktop usage | Restored when Gaming Mode is disabled |

If needed: Auto‑login for *Arcade* via `Autologon.exe` (Sysinternals).

---

## 🔄 Execution Flow (High‑Level)

| Step | Context | Method |
|---|---|---|
| Make Arcade session visible | SYSTEM | `tscon <SID> /dest:console` |
| Switch display & audio | SYSTEM **inside** Arcade session | `PsExec -i <SID> -s zocken.ps1 -Enable -NoSteam` |
| Launch Steam Big Picture | Arcade user | `schtasks /Run /TN "Arcade-StartSteam"` |
| Stop Steam | Arcade user | `schtasks /Run /TN "Arcade-StopSteam"` |
| Return to login screen | SYSTEM | `tsdiscon` |

---

## 📂 File Overview

| File | Purpose |
|---|---|
| `zocken.ps1` | Switch display & audio, optionally control Steam |
| `Start-ZockenListener.ps1` | MQTT listener & state controller |
| `start-steam.ps1` | Starts Steam Big Picture (Arcade session) |
| `stop-steam.ps1` | Stops Steam (Arcade session) |

---

## 🗓 Required Scheduled Tasks

| Task Name | Runs As | Calls |
|---|---|---|
| `Arcade-StartSteam` | Arcade user | `start-steam.ps1` |
| `Arcade-StopSteam` | Arcade user | `stop-steam.ps1` |
| `Start-ZockenListener` | SYSTEM (boot) | `Start-ZockenListener.ps1` |

---

## 📡 MQTT Topics

| Topic | Payload | Action |
|---|---|---|
| `windows/klose-xmg/zocken` | `enable` | Activate Gaming Mode |
| `windows/klose-xmg/zocken` | `disable` | Deactivate Gaming Mode |

---

## 🏠 Home Assistant Integration (Example)

```yaml
switch:
  - platform: mqtt
    name: "XMG Gaming Mode"
    command_topic: "windows/klose-xmg/zocken"
    payload_on: "enable"
    payload_off: "disable"
    retain: false
```

Entity created:
```
switch.xmg_gaming_mode
```

---

## 🧠 Key Challenges Solved

- Balancing **SYSTEM vs. User session** execution requirements
- Ensuring the Arcade session is **visible and interactive**
- Starting Steam Big Picture **reliably via Scheduled Tasks**
- Switching display and audio **inside the correct session**
- Running an MQTT listener **headless at system boot**
- Preventing **automation feedback loops** in Home Assistant
- Handling PsExec permissions, paths, and session visibility

---

## ⚠️ Disclaimer

- The code is **not written or engineered by hand** — it was created using **ChatGPT‑5**.
- I am **not a software developer** — this was created through iterative refinement.
- **Do NOT copy this setup 1:1** — it is highly dependent on:
  - my hardware
  - my projector & audio routing
  - my Windows user/session layout
  - my Home Assistant automation logic

This project is best used as a **learning reference** or **starting point**, not a drop‑in solution.

---

## ✅ Result

- Main desktop stays secure
- Arcade session provides a clean gaming environment
- One MQTT command controls the full experience
- System always resets back to a safe login state

---

**Created, refined, tested, and debugged with the assistance of _ChatGPT‑5_.**
