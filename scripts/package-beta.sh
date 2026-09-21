#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIRECTORY:h}"
BETA_VERSION="${1:-0.2.1}"
MARKETING_VERSION="${2:-0.2.1}"
BUILD_VERSION="${3:-3}"
RELEASE_NAME="DesktopCanvas-Beta-${BETA_VERSION}"
DIST_DIRECTORY="${PROJECT_ROOT}/dist"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/desktopcanvas-release.XXXXXX")"
DERIVED_DATA_DIRECTORY="${BUILD_ROOT}/DerivedData"
APP_PATH="${DERIVED_DATA_DIRECTORY}/Build/Products/Release/DesktopCanvas.app"
DMG_PATH="${DIST_DIRECTORY}/${RELEASE_NAME}.dmg"
ZIP_PATH="${DIST_DIRECTORY}/${RELEASE_NAME}-macOS-universal.zip"
CHECKSUM_PATH="${DIST_DIRECTORY}/${RELEASE_NAME}-SHA256.txt"
RELEASE_NOTES_PATH="${PROJECT_ROOT}/RELEASE_NOTES_BETA_${BETA_VERSION}.md"
STAGING_ROOT=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

cleanup() {
    if [[ -d "${APP_PATH}" && -x "${LSREGISTER}" ]]; then
        "${LSREGISTER}" -u "${APP_PATH}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${STAGING_ROOT}" && -d "${STAGING_ROOT}" ]]; then
        rm -rf -- "${STAGING_ROOT}"
    fi
    if [[ -d "${BUILD_ROOT}" ]]; then
        rm -rf -- "${BUILD_ROOT}"
    fi
}

trap cleanup EXIT

if [[ ! -f "${RELEASE_NOTES_PATH}" ]]; then
    print -u2 "未找到对应的发布说明：${RELEASE_NOTES_PATH}"
    exit 1
fi

for output_path in "${DMG_PATH}" "${ZIP_PATH}" "${CHECKSUM_PATH}"; do
    if [[ -e "${output_path}" ]]; then
        print -u2 "输出文件已存在，请先移动它再重新打包：${output_path}"
        exit 1
    fi
done

mkdir -p "${DIST_DIRECTORY}"

xcodebuild \
    -project "${PROJECT_ROOT}/DesktopCanvas.xcodeproj" \
    -scheme DesktopCanvas \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "${DERIVED_DATA_DIRECTORY}" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="${MARKETING_VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_VERSION}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    clean build

if [[ ! -d "${APP_PATH}" ]]; then
    print -u2 "Release 应用未生成：${APP_PATH}"
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/DesktopCanvas"
BUILT_ARCHITECTURES="$(lipo -archs "${APP_EXECUTABLE}")"
if [[ " ${BUILT_ARCHITECTURES} " != *" arm64 "* || " ${BUILT_ARCHITECTURES} " != *" x86_64 "* ]]; then
    print -u2 "通用架构验证失败：${BUILT_ARCHITECTURES}"
    exit 1
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/desktopcanvas-beta.XXXXXX")"
PAYLOAD_DIRECTORY="${STAGING_ROOT}/${RELEASE_NAME}"
mkdir -p "${PAYLOAD_DIRECTORY}"

ditto "${APP_PATH}" "${PAYLOAD_DIRECTORY}/DesktopCanvas.app"
ditto "${RELEASE_NOTES_PATH}" "${PAYLOAD_DIRECTORY}/Beta ${BETA_VERSION} 发布说明.md"
ln -s /Applications "${PAYLOAD_DIRECTORY}/Applications"

hdiutil create \
    -volname "桌面画布 Beta ${BETA_VERSION}" \
    -srcfolder "${PAYLOAD_DIRECTORY}" \
    -format UDZO \
    "${DMG_PATH}"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
hdiutil verify "${DMG_PATH}"
shasum -a 256 "${DMG_PATH}" "${ZIP_PATH}" > "${CHECKSUM_PATH}"

print "Beta ${BETA_VERSION} 打包完成："
print "  ${DMG_PATH}"
print "  ${ZIP_PATH}"
print "  ${CHECKSUM_PATH}"
print "  架构：${BUILT_ARCHITECTURES}"
