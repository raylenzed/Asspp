#!/bin/bash
set -euo pipefail

task_root=$(cd "$(dirname "$0")/../.." && pwd)
task_package=$(mktemp -d /tmp/asspp-sap-validation.XXXXXX)
trap 'rm -rf "$task_package"' EXIT
mkdir -p "$task_package/Sources" "$task_package/Tests"
cp -R "$task_root/Packages/ApplePackage/Sources/AppleSAPRuntime" "$task_package/Sources/"
cp -R "$task_root/Packages/ApplePackage/Tests/SAPRuntimeTests" "$task_package/Tests/"
cat > "$task_package/Package.swift" <<'EOF'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SAPValidation",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AppleSAPRuntime", resources: [.copy("Runtime")]),
        .testTarget(name: "SAPRuntimeTests", dependencies: ["AppleSAPRuntime"]),
    ]
)
EOF
ASSPP_TEST_APPLE_SAP=1 swift test --package-path "$task_package" --filter SAPWebSignerTests
