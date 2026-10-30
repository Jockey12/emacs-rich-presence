# Emacs Discord Rich Presence

A small Emacs Lisp client that displays the current buffer and project in Discord Rich Presence over Discord's local IPC socket.

## Features

- Shows the exact current buffer name and project name.
- Reconnects through Discord's local IPC interface and updates on buffer changes.
- Includes an Emacs-inspired icon (`assets/emacs-logo.svg`) for uploading as a Discord application asset.
- Designed for Doom Emacs, but the library can be loaded from any Emacs configuration.

## Discord setup

1. Create an application in the [Discord Developer Portal](https://discord.com/developers/applications) and copy its **Application ID**. The Public Key is not used.
2. In **Rich Presence → Art Assets**, upload `assets/emacs-logo.svg` (or a PNG export) with the asset key `emacs_logo`. The activity references this key as its large image.
3. In Discord **User Settings → Activity Privacy**, enable **Share your detected activities with others**. Use the desktop app and a visible status.

## Doom Emacs setup

Copy `discord-presence.el` into your Doom config directory, then add this to `~/.config/doom/config.el`:

```elisp
(load! "discord-presence")
(setq discord-presence-client-id "YOUR_APPLICATION_ID")
(discord-presence-mode 1)
```

Restart Emacs. Use `M-x discord-presence-status` to inspect the connection, or `M-x discord-presence-stop` / `M-x discord-presence-start` to control it.

The activity shows the exact buffer name as its details and the project directory's basename as its state. Buffers outside a project display `No project`.

## Logo notes

Discord application assets are registered in the Developer Portal, not served directly from the plugin. Upload the included SVG under the exact key `emacs_logo`; Discord may require a PNG upload depending on its current asset uploader.

## License

MIT. See [LICENSE](LICENSE).
