#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'Usage: %s <version>\n' "$0" >&2
    exit 1
fi

version="${1#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Version must use SemVer, for example 0.1.0.\n' >&2
    exit 1
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(dirname "$script_directory")"
project_path="$repository_directory/AIUsage.xcodeproj"
derived_data_directory="$repository_directory/DerivedData-Release"
artifact_directory="$repository_directory/dist/v$version"
release_notes="$repository_directory/docs/releases/$version.md"
application_name="AI Usage Plus"
disk_image_name="AI-Usage-Plus"
repository_url="https://github.com/rafalozan0/ai-usage-plus"
built_application="$derived_data_directory/Build/Products/Release/$application_name.app"
application_binary="$built_application/Contents/MacOS/$application_name"
sparkle_framework="$built_application/Contents/Frameworks/Sparkle.framework"
disk_image="$artifact_directory/$disk_image_name.dmg"
checksum="$artifact_directory/$disk_image_name.dmg.sha256"
sparkle_account="ai-usage-plus"
sparkle_key_file="${SPARKLE_ED_KEY_FILE:-}"

if [[ ! -f "$release_notes" ]]; then
    printf 'Missing release notes: %s\n' "$release_notes" >&2
    exit 1
fi

xcode_major="$(
    xcodebuild -version |
        awk 'NR == 1 { split($2, parts, "."); print parts[1] }'
)"
if [[ -z "$xcode_major" || "$xcode_major" -lt 27 ]]; then
    printf '%s releases require Xcode 27 or newer.\n' "$application_name" >&2
    exit 1
fi

configured_version="$(
    xcodebuild \
        -project "$project_path" \
        -scheme AIUsage \
        -configuration Release \
        -showBuildSettings |
        awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }'
)"
if [[ "$configured_version" != "$version" ]]; then
    printf \
        'Project version is %s, but the requested release is %s.\n' \
        "$configured_version" \
        "$version" >&2
    exit 1
fi

# Signing modes:
#   developer-id  Developer ID Application certificate; can be notarized.
#   self-signed   Any other identity (for example a stable self-signed
#                 certificate). Keeps the code signing identity stable across
#                 releases so Keychain "Always Allow" grants survive updates,
#                 but cannot be notarized.
#   ad-hoc        No identity. Every build gets a new signature.
codesign_identity="${AI_USAGE_CODESIGN_IDENTITY:-}"
codesign_keychain="${AI_USAGE_CODESIGN_KEYCHAIN:-}"
keychain_arguments=()
if [[ -n "$codesign_keychain" ]]; then
    keychain_arguments+=(--keychain "$codesign_keychain")
fi

if [[ -z "$codesign_identity" ]]; then
    codesign_identity="$(
        security find-identity -v -p codesigning 2>/dev/null |
            awk '/Developer ID Application:/ { print $2; exit }'
    )"
fi

if [[ -z "$codesign_identity" ]]; then
    signing_mode="ad-hoc"
elif security find-identity -p codesigning ${codesign_keychain:+"$codesign_keychain"} 2>/dev/null |
    grep -F "$codesign_identity" |
    grep -q 'Developer ID Application:'; then
    signing_mode="developer-id"
else
    signing_mode="self-signed"
fi

build_settings=()
case "$signing_mode" in
    developer-id)
        printf 'Building a universal Developer ID signed app…\n'
        build_settings+=(
            "CODE_SIGN_STYLE=Manual"
            "CODE_SIGN_IDENTITY=$codesign_identity"
            "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO"
        )
        if [[ -n "$codesign_keychain" ]]; then
            build_settings+=("OTHER_CODE_SIGN_FLAGS=--keychain $codesign_keychain")
        fi
        ;;
    self-signed)
        # Xcode refuses untrusted identities, so build ad-hoc and re-sign
        # every nested component below. Hardened Runtime stays off: without
        # a Team ID, library validation would reject Sparkle.framework.
        printf 'Building a universal app for self-signed distribution…\n'
        build_settings+=(
            "CODE_SIGN_STYLE=Automatic"
            "ENABLE_HARDENED_RUNTIME=NO"
        )
        ;;
    ad-hoc)
        printf 'Building a universal ad-hoc signed app…\n'
        printf \
            'Warning: no signing identity was found; Keychain grants will not survive updates.\n' \
            >&2
        build_settings+=(
            "CODE_SIGN_STYLE=Automatic"
            "ENABLE_HARDENED_RUNTIME=NO"
        )
        ;;
esac

xcodebuild \
    -quiet \
    -project "$project_path" \
    -scheme AIUsage \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data_directory" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    "${build_settings[@]}" \
    clean build

if [[ ! -d "$built_application" ]]; then
    printf 'Release app was not produced at %s\n' "$built_application" >&2
    exit 1
fi

codesign_options=()
if [[ "$signing_mode" == "developer-id" ]]; then
    codesign_options+=(
        --force
        --sign "$codesign_identity"
        ${keychain_arguments[@]+"${keychain_arguments[@]}"}
        --options runtime
        --timestamp
    )
elif [[ "$signing_mode" == "self-signed" ]]; then
    codesign_options+=(
        --force
        --sign "$codesign_identity"
        ${keychain_arguments[@]+"${keychain_arguments[@]}"}
        --timestamp=none
    )
fi

if [[ "$signing_mode" != "ad-hoc" ]]; then
    printf 'Signing Sparkle helpers and the app (%s)…\n' "$signing_mode"
    sparkle_version="$sparkle_framework/Versions/B"

    /usr/bin/codesign \
        "${codesign_options[@]}" \
        "$sparkle_version/XPCServices/Installer.xpc"
    /usr/bin/codesign \
        "${codesign_options[@]}" \
        --preserve-metadata=entitlements \
        "$sparkle_version/XPCServices/Downloader.xpc"
    /usr/bin/codesign \
        "${codesign_options[@]}" \
        "$sparkle_version/Autoupdate"
    /usr/bin/codesign \
        "${codesign_options[@]}" \
        "$sparkle_version/Updater.app"
    /usr/bin/codesign \
        "${codesign_options[@]}" \
        "$sparkle_framework"
    /usr/bin/codesign \
        "${codesign_options[@]}" \
        "$built_application"
fi

/usr/bin/lipo -verify_arch arm64 "$application_binary"
/usr/bin/lipo -verify_arch x86_64 "$application_binary"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$built_application"

embedded_version="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$built_application/Contents/Info.plist"
)"
if [[ "$embedded_version" != "$version" ]]; then
    printf 'Built app version is %s, expected %s.\n' "$embedded_version" "$version" >&2
    exit 1
fi

feed_url="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUFeedURL' \
        "$built_application/Contents/Info.plist"
)"
expected_feed_url="https://raw.githubusercontent.com/rafalozan0/ai-usage-plus/main/appcast.xml"
if [[ "$feed_url" != "$expected_feed_url" ]]; then
    printf 'Unexpected Sparkle feed URL: %s\n' "$feed_url" >&2
    exit 1
fi

sparkle_directory="$derived_data_directory/SourcePackages/artifacts/sparkle/Sparkle"
sparkle_license="$derived_data_directory/SourcePackages/checkouts/Sparkle/LICENSE"
generate_appcast="$sparkle_directory/bin/generate_appcast"
generate_keys="$sparkle_directory/bin/generate_keys"
sign_update="$sparkle_directory/bin/sign_update"
if [[
    ! -x "$generate_appcast" ||
        ! -x "$generate_keys" ||
        ! -x "$sign_update" ||
        ! -f "$sparkle_license"
]]; then
    printf 'Sparkle release tools were not resolved by Xcode.\n' >&2
    exit 1
fi

embedded_public_key="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :SUPublicEDKey' \
        "$built_application/Contents/Info.plist"
)"
if [[ -n "$sparkle_key_file" ]]; then
    # CI has no login Keychain entry, so derive the Ed25519 public key from
    # the exported private seed (PKCS#8 prefix + 32-byte seed).
    sparkle_signing_arguments=(--ed-key-file "$sparkle_key_file")
    expected_public_key="$(
        {
            printf '302e020100300506032b657004220420' | xxd -r -p
            base64 -d < "$sparkle_key_file"
        } |
            openssl pkey -inform DER -pubout -outform DER |
            tail -c 32 |
            base64
    )"
else
    sparkle_signing_arguments=(--account "$sparkle_account")
    expected_public_key="$("$generate_keys" --account "$sparkle_account" -p)"
fi
if [[ "$embedded_public_key" != "$expected_public_key" ]]; then
    printf 'The app public key does not match the Sparkle signing key.\n' >&2
    exit 1
fi

mkdir -p "$artifact_directory"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-release.XXXXXX")"
smoke_test_pid=""
cleanup() {
    if [[ -n "$smoke_test_pid" ]] && kill -0 "$smoke_test_pid" 2>/dev/null; then
        kill -TERM "$smoke_test_pid" 2>/dev/null || true
        wait "$smoke_test_pid" 2>/dev/null || true
    fi
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

smoke_test_log="$temporary_directory/application-smoke.log"
printf 'Running launch smoke test…\n'
LLVM_PROFILE_FILE="$temporary_directory/application-smoke.profraw" \
    XCTestConfigurationFilePath=ReleaseSmoke \
    "$application_binary" > "$smoke_test_log" 2>&1 &
smoke_test_pid=$!
for _ in {1..20}; do
    if ! kill -0 "$smoke_test_pid" 2>/dev/null; then
        printf 'Release app exited during launch smoke test:\n' >&2
        sed -n '1,120p' "$smoke_test_log" >&2
        exit 1
    fi
    sleep 0.1
done
if ! kill -0 "$smoke_test_pid" 2>/dev/null; then
    printf 'Release app exited during launch smoke test:\n' >&2
    sed -n '1,120p' "$smoke_test_log" >&2
    exit 1
fi
kill -TERM "$smoke_test_pid" 2>/dev/null || true
wait "$smoke_test_pid" 2>/dev/null || true
smoke_test_pid=""

disk_image_source="$temporary_directory/disk-image"
updates_directory="$temporary_directory/updates"
licenses_directory="$disk_image_source/Licenses"
mkdir -p "$licenses_directory" "$updates_directory"

/usr/bin/ditto "$built_application" "$disk_image_source/$application_name.app"
/usr/bin/ditto "$repository_directory/LICENSE" "$licenses_directory/$application_name.txt"
/usr/bin/ditto \
    "$repository_directory/NOTICE" \
    "$licenses_directory/Third-Party Notices.txt"
/usr/bin/ditto "$sparkle_license" "$licenses_directory/Sparkle.txt"
/bin/ln -s /Applications "$disk_image_source/Applications"

printf 'Creating DMG…\n'
/usr/bin/hdiutil create \
    -quiet \
    -volname "$application_name" \
    -srcfolder "$disk_image_source" \
    -format UDZO \
    -ov \
    "$disk_image"
/usr/bin/hdiutil verify -quiet "$disk_image"

if [[ "$signing_mode" == "developer-id" ]]; then
    /usr/bin/codesign \
        --force \
        --sign "$codesign_identity" \
        ${keychain_arguments[@]+"${keychain_arguments[@]}"} \
        --timestamp \
        "$disk_image"
elif [[ "$signing_mode" == "self-signed" ]]; then
    /usr/bin/codesign \
        --force \
        --sign "$codesign_identity" \
        ${keychain_arguments[@]+"${keychain_arguments[@]}"} \
        --timestamp=none \
        "$disk_image"
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    if [[ "$signing_mode" != "developer-id" ]]; then
        printf 'NOTARYTOOL_PROFILE requires a Developer ID signed build.\n' >&2
        exit 1
    fi
    printf 'Submitting DMG for notarization…\n'
    notarization_result="$temporary_directory/notarization-result.json"
    xcrun notarytool submit \
        "$disk_image" \
        --keychain-profile "$NOTARYTOOL_PROFILE" \
        --wait \
        --output-format json > "$notarization_result"
    sed -n '1,120p' "$notarization_result"

    notarization_status="$(
        /usr/bin/plutil \
            -extract status \
            raw \
            -o - \
            "$notarization_result"
    )"
    if [[ "$notarization_status" != "Accepted" ]]; then
        notarization_id="$(
            /usr/bin/plutil \
                -extract id \
                raw \
                -o - \
                "$notarization_result"
        )"
        printf 'Notarization failed with status %s.\n' "$notarization_status" >&2
        xcrun notarytool log \
            "$notarization_id" \
            --keychain-profile "$NOTARYTOOL_PROFILE" >&2
        exit 1
    fi

    xcrun stapler staple "$disk_image"
    xcrun stapler validate "$disk_image"
fi

/usr/bin/shasum -a 256 "$disk_image" |
    awk -v name="$disk_image_name.dmg" '{ print $1 "  " name }' > "$checksum"

/usr/bin/ditto "$disk_image" "$updates_directory/$disk_image_name.dmg"
/usr/bin/ditto "$release_notes" "$updates_directory/$disk_image_name.md"
if [[ -f "$repository_directory/appcast.xml" ]]; then
    /usr/bin/ditto \
        "$repository_directory/appcast.xml" \
        "$updates_directory/appcast.xml"
fi

printf 'Generating signed Sparkle appcast…\n'
"$generate_appcast" \
    "${sparkle_signing_arguments[@]}" \
    --download-url-prefix \
    "$repository_url/releases/download/v$version/" \
    --embed-release-notes \
    --link "$repository_url" \
    --maximum-versions 5 \
    --maximum-deltas 0 \
    "$updates_directory"

/usr/bin/xmllint --noout "$updates_directory/appcast.xml"
"$sign_update" \
    "${sparkle_signing_arguments[@]}" \
    --verify \
    "$updates_directory/appcast.xml"
/usr/bin/ditto \
    "$updates_directory/appcast.xml" \
    "$repository_directory/appcast.xml"

printf '\nRelease package is ready:\n'
printf '  App: %s\n' "$built_application"
printf '  DMG: %s\n' "$disk_image"
printf '  SHA-256: %s\n' "$checksum"
printf '  Appcast: %s\n' "$repository_directory/appcast.xml"
printf '  Signing: %s\n' "$signing_mode"

if [[ "$signing_mode" != "developer-id" ]]; then
    printf '\nNotarization: skipped (no Developer ID Application identity)\n'
elif [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    printf '\nNotarization: skipped (NOTARYTOOL_PROFILE is not set)\n'
else
    printf '\nNotarization: complete\n'
fi
