# Swift + SwiftUI iOS App Setup

## iOS verify — pre-flight checklist

Before kicking off `xcodebuild` or simulator booting — any of which take minutes — run these checks first. Missing platform SDKs and simulator runtimes surface here in seconds.

Run each step in order. Halt at the first failure and surface what's missing to the user before kicking off anything expensive.

```bash
# 1. Xcode is installed and selected
xcode-select -p
xcodebuild -version

# 2. At least one iOS simulator runtime is available
xcrun simctl list runtimes available | grep -E "iOS [0-9]+\." | head -5

# 3. The Xcode-shipped SDK has matching simulator support
xcodebuild -showsdks 2>&1 | grep iphonesimulator
xcrun simctl list devices available | grep -E "iPhone 1[567]" | head -3
```

If step 3's `simctl` output shows zero iPhone devices on the SDK's iOS version, the platform support files are missing. The fix is an 8–12 GB, 10–30 minute download — **confirm with the user before kicking it off**:

```bash
xcodebuild -downloadPlatform iOS
```

## Running the App

```bash
# Start simulator and run app
codeyam-editor editor start-simulator swift-ios-swiftui
```

## Mocking & CA Installation
To allow HTTPS mock interception to function out-of-the-box, the simulator boot path installs the CodeYam root CA into the booted simulator's keychain:
```bash
xcrun simctl keychain booted add-root-cert .codeyam/ca/ca.pem
```
This ensures URLSession requests are trusted and routed correctly.
