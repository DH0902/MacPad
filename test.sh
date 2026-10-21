#!/bin/zsh
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), SwiftPM doesn't
# search the folder that holds Swift Testing, so point it there explicitly.
set -euo pipefail
cd "$(dirname "$0")"
FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIBS=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [[ -d $FRAMEWORKS ]]; then
    swift test -Xswiftc -F -Xswiftc $FRAMEWORKS -Xlinker -F -Xlinker $FRAMEWORKS \
        -Xlinker -rpath -Xlinker $FRAMEWORKS -Xlinker -rpath -Xlinker $LIBS "$@"
else
    swift test "$@"
fi
