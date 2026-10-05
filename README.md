# MeloPlayer - Codemagic + AltStore

This version builds an unsigned physical-iPhone app in Codemagic and packages it as `MeloPlayer-AltStore.ipa`. AltStore/AltServer performs the free Apple Account signing when you install the IPA.

## GitHub layout
Keep `codemagic.yaml`, `project.yml`, and this README at the repository root. Keep the Swift files inside the `MeloPlayer` folder.

## Codemagic
Start workflow **MeloPlayer iPhone IPA - AltStore**. After it succeeds, open **Artifacts** and download `MeloPlayer-AltStore.ipa`.

## AltStore
Transfer/open the IPA on the iPhone, then in AltStore use **My Apps > +** and choose `MeloPlayer-AltStore.ipa`. AltStore will sign it using the Apple Account configured in AltStore.

Free Apple Account provisioning normally expires after 7 days, so refresh the app through AltStore before it expires.
