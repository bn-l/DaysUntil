# Build commands for DaysUntil app

# Default recipe: build the app bundle
default: app

# Build DaysUntil.app bundle to ./build/
app:
    @mkdir -p build
    xcodebuild -project DaysUntil.xcodeproj -scheme DaysUntil -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode -quiet
    @if [ -d build/DaysUntil.app ]; then trash build/DaysUntil.app; fi
    @cp -R .build/xcode/Build/Products/Debug/DaysUntil.app build/

# Build release app bundle
app-release:
    @mkdir -p build
    xcodebuild -project DaysUntil.xcodeproj -scheme DaysUntil -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode -quiet
    @if [ -d build/DaysUntil.app ]; then trash build/DaysUntil.app; fi
    @cp -R .build/xcode/Build/Products/Release/DaysUntil.app build/

# Regenerate Xcode project from project.yml
gen:
    xcodegen generate

# Run the app
run: app
    open build/DaysUntil.app

# Render sample menubar badges to /tmp/daysuntil-icons for inspection
icons:
    swift build
    .build/debug/DaysUntil --render-icons /tmp/daysuntil-icons
    open /tmp/daysuntil-icons

# Clean build artifacts
clean:
    @if [ -d build ]; then trash build; fi
    @if [ -d .build ]; then trash .build; fi

# Print version from Info.plist
version:
    @/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist
