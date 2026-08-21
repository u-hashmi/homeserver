# 00 — Hardware prep

## What you have

| Part | Spec | Verdict |
|------|------|---------|
| CPU | i5-7500T, 4C/4T, 35 W, Skylake | Fine. Intel HD 630 = QuickSync (H.264 + HEVC 8-bit) |
| RAM | 8 GB | **Tight.** Works, but see below |
| Boot disk | 256 GB SSD | Enough for OS + configs + databases. Not for media |
| Bulk disk | 1 TB external USB3 | Media + Nextcloud files + backups |

## Strongly recommended: 16 GB RAM

The M910q Tiny has **two SODIMM slots, DDR4-2400, 32 GB max**. Full stack idles at
roughly 3.5–4 GB; a single Plex transcode plus Nextcloud PHP workers will push an
8 GB box into swap.

- Buy: 2× 8 GB DDR4-2400 SODIMM (~$25–35 used). Or 1× 8 GB alongside the existing
  stick if it's a single 8 GB module.
- Everything in this repo runs on 8 GB. If you stay at 8 GB, skip the `ops` stack
  and Bazarr, and expect Plex direct-play only.

## Optional: internal 2.5" SATA drive

There's a 2.5" bay next to the M.2 slot. Populating it needs Lenovo's SATA
cable + bracket kit (part often sold as "M910q 2.5 inch HDD cable"), which is
usually missing from used units. A 2 TB 2.5" SATA SSD in that bay is a better home
for media than USB — but the 1 TB external works fine, so treat this as later.

## Check what's actually installed

From Windows, before you wipe:

```powershell
Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel,Capacity,Speed,Manufacturer
Get-PhysicalDisk | Select-Object FriendlyName,MediaType,Size,BusType
```

Same question after Debian is installed:

```bash
sudo dmidecode -t memory | grep -E 'Size|Speed|Locator|Part Number'
```

What you are looking for is whether the 8 GB is **1 x 8 GB** (one slot free — add a
second 8 GB stick) or **2 x 4 GB** (both slots full — you replace the pair). Either
way this is not a decision you need to make before building: the RAM upgrade is a
stick swap and a reboot, with no configuration change anywhere in this repo.

## BIOS settings (F1 at boot)

| Setting | Value | Why |
|---------|-------|-----|
| After Power Loss | **Power On** | Server comes back by itself after an outage |
| Wake on LAN | **Enabled (Primary)** | Remote power-on |
| Intel VT-x / VT-d | Enabled | Containers don't need it, but keep options open |
| Secure Boot | Leave **Enabled** | Debian 13 signs its kernel; no reason to disable |
| Boot mode | UEFI only | |
| Automatic Boot Sequence / USB boot | Enabled | So you can boot the Debian installer |
| Fan control / Thermal | Best Performance | 35 W chip in a 1 L case running 24/7 |

Set a BIOS supervisor password while you're in there, and note it somewhere.

## Physical

- Put the 1 TB drive on a **rear USB 3.0 port** (blue) — front ports share a
  controller and are easier to knock loose. This drive is permanent; the fstab entry
  is `nofail` but the media stacks will not start cleanly without it.
- Wired ethernet, not Wi-Fi. The Kalshi bot cares about latency and jitter.
- Give it a static DHCP reservation in your router *now* and write the IP down —
  every doc below refers to it as `192.168.1.50`. Replace with yours.
