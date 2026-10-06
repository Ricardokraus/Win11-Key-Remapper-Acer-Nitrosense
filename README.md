<p align="center">
  <img src="assets/banner.svg" alt="Windows 11 Key Remapper - NitroSense Key Remapper" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense?color=30D158&label=release"></a>
  <a href="https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/total?color=30D158"></a>
  <img alt="Windows 10 | 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4">
  <a href="https://www.autohotkey.com/"><img alt="AutoHotkey v2" src="https://img.shields.io/badge/AutoHotkey-v2-334455?logo=autohotkey&logoColor=white"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense?color=blue"></a>
</p>

<h3 align="center">
  Keep hitting the NitroSense key instead of Num Lock or Backspace?<br>
  Turn it into Num Lock, disable it, or remap it — a small, free AutoHotkey app.
</h3>

<p align="center">
  <a href="#installation"><b>Get started</b></a> ·
  <a href="#features"><b>Features</b></a> ·
  <a href="#faq"><b>FAQ</b></a> ·
  <a href="#help-and-contributing"><b>Help and contributing</b></a>
</p>

On Acer Nitro laptops the **NitroSense key** sits right next to Backspace and
Num Lock. One slip and the NitroSense app pops up. **Windows 11 Key Remapper**
is a tiny tray app that gives that key a better job — or any other key you pick.

<!-- Demo GIF: record with ScreenToGif, save as assets/demo.gif, then use it in
     place of the screenshot below.
<p align="center"><img src="assets/demo.gif" alt="The app's notifications" width="760"></p>
-->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshot-dark.png">
    <img src="assets/screenshot-light.png" alt="The settings window, Keys section: the key to remap, what it does and the shortcut that opens NitroSense" width="760">
  </picture>
</p>

---

<a name="installation"></a>
## 🚀 Get started

The app is an [AutoHotkey v2](https://www.autohotkey.com/) script. AutoHotkey is
free, open source and signed, so it also runs with Windows 11's *Smart App
Control* on. (There's no exe for now: [why?](#why-no-exe))

1. Install [AutoHotkey v2](https://www.autohotkey.com/) (*Download v2.0* → run
   the installer, default options).

2. Download `Win11KeyRemapper-vX.Y.Z.zip` from the
   [latest release](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/latest)
   and extract it to a folder you'll keep, for example `Documents\Win11KeyRemapper`
   (not *Downloads*: *Start with Windows* points to wherever the app is).

3. Double-click **`src\Win11KeyRemapper.ahk`**.

4. The settings window opens on *Keys*. Pick what the NitroSense key should do —
   changes apply at once. *Start with Windows* is already on. Close the window:
   the app lives in the tray. Double-click its icon, or open the app again, to
   come back.

Everything is changed from the settings window. If you'd rather edit a text file,
`src\settings.ini` explains every option inside it (open it from *Settings* →
*Advanced* → *Open folder*), and [`settings.example.ini`](settings.example.ini)
shows them all with their defaults.

<a name="features"></a>
## ✨ Features

<details>
<summary><b>See all features</b></summary>
<br>

- **Remap the NitroSense key** (or any key) to another key or shortcut — **Num
  Lock** by default — or make it do nothing.

- **Holding it toggles Num Lock once** (or Caps / Scroll Lock), not over and
  over; other keys repeat like the real key.

- **Built-in key detector**: click *Change…*, press a key or a combination, done.

- **A shortcut to open NitroSense** (default: <kbd>Right Ctrl</kbd> + NitroSense
  key). It finds the app by itself, Microsoft Store version included, or opens any
  app you choose.

- **Windows 11 style settings**: a sidebar with sections, **light and dark
  mode**, changes applied at once, small animations, sharp on every monitor.

- **Notifications your way**: always (at startup, after unlocking, when the
  screen turns on), only at startup, or never; six positions, three animations,
  frosted glass or solid.

- **A tiny tray menu** (settings, pause, restart, exit), or **no tray icon** at
  all.

- **Tells you about new versions**: checks GitHub once a day (you can turn it
  off).

- **Light**: no admin rights, no driver, no service, no CPU use while idle.

- **Free and open source** (MIT).

</details>

<a name="updating"></a>
## 🔄 Updating and uninstalling

<details>
<summary><b>How to update</b></summary>
<br>

When there's a new version, the app tells you (*Settings* → *Updates*), and
*Download* opens the release page. Then:

1. Click *Exit* in the app (settings → *General* → *App*, or tray icon → *Exit*).

2. Download the new zip and extract it **over the same folder**, replacing the
   files. Your `settings.ini` isn't in the zip, so it stays.

3. Double-click `src\Win11KeyRemapper.ahk` again.

</details>

<details>
<summary><b>How to uninstall</b></summary>
<br>

1. In the settings (*General*), turn off *Start with Windows*.

2. Click *Exit* under *App* (or tray icon → *Exit*).

3. Delete the app's folder, and `%APPDATA%\Win11KeyRemapper` if it exists.
   Nothing else is installed.

If you don't use AutoHotkey for anything else, you can uninstall it from
Windows' *Installed apps*.

</details>

<a name="faq"></a>
## ❓ FAQ

<a name="why-no-exe"></a>
<details>
<summary><b>Q: Why do I need AutoHotkey? Is there an exe?</b></summary>
<br>

**A:** Not for now. An exe made from an AutoHotkey script isn't code-signed, and
Windows 11's *Smart App Control* blocks unsigned apps it doesn't know, with no
*Run anyway* button (turning it off affects the whole PC, and often can't be
undone without reinstalling Windows). AutoHotkey itself is signed, so the script
runs everywhere, and you can read exactly what it does. A signed exe that installs
and updates itself is planned.
</details>

<details>
<summary><b>Q: My antivirus warns about it</b></summary>
<br>

**A:** This app installs a keyboard hook, which is also what keyloggers do, so a
heuristic scanner may flag it. It's a false positive: the whole app is the
readable script in `src\`, it never stores or sends your keys (see
[SECURITY.md](SECURITY.md)), and every release has a `SHA256SUMS.txt` you can
compare with `Get-FileHash` on the zip you downloaded.
</details>

<details>
<summary><b>Q: It doesn't work while Task Manager is focused</b></summary>
<br>

**A:** Windows doesn't pass keystrokes to apps without admin rights while an app with
admin rights (like Task Manager) is in the foreground. That's a Windows security
rule (UIPI). This app deliberately runs without admin rights so it can start
silently at logon. Click any normal window and it works again.
</details>

<details>
<summary><b>Q: What does <i>Exact key match</i> do?</b></summary>
<br>

**A:** Some vendor keys share the same virtual-key code. On Acer laptops, turning Win
Lock on and off (<kbd>Fn</kbd>+<kbd>Win</kbd>) sends the NitroSense key's code
(`VK FF`) with other scan codes (`159` and `162`). With *Exact key match* on (the
default), the scan code must match too, so only the NitroSense key (`175`) is
remapped and Win Lock works as usual. The switch is in Settings → *Advanced*.
</details>

<details>
<summary><b>Q: I hid the tray icon. How do I open the settings?</b></summary>
<br>

**A:** Open the app again (double-click `src\Win11KeyRemapper.ahk`). Instead of
starting a second copy, the running one shows its settings window, where you can
turn the icon back on.
</details>

<details>
<summary><b>Q: Does it connect to the internet?</b></summary>
<br>

**A:** Only to check for updates: once a day it asks GitHub's API for the latest release
(nothing about you or your keys is sent). Turn off *Check for updates
automatically* in Settings → *Updates* to stop it; *Check now* still works on demand.
It never downloads anything by itself: *Download* opens the release page in your
browser.
</details>

<details>
<summary><b>Q: The Acer Num Lock / Caps Lock pop-up still shows</b></summary>
<br>

**A:** That overlay comes from Acer Quick Access, which NitroSense needs. It's outside
this app's control.
</details>

<details>
<summary><b>Q: Does it work on other laptops or keyboards?</b></summary>
<br>

**A:** Yes, for any key that reaches Windows as a key press: open the settings, go to
*Keys*, click *Change…* next to *Key* and press it. Keys handled entirely by the firmware (like
<kbd>Fn</kbd> itself) never reach Windows and can't be remapped.
</details>

<details>
<summary><b>Q: The notification stutters on my old or low-power PC</b></summary>
<br>

**A:** The frosted glass takes a capture of the screen behind the notification and
blurs it, each time it appears. Turn off *Transparency effects* in Settings →
*Notifications*: you get a solid card in the settings window's colors, with no
capture at all. Or set *Show notifications* to *Only when the app starts* or
*Never*.
</details>

<details>
<summary><b>Q: Where are my settings? Can I edit them by hand?</b></summary>
<br>

**A:** In `src\settings.ini`, next to `Win11KeyRemapper.ahk` (or in
`%APPDATA%\Win11KeyRemapper\settings.ini` when that folder isn't writable).
Settings → *Advanced* → *Open folder* takes you there. Every option is explained
inside the file. After editing it, restart the app (tray icon → *Restart*). The app
writes the file again when you change something in the settings window, so your
own comments in it are lost.
</details>

<details>
<summary><b>Q: How does it work?</b></summary>
<br>

**A:**

- The NitroSense key reports virtual-key code `0xFF` ("no mapping"), which
  AutoHotkey hotkeys can't target reliably. The app installs its own low-level
  keyboard hook (`WH_KEYBOARD_LL`) and matches each key by virtual-key code
  **and** scan code (with the extended bit).

- The matched key is swallowed, so neither Windows nor the vendor software sees
  it — otherwise both would react and Num Lock would toggle twice.

- Modifiers for the launcher shortcut are tracked by the hook itself.

- The hook never does real work: actions go to a queue that runs right after,
  because Windows silently removes hooks that respond too slowly. The hook is
  also reinstalled after unlocking and after sleep.

- Key-downs that arrive while the key is still held (auto-repeat) are passed on
  as repeats of the target, except for Num, Caps and Scroll Lock, so holding the
  key toggles them once.

- The settings window is standard Win32 with custom-drawn cards, buttons,
  keycaps, switches and sidebar, aware of each monitor's scale; the notification
  is drawn once with GDI+ and then only moved and faded by the window manager, so
  it costs next to nothing.

More details in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
</details>

## 💻 Tested models

| Laptop | Windows | Codes shown in the settings window | Status |
|---|---|---|---|
| Acer Nitro V 16S AI (ANV16S-41) | 11 | NitroSense key `VK FF SC 175` · Win Lock on `FF 159` / off `FF 162` | ✅ Works |

Tried it on another laptop? Please
[tell us how it went](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/issues/new?template=works_on_my_laptop.yml),
even if it didn't work — that's how this list grows.

---

<a name="help-and-contributing"></a>
## 💬 Help and contributing

Bugs, ideas, questions and code all go through GitHub. The same links are in the
app: settings window → *About*.

<details>
<summary><b>Report a bug, suggest an idea or ask a question</b></summary>
<br>

You need a free GitHub account.

1. Open the [Issues tab](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/issues)
   and search first: maybe someone already reported it. If so, add a 👍 or a
   comment with your details.

2. If not, click **New issue** and pick a form:

   - 🐞 **Bug report** — something doesn't work as expected.
   - 💡 **Feature request** — an idea or an improvement.
   - 💻 **Works on my laptop** — tell us whether it works on your model (even if it doesn't!).
   - ❓ **Question** — anything else.

3. Fill in the form and click **Create**. GitHub emails you when someone answers.

Found a security problem? Please report it privately instead — see
[SECURITY.md](SECURITY.md).

</details>

<details>
<summary><b>Contribute code or docs</b></summary>
<br>

Pull requests are welcome! [CONTRIBUTING.md](CONTRIBUTING.md) explains how to
test a change (syntax check and logic tests, the same ones GitHub Actions runs),
and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) how the app works and the traps
this project already fell into.

</details>

If the app helps you, a ⭐ helps others find it.

<a href="https://star-history.com/#Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense&type=Date&theme=dark">
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense&type=Date" width="600">
  </picture>
</a>

## 📄 License

[MIT](LICENSE) © 2026 Ricardo
