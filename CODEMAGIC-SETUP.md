# MeloPlayer + Codemagic

This repository is ready for Codemagic to detect `codemagic.yaml` from the repository root.

## First test build
1. Upload the CONTENTS of this folder to the root of your GitHub repository.
2. In Codemagic select branch `main` and tap **Check for configuration files**.
3. Select **MeloPlayer iOS** and start a build.
4. The included workflow deliberately performs an unsigned iOS Simulator build first. This verifies that the Swift/Xcode project compiles without requiring Apple signing credentials.

## To produce an installable IPA / TestFlight build
Apple requires code signing. In Codemagic connect your Apple Developer / App Store Connect credentials, register a unique bundle identifier, and configure iOS code signing. Then change the workflow from the simulator verification build to an archive/export workflow using your signing profile.

Current placeholder bundle identifier: `com.example.MeloPlayer`. Change this to a bundle ID you own before distribution, for example `com.yourname.meloplayer`.

Do not commit Apple private keys, .p8 keys, certificates, or passwords to GitHub.
