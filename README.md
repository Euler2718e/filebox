![FileBox](screenshot.png)

# FileBox

A minimal floating shelf for macOS that holds files, images, and links while you navigate to where they need to go.

Moving files across folders in Finder means juggling two windows at once. FileBox solves this by giving you a temporary holding space — pick something up, drop it in the shelf, navigate wherever you like, then drag it back out.

---

## How it works

FileBox lives in your menu bar and stays out of your way. The shelf only appears when you start dragging something — it detects an active drag and fades in at the top-right corner of your screen. Drop your file into it, navigate to the destination, then drag it back out.

Once files are in the shelf, it stays visible until you clear it.

---

## Features

- **Auto-shows on drag** — appears only when you're actively dragging a file, image, or URL; invisible otherwise
- **Accepts anything** — local files from Finder, images from browsers, web URLs, or anything draggable
- **Drag out to place** — drag items from the shelf directly into Finder, apps, or any drop target
- **Fixed position** — dragging files out never accidentally moves the window; grab the header strip to reposition it
- **Finder integration** — press ⌥G to instantly grab whatever is selected in Finder
- **No Dock icon** — lives quietly in the menu bar

---

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`)

---

## Installation

```bash
git clone https://github.com/jakob/FileBox
cd FileBox
bash build-app.sh
```

This builds a release binary, packages it as `FileBox.app`, and opens it. Drag it to `/Applications` to install permanently.

---

## Permissions

On first launch macOS will ask for **Input Monitoring** access (System Settings → Privacy & Security → Input Monitoring). This is required for the auto-show-on-drag feature. Without it, FileBox still works — use the menu bar icon or ⌥G to show it manually.

---

## Usage

| Action | Result |
|---|---|
| Start dragging a file anywhere | Shelf appears automatically |
| Drop onto shelf | File is stored |
| Drag from shelf | Pick the file back up |
| Hover a row | Reveal ✕ to remove |
| Click **Clear** in header | Empty the shelf |
| ⌥G | Grab current Finder selection |
| Menu bar icon | Manual show / clear / quit |

---

## License

MIT — see [LICENSE](LICENSE)
