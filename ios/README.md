# ios

Vitalog iOS 앱입니다. HealthKit 데이터를 읽어 Supabase로 올립니다. SwiftUI로 만들었고 최소 지원 버전은 iOS 17.0입니다.

## 현재 기능

- 이메일과 비밀번호로 Supabase에 로그인합니다. 세션은 `supabase-swift`가 키체인에 저장합니다.
- 최초 동기화(백필): 읽을 수 있는 모든 HealthKit 유형을 최신 달부터 거꾸로 월 단위로 읽어 올립니다. 끝난 구간은 기기에 기록하므로 중단돼도 이어서 진행합니다. 모두 끝나면 완료 시각을 기록하고, 이후 화면에는 완료 행만 남습니다. 복약, 시력 처방 권한을 나중에 허용했거나 앱 업데이트로 유형이 늘어난 경우에는 "다시 실행"(또는 새 유형 감지 시 자동 해제)으로 빠진 부분만 이어서 올립니다.
- 일별 통계(`daily_stats`), 원본 샘플, 운동과 경로, 활동 링, 고정 정보를 올립니다. 수치형 원본은 유형별 보관 기간(심박수 6개월, 고빈도 유형 3개월, 활동 링용 시간 2종은 제외, 나머지 전체)만 올립니다. 기준은 `HealthCatalog.swift`의 `QuantityRetention`입니다.
- 새 기록 동기화(증분, 백그라운드): 옵저버와 앵커 조회로 새 샘플과 삭제를 반영하고, 보조 백그라운드 작업(6시간 간격)과 앱을 화면에 띄울 때, "지금 동기화" 버튼으로도 동기화합니다. 동기화 기록은 `sync_log`에 남습니다.
- 앱 화면의 "상태"에 마지막 동기화 시각과 앱 만료일(남은 일수)을 표시하고, 만료가 2일 이하로 남으면 경고합니다. 만료일은 설치된 프로파일에서 읽습니다.

## 파일 구성

앱 코드는 `Vitalog/`에 있습니다.

| 파일 | 역할 |
| --- | --- |
| `VitalogApp.swift` | 진입점. 로그인 상태에 따라 화면을 바꿉니다. |
| `LoginView.swift` | 로그인 화면 |
| `BackfillView.swift` | 상태(마지막 동기화, 앱 만료일), 동기화 버튼, 유형별 진행 상황과 오류 표시 |
| `BackfillEngine.swift` | 백필 순서 제어, 잠금 상태 감지와 재개 |
| `BackfillProgress.swift` | 끝난 구간 기록을 기기 파일에 저장 |
| `BackfillTasks.swift`, `OtherSampleTasks.swift` | 유형 그룹별 동기화 작업 |
| `HealthReader.swift` | 권한 요청과 HealthKit 조회 |
| `HealthCatalog.swift`, `HealthNames.swift` | 수집 유형 목록, 표준 단위, 이름 |
| `HealthRows.swift` | HealthKit 객체를 DB 행으로 변환 |
| `Uploader.swift` | 묶음 upsert, 삭제, 재시도, `sync_log` 기록 |
| `SupabaseService.swift` | Supabase 클라이언트 설정 |
| `AppDelegate.swift` | 옵저버 등록과 보조 백그라운드 작업 예약 |
| `SyncService.swift`, `SyncState.swift` | 증분 동기화와 그 상태(앵커, 마지막 동기화) 저장 |
| `ProvisioningExpiry.swift` | 설치된 프로파일에서 앱 만료 시각 읽기 |
| `Theme.swift` | 디자인 토큰(색), 로고, 공통 스타일(버튼, 입력칸, 섹션 제목) |
| `Assets.xcassets/` | 앱 아이콘(`AppIcon`). 1024×1024 PNG 한 장이며 알파 채널이 없어야 합니다. 바꿀 때는 `AppIcon.appiconset/AppIcon.png`만 교체합니다. |

구조 설명은 [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)의 "iOS 앱 구조"를 보세요.

## 디자인

앱 아이콘과 같은 색과 서식을 씁니다. 값은 모두 `Vitalog/Theme.swift`에 있어서 색을 바꿀 때는 이 파일만 고칩니다.

| 이름 | 값 | 용도 |
| --- | --- | --- |
| `mint` | `#1AC8A4` | 아이콘 그라데이션의 밝은 쪽, 로고 |
| `teal` | `#044E60` | 아이콘 그라데이션의 어두운 쪽, 상단 바, 제목과 섹션 머리글 |
| `accent` | `#087A70` | 버튼과 링크 색(앱 전체 `tint`) |
| `coral` | `#FF6B5E` | 아이콘의 끝점 |
| `alert` | `#D9453A` | 오류와 만료 경고 글자 |
| `background` | `#EFF5F5` | 화면 배경 |

- 라이트 모드만 지원합니다 (`Info.plist`의 `UIUserInterfaceStyle`이 `Light`).
- 로고(`LogoMark`)는 아이콘의 심전도 선을 같은 좌표로 그린 것이라, 아이콘을 바꾸면 `PulseShape`와 함께 맞춥니다.

## 설정

접속 주소와 공개 키는 git에서 제외된 `Secrets.xcconfig`에서 읽습니다.

```bash
cp Secrets.xcconfig.example Secrets.xcconfig
```

| 키 | 값 |
| --- | --- |
| `SUPABASE_URL` | Supabase 프로젝트 주소 (`https://<프로젝트 ref>.supabase.co`). xcconfig에서 `//`가 주석으로 해석되지 않도록 `https:/$()/<프로젝트 ref>.supabase.co`처럼 씁니다. |
| `SUPABASE_PUBLISHABLE_KEY` | 공개 키. 대시보드의 Project Settings > API Keys에 있는 Publishable key입니다. |

- 서비스 키(service_role, secret)는 절대 넣지 않습니다. 앱은 공개 키와 로그인 세션만 씁니다.
- 서버 주소를 바꾸면 앱은 서버별로 따로 저장한 백필 기록과 동기화 기록을 쓰므로, 새 서버에서는 처음부터 최초 동기화를 합니다.

## 빌드와 설치

저장소 루트에서 실행합니다. `<기기 UDID>`는 `CLAUDE.md`의 프로젝트 값을 보세요.

```bash
xcodebuild -project ios/Vitalog.xcodeproj -scheme Vitalog -destination 'id=<기기 UDID>' -derivedDataPath build -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device <기기 UDID> build/Build/Products/Debug-iphoneos/Vitalog.app
```

- 앱을 지우지 않고 덮어 설치합니다. 지우면 기기에 저장된 최초 동기화 진행 기록과 동기화 기록이 사라집니다.
- 무료 개발자 계정은 프로파일이 만료되는 7일 뒤부터 앱이 실행되지 않습니다. 설치된 프로파일이 아직 유효하면 단순히 덮어 설치해도 만료일이 연장되지 않습니다.

## 주 1회 재설치

아이폰을 Mac에 연결하고(잠금 해제, 이 Mac 신뢰) 저장소 루트에서 실행합니다.

```bash
scripts/reinstall.sh
```

- 하는 일: 기기 연결 확인 → 이 앱(`com.kudongku.vitalog`)의 프로파일만 백업해 두고 Xcode가 새로 받게 함 → 빌드 → 앱을 지우지 않고 덮어 설치 → 새 만료 시각과 다음 재설치 권장일 출력. 다른 앱의 프로파일은 건드리지 않고, 빌드가 실패하면 프로파일을 원래대로 되돌립니다.
- `--launch`를 붙이면 설치 후 앱을 실행합니다 (기기 잠금을 풀어 둬야 합니다). 기기를 바꾸면 환경 변수 `VITALOG_DEVICE`에 UDID를 넣습니다.
- 만료 직전에 하지 말고, 앱 화면의 "상태"에 보이는 만료일 하루 전까지 합니다. 요일을 정해 캘린더 반복 알림을 두면 놓치지 않습니다.
- 만료일이 7일보다 짧게 나오면 프로파일이 갱신되지 않은 것이므로 Xcode의 Apple ID 로그인 상태를 확인하세요.

## 실행할 때 알아둘 점

- HealthKit은 기기가 잠기면 읽을 수 없습니다. 최초 동기화는 충전기에 꽂고 화면을 켜 둔 채 진행하세요. 잠기면 멈췄다가 잠금을 풀면 이어 갑니다.
- 처음 실행하면 HealthKit 읽기 권한을 요청합니다. 복약과 시력 처방은 항목별 권한 요청이 따로 있습니다.
- 시뮬레이터에는 실제 건강 데이터가 없으므로 데이터 검증은 실기기에서 합니다.

## 의존성

- [supabase-swift](https://github.com/supabase/supabase-swift) (Swift Package Manager)
