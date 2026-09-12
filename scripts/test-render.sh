#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
xcrun swiftc -swift-version 5 -g Sources/MacBookDuo/LiveSessionState.swift Sources/MacBookDuo/EffectMath.swift Sources/MacBookDuo/HingeSensor.swift Sources/MacBookDuo/GlassRenderer.swift Sources/MacBookDuo/DesktopCapture.swift Sources/MacBookDuo/DuoModel.swift Tests/RenderTests.swift -o work/render-tests -framework AppKit -framework SwiftUI -framework MetalKit -framework CoreImage -framework ScreenCaptureKit -framework IOKit
work/render-tests "$PWD/work/render-check"
