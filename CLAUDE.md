# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`razersocks` is a macOS CLI that reads the battery level of Razer wireless mice over USB HID and exits. Swift, IOKit only, no dependencies. Public MIT project distributed through a Homebrew tap. The folder is `razersoc`, the product and GitHub repo are `razersocks`.

## Commands

```sh
make test                                   # unit tests, no hardware needed
swift test --filter BatteryReaderTests      # one class
swift test --filter CLITests/testRawOutput  # one test
swift run razersocks --json                 # run against the attached mouse
make universal                              # arm64 + x86_64 in dist/, via two builds and lipo
make dist                                   # tar.gz and SHA-256
```

Querying real hardware needs Input Monitoring for the terminal app. Without it every query exits 3.

## Architecture

Everything testable lives in `RazerSocksCore`. `Sources/razersocks/main.swift` only wires it to stdout, `usleep` and the permission prompt.

- `DeviceTable`: supported PIDs. Table order is display priority.
- `RazerProtocol`: pure packet building and reply parsing. A reply counts only if it echoes the transaction ID, class and command, because the device buffer can hold a stale reply or one meant for other software. The reply CRC is not checked.
- `BatteryReader`: retries, transaction ID fallback and interface probing, over the `FeatureReportTransport` protocol. Tests drive it with `FakeMouse`.
- `HIDTransport` / `HIDDiscovery`: the only IOKit code, not unit tested. Groups interfaces into devices by USB location and probes only interfaces that declare a feature report of 90 bytes or more.
- `CLI`: argument parsing, formatting, exit codes. Pure. JSON is hand-written to keep key order stable.

`.retry` and `.rejected` differ on purpose: `.rejected` moves on to the next transaction ID, `.retry` after three attempts ends that interface.

## Viper V3 Pro on macOS

The `0x00C1` dongle exposes three HID interfaces. Only the one with usage page 1, usage 2 declares a 90-byte feature report. `IOHIDDeviceOpen` returns `0xe00002e2` when Input Monitoring is denied.

## Release

`CLI.version` is the only version source, and the release workflow fails if the tag does not match it. `scripts/render-formula.sh` generates the formula, so change the formula there. `Formula/razersocks.rb` is a rendered sample with a placeholder SHA-256. The published formula goes to `homebrew-tap` (needs the `HOMEBREW_TAP_TOKEN` secret).
