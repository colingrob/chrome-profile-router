# Setting this up for someone

When asked to set up Chrome deep-link routing:

1. Confirm this is macOS and check for Chrome, `xcrun swiftc`, Python 3, and OpenSSL. Install missing Apple command line tools through their normal installer if requested.
2. Read `README.md`. Build and install with `bash scripts/install.sh`. If an older copy of the router is running, quit it before updating.
3. Open `~/Applications/Chrome Profile Router.app`. Set it as the default browser through System Settings → Desktop & Dock → Default web browser. Verify the app says **Routing external links**.
4. Test an ordinary external web link. Verify that the picker lists the user's actual profiles and the chosen profile receives the link. Don't use real login tokens for a test.
5. The Chrome extension is optional. Load the installed support-folder copy through Chrome's **Load unpacked** UI if the user wants toolbar or right-click actions. Never edit Chrome's protected preference files to force-install it. Respect browser automation restrictions and tell the user if that step needs manual interaction.
6. Leave the router installed, remove any disposable test rules you created, and explain how to change or forget a choice.

Only the `http` and `https` default handlers should change. Do not alter credentials, browser profiles, bookmarks, or unrelated protocol handlers. No database or cloud access is needed.

## Code

The app is Swift/AppKit with a SwiftUI view. `RouterCore.swift` contains URL validation, profile discovery, and rule persistence. The extension uses Manifest V3 and a small native messaging helper. There are no package dependencies.

Run `bash scripts/build.sh` and `bash scripts/test.sh` after changes. Keep full URLs out of persistent state and logs. Preserve the public extension key in `extension/manifest.json`, because it keeps the extension ID stable across installations.
