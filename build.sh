#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Speakink"
LOCAL_APP="$PROJECT_DIR/$APP_NAME.app"
RELEASE_DIR="$PROJECT_DIR/release"
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*"\(.*\)".*/\1/')

echo "==> Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

# Parse arguments
BUILD_MODE="${1:-universal}" # universal, silicon, intel, separate

case "$BUILD_MODE" in
  silicon)
    echo "==> Building $APP_NAME (Release, Apple Silicon only)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    ;;
  intel)
    echo "==> Building $APP_NAME (Release, Intel only)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    ;;
  separate)
    echo "==> Building $APP_NAME (Release, Apple Silicon)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
        clean build 2>&1 | tail -5

    BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/Release -name "$APP_NAME.app" -maxdepth 1 2>/dev/null | head -1)
    if [ -z "$BUILT_APP" ]; then
        echo "ERROR: Apple Silicon build product not found!"
        exit 1
    fi

    mkdir -p "$RELEASE_DIR"
    rm -rf "$RELEASE_DIR/$APP_NAME-Apple-Silicon.app"
    cp -R "$BUILT_APP" "$RELEASE_DIR/$APP_NAME-Apple-Silicon.app"

    echo "==> Building $APP_NAME (Release, Intel)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO \
        clean build 2>&1 | tail -5

    BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/Release -name "$APP_NAME.app" -maxdepth 1 2>/dev/null | head -1)
    if [ -z "$BUILT_APP" ]; then
        echo "ERROR: Intel build product not found!"
        exit 1
    fi

    rm -rf "$RELEASE_DIR/$APP_NAME-Intel.app"
    cp -R "$BUILT_APP" "$RELEASE_DIR/$APP_NAME-Intel.app"

    # Create DMGs for distribution
    if command -v hdiutil &>/dev/null; then
        echo "==> Creating DMGs..."
        rm -f "$RELEASE_DIR/$APP_NAME-$VERSION-Apple-Silicon.dmg"
        hdiutil create -volname "$APP_NAME" -srcfolder "$RELEASE_DIR/$APP_NAME-Apple-Silicon.app" \
            -ov -format UDZO "$RELEASE_DIR/$APP_NAME-$VERSION-Apple-Silicon.dmg" 2>&1 | tail -2

        rm -f "$RELEASE_DIR/$APP_NAME-$VERSION-Intel.dmg"
        hdiutil create -volname "$APP_NAME" -srcfolder "$RELEASE_DIR/$APP_NAME-Intel.app" \
            -ov -format UDZO "$RELEASE_DIR/$APP_NAME-$VERSION-Intel.dmg" 2>&1 | tail -2
    fi

    echo ""
    echo "==> Separate builds complete!"
    echo "    Apple Silicon: $RELEASE_DIR/$APP_NAME-Apple-Silicon.app"
    echo "    Intel:         $RELEASE_DIR/$APP_NAME-Intel.app"
    if [ -f "$RELEASE_DIR/$APP_NAME-$VERSION-Apple-Silicon.dmg" ]; then
        echo "    DMG (Silicon): $RELEASE_DIR/$APP_NAME-$VERSION-Apple-Silicon.dmg"
        echo "    DMG (Intel):   $RELEASE_DIR/$APP_NAME-$VERSION-Intel.dmg"
    fi
    echo ""
    ls -lh "$RELEASE_DIR"/*.dmg "$RELEASE_DIR"/*.app 2>/dev/null | awk '{print "    " $5 "\t" $NF}'
    exit 0
    ;;
  universal|*)
    echo "==> Building $APP_NAME (Release, Universal Binary)..."
    xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
        ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
        build 2>&1 | tail -5
    ;;
esac

# Find the built .app in DerivedData
BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/Release -name "$APP_NAME.app" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$BUILT_APP" ]; then
    echo "ERROR: Build product not found!"
    exit 1
fi

echo "==> Removing old $APP_NAME.app..."
rm -rf "$LOCAL_APP"

echo "==> Copying new build to project root..."
cp -R "$BUILT_APP" "$LOCAL_APP"

echo "==> Done! $LOCAL_APP"
echo "==> Opening $APP_NAME..."
open "$LOCAL_APP"
