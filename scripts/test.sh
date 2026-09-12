#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
xcrun swiftc Sources/MacBookDuo/EffectMath.swift Tests/EffectMathTests.swift -o work/effect-tests
work/effect-tests

xcrun swiftc Sources/MacBookDuo/LiveSessionState.swift Tests/LiveSessionStateTests.swift -o work/lifecycle-tests
work/lifecycle-tests
