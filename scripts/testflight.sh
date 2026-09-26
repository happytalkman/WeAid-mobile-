#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:---verify}"
case "$mode" in --verify|--archive|--upload) ;; *) echo 'Usage: bash scripts/testflight.sh --verify|--archive|--upload'; exit 2;; esac
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null; then
  echo 'Mac과 정식 Xcode 26 이상이 필요합니다. 이 환경에서는 빌드/업로드하지 않았습니다.' >&2
  exit 1
fi
xcode_version="$(xcodebuild -version | head -n 1 | awk '{print $2}')"
if [[ "${xcode_version%%.*}" -lt 26 ]]; then echo 'Xcode 26 이상을 선택해 주세요.' >&2; exit 1; fi
if [[ "$mode" == --verify ]]; then
  xcodebuild -project MarkMobile.xcodeproj -scheme MarkMobile \
    -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/Verify CODE_SIGNING_ALLOWED=NO build
  exit 0
fi
: "${MARK_TEAM_ID:?Apple Team ID를 MARK_TEAM_ID에 설정하세요.}"
: "${MARK_BUNDLE_ID:?등록한 앱 Bundle ID를 MARK_BUNDLE_ID에 설정하세요.}"
: "${MARK_BUILD_NUMBER:?이전 업로드보다 큰 정수 빌드 번호를 MARK_BUILD_NUMBER에 설정하세요.}"
[[ "$MARK_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo '잘못된 Team ID'; exit 2; }
[[ "$MARK_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { echo '잘못된 Bundle ID'; exit 2; }
[[ "$MARK_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo '빌드 번호는 양의 정수여야 합니다.'; exit 2; }
[[ "$MARK_BUNDLE_ID" != com.personal.markmobile ]] || { echo '고유한 Bundle ID로 변경해 주세요.'; exit 2; }
# Validate compilation first. Credentials are taken from Xcode's signed-in account.
bash scripts/testflight.sh --verify
mkdir -p build
archive="build/MarkMobile-${MARK_BUILD_NUMBER}.xcarchive"
xcodebuild -project MarkMobile.xcodeproj -scheme MarkMobile \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$MARK_TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$MARK_BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$MARK_BUILD_NUMBER" archive
if [[ "$mode" == --archive ]]; then
  echo "Archive created: $archive"
  echo 'Xcode Organizer에서 Validate App 및 Distribute App을 진행하세요.'
  exit 0
fi
# An upload is explicitly selected with --upload. No external testers are invited.
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>${MARK_TEAM_ID}</string>
<key>signingStyle</key><string>automatic</string>
<key>uploadSymbols</key><true/>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" \
  -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
printf '%s\n' '업로드 명령이 완료되었습니다. App Store Connect에서 처리 상태·암호화 관련 질문·TestFlight 그룹을 확인해 주세요.'
