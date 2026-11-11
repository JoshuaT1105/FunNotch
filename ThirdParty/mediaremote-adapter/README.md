# mediaremote-adapter (vendored)

Source of [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
at tag `v0.7.7` (commit `e3ff502`), BSD 3-Clause (see `LICENSE`).

macOS 15.4 stopped answering apps that ask the private MediaRemote framework
what is playing. `/usr/bin/perl` is still entitled to, so `build.sh` compiles
`MediaRemoteAdapter.framework` and `MediaRemoteAdapterTestClient` from this
source and bundles them, with `bin/mediaremote-adapter.pl`, into
`FunNotch.app/Contents/Resources/MediaRemoteAdapter/`. FunNotch runs
`/usr/bin/perl mediaremote-adapter.pl <framework> <test client> stream` and
reads now playing updates from its output. See
`Sources/Managers/MediaRemoteAdapter.swift`.

Only the files the build needs are copied here. To update, replace them with a
newer tag and note it above.
