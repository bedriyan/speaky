#!/bin/bash
set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Speaky"
BUILD_DIR="$PROJECT_DIR/build"
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
DMGBUILD_SETTINGS="$PROJECT_DIR/.github/dmgbuild-settings.py"
DMG_BACKGROUND="$PROJECT_DIR/.github/dmg-background.png"
DOCS_DIR="$PROJECT_DIR/docs"

echo "==> Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

# Parse arguments
BUILD_MODE="${1:-universal}" # universal, silicon, intel, separate

# Helper: wipe DerivedData to avoid stale builds across architectures
clean_derived_data() {
    rm -rf ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*
}

# Clean DerivedData to avoid stale cached builds
clean_derived_data

# Ensure clean build output directory
mkdir -p "$BUILD_DIR"

# Helper: find the built .app in DerivedData
find_built_app() {
    find ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/Release \
        -name "$APP_NAME.app" -maxdepth 1 2>/dev/null | head -1
}

# Helper: prepare app for distribution (strip quarantine, re-sign)
prepare_app() {
    local app_path="$1"
    xattr -cr "$app_path"
    # Deep-sign nested frameworks/bundles first, then re-sign the main app
    # with explicit identifier so macOS Accessibility matches the bundle ID
    codesign --force --deep --sign - "$app_path"
    codesign --force --sign - --identifier com.bedriyan.speaky "$app_path"
}

# Helper: create DMG using dmgbuild (with drag-to-Applications visual)
create_dmg() {
    local app_path="$1"
    local dmg_path="$2"

    if command -v dmgbuild &>/dev/null && [ -f "$DMGBUILD_SETTINGS" ]; then
        APP_PATH="$app_path" DMG_BACKGROUND="$DMG_BACKGROUND" \
            dmgbuild -s "$DMGBUILD_SETTINGS" "$APP_NAME" "$dmg_path"
    else
        echo "    (dmgbuild not found, falling back to hdiutil)"
        local tmpdir
        tmpdir=$(mktemp -d)
        ditto "$app_path" "$tmpdir/$APP_NAME.app"
        hdiutil create -volname "$APP_NAME" -srcfolder "$tmpdir" -ov -format UDZO "$dmg_path" 2>&1 | tail -2
        rm -rf "$tmpdir"
    fi
}

# Helper: find Sparkle tools from SPM checkout
find_sparkle_tools() {
    local sparkle_dir
    sparkle_dir=$(find ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/SourcePackages/artifacts/sparkle \
        -name "sign_update" -maxdepth 5 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
    if [ -z "$sparkle_dir" ]; then
        echo ""
    else
        echo "$sparkle_dir"
    fi
}

# Helper: sign DMG with Sparkle EdDSA and generate appcast
sparkle_sign_and_appcast() {
    local sparkle_tools
    sparkle_tools=$(find_sparkle_tools)
    if [ -z "$sparkle_tools" ]; then
        echo "    WARNING: Sparkle tools not found — skipping EdDSA signing and appcast generation"
        echo "    (Build the project first so SPM checkouts are available)"
        return
    fi

    echo "==> Signing DMGs with Sparkle EdDSA..."
    local sign_update="$sparkle_tools/sign_update"
    local generate_appcast="$sparkle_tools/generate_appcast"

    # Create arch-specific staging dirs for appcast generation
    local arm64_dir="$BUILD_DIR/appcast-arm64"
    local x86_dir="$BUILD_DIR/appcast-x86_64"
    rm -rf "$arm64_dir" "$x86_dir"
    mkdir -p "$arm64_dir" "$x86_dir"

    # Copy and sign arch-specific DMGs
    local arm64_dmg="$BUILD_DIR/$APP_NAME-$VERSION-Apple-Silicon.dmg"
    local x86_dmg="$BUILD_DIR/$APP_NAME-$VERSION-Intel.dmg"

    if [ -f "$arm64_dmg" ]; then
        cp "$arm64_dmg" "$arm64_dir/"
        echo "    Signing: $(basename "$arm64_dmg")"
        "$sign_update" "$arm64_dir/$(basename "$arm64_dmg")" 2>&1 | head -1 || true
    fi

    if [ -f "$x86_dmg" ]; then
        cp "$x86_dmg" "$x86_dir/"
        echo "    Signing: $(basename "$x86_dmg")"
        "$sign_update" "$x86_dir/$(basename "$x86_dmg")" 2>&1 | head -1 || true
    fi

    echo "==> Generating appcasts..."
    local download_url_prefix="https://github.com/bedriyan/speaky/releases/download/v$VERSION"

    if [ -f "$arm64_dmg" ]; then
        "$generate_appcast" --download-url-prefix "$download_url_prefix/" "$arm64_dir" 2>&1 | tail -3 || true
        if [ -f "$arm64_dir/appcast.xml" ]; then
            mkdir -p "$DOCS_DIR"
            cp "$arm64_dir/appcast.xml" "$DOCS_DIR/appcast-arm64.xml"
            echo "    Created: docs/appcast-arm64.xml"
        fi
    fi

    if [ -f "$x86_dmg" ]; then
        "$generate_appcast" --download-url-prefix "$download_url_prefix/" "$x86_dir" 2>&1 | tail -3 || true
        if [ -f "$x86_dir/appcast.xml" ]; then
            mkdir -p "$DOCS_DIR"
            cp "$x86_dir/appcast.xml" "$DOCS_DIR/appcast-x86_64.xml"
            echo "    Created: docs/appcast-x86_64.xml"
        fi
    fi

    # Cleanup staging
    rm -rf "$arm64_dir" "$x86_dir"
}

# Helper: sign and package a single build into a DMG
package_build() {
    local suffix="$1"  # e.g. "Apple-Silicon", "Intel", "Universal", or ""
    local dmg_name

    BUILT_APP=$(find_built_app)
    if [ -z "$BUILT_APP" ]; then
        echo "ERROR: Build product not found!"
        exit 1
    fi

    echo "    Arch: $(lipo -info "$BUILT_APP/Contents/MacOS/$APP_NAME" 2>&1)"

    # Stage, sign, and create DMG
    local stage_dir
    stage_dir=$(mktemp -d)
    ditto "$BUILT_APP" "$stage_dir/$APP_NAME.app"
    prepare_app "$stage_dir/$APP_NAME.app"

    if [ -n "$suffix" ]; then
        dmg_name="$APP_NAME-$VERSION-$suffix.dmg"
    else
        dmg_name="$APP_NAME-$VERSION.dmg"
    fi

    echo "==> Creating DMG: $dmg_name..."
    rm -f "$BUILD_DIR/$dmg_name"
    create_dmg "$stage_dir/$APP_NAME.app" "$BUILD_DIR/$dmg_name"
    rm -rf "$stage_dir"

    echo "    $BUILD_DIR/$dmg_name"
}

case "$BUILD_MODE" in
  silicon)
    echo "==> Building $APP_NAME (Release, Apple Silicon only)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    package_build "Apple-Silicon"
    ;;
  intel)
    echo "==> Building $APP_NAME (Release, Intel only)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    package_build "Intel"
    ;;
  separate)
    # --- Apple Silicon ---
    echo "==> Building $APP_NAME (Release, Apple Silicon)..."
    clean_derived_data
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    package_build "Apple-Silicon"

    # --- Intel ---
    echo "==> Building $APP_NAME (Release, Intel)..."
    clean_derived_data
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    package_build "Intel"
    ;;
  universal|*)
    echo "==> Building $APP_NAME (Release, Universal Binary)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    package_build ""
    ;;
esac

# Generate Sparkle appcasts for separate builds
if [ "$BUILD_MODE" = "separate" ]; then
    sparkle_sign_and_appcast
fi

echo ""
echo "==> Build complete!"
ls -lh "$BUILD_DIR/$APP_NAME-$VERSION"*.dmg 2>/dev/null | awk '{print "    " $5 "\t" $NF}'
echo ""
echo "Install from the DMG in build/ directory."
