# razersocks

Print the battery level (state of charge) of a Razer wireless mouse on macOS.
One small native binary, no dependencies, no background process.

```console
$ razersocks
╭────────────────────╮
│████████████████    ├▌ 84%
╰────────────────────╯
Viper V3 Pro (discharging)
```

Not affiliated with Razer Inc.

## Install

```sh
brew install bramvanoost/tap/razersocks
```

From source (Xcode 15 or later):

```sh
git clone https://github.com/bramvanoost/razersocks.git
cd razersocks
sudo make install
```

Runs on macOS 12 or later, Apple Silicon and Intel.

## Permission

macOS treats mice as input devices, so the app that runs `razersocks` needs Input Monitoring:

1. Open **System Settings > Privacy & Security > Input Monitoring**.
2. Enable your terminal. Not listed? Click **+** and add it. For a status bar, enable that app (for example SketchyBar) instead.
3. Quit that app fully (Cmd+Q) and reopen it. Closing the window is not enough.

`razersocks` only sends battery queries. It does not read movement, clicks or keys.

## Usage

| Option | Output |
|---|---|
| none | The battery drawing above |
| `-q`, `--quiet`, `--raw` | `84` |
| `-j`, `--json` | `{"device":"Razer Viper V3 Pro","pid":"0x00c1","battery":84,"charging":false,"connection":"wireless"}` |
| `-a`, `--all` | Every connected supported device (an array with `--json`) |
| `-v`, `--version` | Version |
| `-h`, `--help` | Help |

| Exit code | Meaning |
|---|---|
| 0 | Success |
| 1 | No supported Razer device found |
| 2 | Device found, but asleep, unreachable or busy |
| 3 | Input Monitoring permission denied |
| 64 | Invalid usage |

Errors go to stderr, so stdout stays empty on failure.

In a terminal the battery fills up in green, yellow (30% or less) or red (10% or less). Piped output has no color or animation. Set `NO_COLOR` to turn the color off.

### tmux

```tmux
set -g status-interval 60
set -g status-right '#(razersocks -q 2>/dev/null)%'
```

### SketchyBar

`~/.config/sketchybar/plugins/razer.sh` (make it executable):

```sh
#!/bin/sh
if level=$(razersocks -q 2>/dev/null); then
  sketchybar --set "$NAME" drawing=on label="$level%"
else
  sketchybar --set "$NAME" drawing=off
fi
```

`sketchybarrc`:

```sh
sketchybar --add item razer right \
           --set razer update_freq=120 updates=on script="$CONFIG_DIR/plugins/razer.sh"
```

## Supported devices

| Device | Product ID | Connection |
|---|---|---|
| Razer Viper V3 Pro | `0x00C0` | Wired |
| Razer Viper V3 Pro | `0x00C1` | Wireless dongle |

### Adding a device

1. Find the product IDs. Run this once with the cable and once with the dongle:
   ```sh
   hidutil list --matching '{"VendorID":0x1532}'
   ```
2. Add one row per product ID to `Sources/RazerSocksCore/DeviceTable.swift`. The transaction ID is usually `0x1F` on recent mice. `0x3F` and `0xFF` are tried automatically if the device rejects it.
3. Run `swift run razersocks --json` and paste the output in your pull request.
4. Add the device to the table above.

## Development

```sh
make test        # unit tests, no hardware needed
make universal   # arm64 + x86_64 binary in dist/
make dist        # archive and SHA-256 checksum
```

To release, set `CLI.version`, then push a matching tag such as `v0.1.0`.

## License

MIT
