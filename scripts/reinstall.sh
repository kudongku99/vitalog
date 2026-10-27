#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${VITALOG_DEVICE:-00008140-000268482109801C}"
BUNDLE_ID="com.kudongku.vitalog"
APP="build/Build/Products/Debug-iphoneos/Vitalog.app"
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)
BACKUP_DIR="$(mktemp -d)"
BUILD_LOG="$(mktemp)"
LAUNCH=false
STASHED=()

for arg in "$@"; do
  case "$arg" in
    --launch) LAUNCH=true ;;
    -h|--help)
      echo "사용법: scripts/reinstall.sh [--launch]"
      echo "  프로파일을 새로 받아 빌드하고 기기에 덮어 설치합니다. 무료 개발자 계정의 7일 제한을 매주 갱신하는 용도입니다."
      echo "  --launch  설치 후 앱을 실행합니다 (기기 잠금을 풀어 둬야 합니다)."
      echo "  환경 변수 VITALOG_DEVICE로 기기 UDID를 바꿀 수 있습니다."
      exit 0 ;;
    *) echo "알 수 없는 옵션: $arg" >&2; exit 2 ;;
  esac
done

die() { echo "오류: $*" >&2; exit 1; }

profile_value() { security cms -D -i "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null || true; }

stash_profiles() {
  local dir file id
  for dir in "${PROFILE_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for file in "$dir"/*.mobileprovision; do
      [ -e "$file" ] || continue
      id="$(profile_value "$file" Entitlements.application-identifier)"
      if [[ "$id" == *".$BUNDLE_ID" ]]; then
        mv "$file" "$BACKUP_DIR/"
        STASHED+=("$file")
      fi
    done
  done
}

restore_profiles() {
  local original
  for original in ${STASHED[@]+"${STASHED[@]}"}; do
    [ -e "$BACKUP_DIR/$(basename "$original")" ] && mv "$BACKUP_DIR/$(basename "$original")" "$original"
  done
}

epoch_of() { TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s; }
kst() { TZ=Asia/Seoul date -r "$1" "+%Y-%m-%d %H:%M"; }

[ -f ios/Secrets.xcconfig ] || die "ios/Secrets.xcconfig가 없습니다. ios/Secrets.xcconfig.example을 복사해 채워 주세요."

echo "1/4 기기 연결 확인"
DEVICE_LINE="$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" || true)"
[[ -n "$DEVICE_LINE" && "$DEVICE_LINE" != *unavailable* ]] \
  || die "기기($DEVICE)에 연결할 수 없습니다. 케이블 연결, 잠금 해제, 이 Mac 신뢰 여부를 확인하세요."

echo "2/4 이 앱의 프로파일을 새로 받도록 준비"
stash_profiles
rm -rf "$APP"
echo "    백업한 프로파일: ${#STASHED[@]}개"

echo "3/4 빌드 (1~3분)"
if ! xcodebuild -project ios/Vitalog.xcodeproj -scheme Vitalog -destination "id=$DEVICE" \
    -derivedDataPath build -allowProvisioningUpdates build >"$BUILD_LOG" 2>&1; then
  restore_profiles
  tail -n 25 "$BUILD_LOG" >&2
  die "빌드에 실패해 프로파일을 원래대로 되돌렸습니다. Xcode에서 Apple ID 로그인 상태를 확인하세요."
fi

EXPIRY="$(profile_value "$APP/embedded.mobileprovision" ExpirationDate)"
[ -n "$EXPIRY" ] || die "빌드 결과에서 프로파일 만료일을 읽지 못했습니다."
EXPIRY_EPOCH="$(epoch_of "$EXPIRY")"
DAYS_LEFT=$(( (EXPIRY_EPOCH - $(date +%s)) / 86400 ))

echo "4/4 기기에 덮어 설치"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null || die "설치에 실패했습니다."

if $LAUNCH; then
  xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 \
    || echo "    앱 실행은 건너뛰었습니다 (기기 잠금을 풀고 직접 여세요)."
fi

rm -rf "$BACKUP_DIR" "$BUILD_LOG"

echo
echo "설치를 마쳤습니다."
echo "  앱 만료: $(kst "$EXPIRY_EPOCH") (${DAYS_LEFT}일 남음)"
echo "  다음 재설치 권장: $(kst $(( EXPIRY_EPOCH - 86400 ))) 이전"
if [ "$DAYS_LEFT" -lt 6 ]; then
  echo "  주의: 만료일이 7일보다 짧습니다. 프로파일이 갱신되지 않았을 수 있으니 Xcode의 Apple ID 로그인 상태를 확인하세요."
fi
