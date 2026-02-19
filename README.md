# QuickTray 📥

**QuickTray** is a lightweight, native macOS menu bar application that acts as a smart shelf for your clipboard history. It automatically captures text and images, allowing you to drag and drop them back into any application or pin important items for later use.

## Features ✨

*   **Clipboard History:** Automatically saves copied text and images.
*   **Smart Previews:**
    *   **Text:** Shows a concise preview of copied text.
    *   **Images:** Displays high-quality thumbnails.
*   **Drag & Drop:** Drag items directly from the menu bar list into other apps (Finder, Mail, Messages, etc.).
*   **Pinning:** Pin important items to the top of the list so they're always accessible. 📌
*   **Semantic Recall Search:** Find old clipboard text by meaning, not just exact words, with local on-device ranking.
*   **Configurable Retention:** Set how many unpinned items to keep; pinned items are never evicted by the history limit.
*   **Persistence:** Your history and pinned items are saved across app restarts.
*   **Management:** Delete individual items or clear the entire history with a single click.
*   **Native Design:** Built with SwiftUI for a seamless macOS experience (supports macOS 13+).

## Installation 🚀

1.  Clone this repository.
2.  Run the build script:
    ```bash
    ./build.sh
    ```
3.  The app will be created in the `build/` directory. Move `QuickTray.app` to your `/Applications` folder.

### Opening on other Macs (Important!) ⚠️

Since this app is not notarized by Apple (which requires a paid developer account), macOS may block it from opening or say the app is "damaged" when you download it.

**To open the app:**

1.  **Right-click** (or Control-click) on `QuickTray.app`.
2.  Select **Open** from the menu.
3.  Click **Open** in the confirmation dialog.

You only need to do this once.

**If that doesn't work:**
Open your Terminal and run this command to remove the quarantine restriction:

```bash
xattr -cr /path/to/QuickTray.app
```

## Usage 💡

1.  Launch **QuickTray**. It will appear in your menu bar (tray icon).
2.  **Copy** text or images as usual. They will automatically appear in QuickTray.
3.  **Click** the tray icon to view your history.
4.  **Drag** an item out to paste it, or use the **Copy** button to put it back on your clipboard.
5.  **Pin** items you use frequently.
6.  Use **Keep X unpinned** in the header to control FIFO retention for unpinned history.
7.  Use the **search bar** to find older copied text semantically (for example, related phrases with different wording).

## Development 🛠️

*   **Language:** Swift 5+
*   **Framework:** SwiftUI, AppKit
*   **Architecture:** MVVM

To build from source:

```bash
cd QuickTray
./build.sh
```

## License 📄

MIT License. See [LICENSE](LICENSE) file for details.
