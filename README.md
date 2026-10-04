# MeloPlayer Native iOS - XcodeGen / Codemagic

This package is designed for uploading from an iPhone. It intentionally contains no .xcodeproj folder.

Upload the CONTENTS of this folder to the root of your GitHub repository. At the root you should see:
- codemagic.yaml
- project.yml
- README.md
- MeloPlayer/

In Codemagic, choose the repository and main branch, then Check for configuration files. The workflow installs XcodeGen, generates MeloPlayer.xcodeproj in the cloud, and runs an unsigned simulator build first.

After that build succeeds, configure Apple Developer signing/TestFlight for a signed IPA.
