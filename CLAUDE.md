# Vitalog

아이폰 HealthKit 데이터를 직접 만든 iOS 앱으로 Supabase에 동기화하고, Supabase Edge Functions의 원격 MCP 서버를 통해 Claude 웹과 모바일에서 조회하는 개인용 프로젝트입니다.

## 현재 단계

- 현재: 개발 단계를 모두 마치고 운영 중입니다. 앱은 매주 `scripts/reinstall.sh`로 재설치합니다.

## 폴더 구조

- `ios/`: SwiftUI 앱 (Xcode 프로젝트). Supabase 연동은 `supabase-swift` 패키지를 쓰고, 접속 주소와 공개 키는 git에서 제외된 `ios/Secrets.xcconfig`에서 읽습니다. 값은 원격 Supabase 프로젝트 기준이며, `ios/Secrets.xcconfig.example`을 복사해 쓰면 됩니다.
- `supabase/migrations/`: DB 스키마 마이그레이션
- `supabase/functions/vitalog-mcp/`: MCP 서버 Edge Function (TypeScript, Deno)
- `scripts/`: 운영 스크립트. `reinstall.sh`는 주 1회 앱 재설치(프로파일 갱신, 빌드, 덮어 설치)입니다.
- `consent/`: OAuth 동의 화면 (정적 HTML 한 장, supabase-js). 접속 주소와 공개 키는 git에서 제외된 `consent/config.js`에서 읽습니다. `consent/config.example.js`를 복사해 쓰면 됩니다. Cloudflare Pages(`vitalog-consent`)에 폴더를 직접 올려 배포합니다.
- `docs/`: 설계 문서
  - `docs/ARCHITECTURE.md`: 아키텍처 정의서 (시스템 구성, 데이터 흐름, iOS 앱 구조)
  - `docs/DB_DESIGN.md`: DB 설계서 (테이블 명세, 설계 원칙, 인덱스, RLS, 용량)
  - `docs/PROMPTS.md`: MCP 처음 사용자를 위한 추천 프롬프트와 지표 설명
- `README.md`, `ios/README.md`, `supabase/README.md`: 저장소 소개, 앱 사용법, 서버 사용법

## 프로젝트 값

- 앱 이름: `Vitalog`
- 번들 ID: `com.kudongku.vitalog` (첫 기기 빌드 전까지만 변경 가능, 이후 변경 금지)
- 기기 UDID: `00008140-000268482109801C`
- Supabase 프로젝트 ref: `quzqrjeicrmvgwrulhyj` (CLI 로그인과 `supabase link` 완료)
- 개발 팀 ID: `7Y4KAM478U` (개인 팀)

## 명령어

| 용도                          | 명령                                                                                                                                                           |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 기기용 빌드                   | `xcodebuild -project ios/Vitalog.xcodeproj -scheme Vitalog -destination 'id=00008140-000268482109801C' -derivedDataPath build -allowProvisioningUpdates build` |
| 기기에 설치                   | `xcrun devicectl device install app --device 00008140-000268482109801C build/Build/Products/Debug-iphoneos/Vitalog.app`                                        |
| 주 1회 앱 재설치 | `scripts/reinstall.sh` |
| 새 마이그레이션 파일          | `supabase migration new <이름>`                                                                                                                                |
| 적용될 마이그레이션 미리 보기 | `supabase db push --dry-run`                                                                                                                                   |
| 원격 DB에 마이그레이션 적용   | `supabase db push`                                                                                                                                             |
| MCP 서버 배포                 | `supabase functions deploy vitalog-mcp --no-verify-jwt`                                                                                                        |
| MCP 도구 시험                 | `npx @modelcontextprotocol/inspector`                                                                                                                          |

## 절대 규칙

- Supabase 서비스 키(service_role 또는 secret 키)는 앱 코드, 저장소, 로그 어디에도 넣지 않습니다. 앱은 공개 키(anon 또는 publishable)와 로그인 세션만 씁니다.
- 비밀 값은 git에서 제외된 파일(`ios/Secrets.xcconfig`)에만 둡니다.
- 모든 테이블에 RLS를 켜고, 정책은 `user_id = auth.uid()` 기준으로 겁니다.
- DB 구조 변경은 반드시 마이그레이션 파일로 합니다. 대시보드에서 직접 고치지 않습니다.
- 실제 건강 수치를 로그, 커밋, 테스트 데이터에 남기지 않습니다. 테스트에는 지어낸 값을 씁니다.
- 원격 DB 적용(`supabase db push`), Edge Function 배포, 원격 데이터 삭제는 사용자에게 확인받은 뒤 실행합니다.

## 데이터 원칙

- 원본 샘플은 HealthKit UUID를 기본 키로 upsert합니다. 같은 데이터를 여러 번 올려도 결과가 같아야 합니다.
- 시간은 UTC(timestamptz)로 저장하고, 일별 통계의 날짜는 기기 시간대 기준입니다.
- 걸음 수 같은 합계는 HealthKit 통계 조회로 계산한 `daily_stats`를 우선 씁니다. 원본을 그냥 더하면 아이폰과 워치 중복으로 값이 부풀려집니다.
- 단위는 유형별 표준 단위 하나로 통일합니다.

## HealthKit 전제

- 기기가 잠겨 있으면 HealthKit을 읽을 수 없습니다. 동기화는 잠금 해제 시점에 일어난다고 가정하고 설계합니다.
- 앵커와 백필 진행 기록은 업로드가 성공한 뒤에만 저장합니다.
- 옵저버의 완료 처리는 성공과 실패를 가리지 않고 모든 경로에서 호출합니다.
- 백그라운드 실행 시간은 짧으므로 작은 묶음으로 나눠 올립니다.
- 실제 데이터 검증은 실기기에서 합니다.

## 무료 개발자 계정

- 설치한 앱은 프로파일이 만료되는 7일 뒤부터 실행되지 않습니다. 재설치는 앱을 지우지 않고 덮어 설치해 기기에 저장된 동기화 기록을 유지하며, 설치된 프로파일이 유효하면 덮어 설치만으로는 만료일이 연장되지 않으므로 `scripts/reinstall.sh`로 프로파일을 새로 받습니다.
- 유료 개발자 계정이 필요한 기능을 추가하기 전에는 먼저 알립니다.

## 작업 방식

- 사용자는 Swift와 iOS 개발이 처음입니다. 변경할 때마다 무엇을 왜 바꿨는지 짧게 설명합니다.
- 한 번에 작은 단위로 작업하고, 빌드 성공을 확인한 뒤 다음으로 넘어갑니다.
- 새 라이브러리나 패키지를 추가하기 전에 이유를 설명하고 확인받습니다.
- 코드 주석은 요청할 때만 작성합니다.
- 저장소에는 현재 시점에 필요한 코드만 남깁니다. 검증용으로 잠시 만든 테스트 파일, 시험용 테이블과 마이그레이션, 임시 화면이나 코드는 목적을 다하면 지우고 커밋에 넣지 않습니다. 검증은 그 자리에서 실행해 결과만 보고합니다.
- 코드를 수정할 때는 영향받는 문서도 같은 작업에서 함께 고칩니다. 문서가 코드와 어긋난 채로 두지 않습니다.
  - DB 마이그레이션(테이블, 컬럼, 인덱스, RLS, 함수) 변경: `docs/DB_DESIGN.md`. 구조가 달라지면 `docs/ARCHITECTURE.md`도 확인합니다.
  - 앱 구조, 동기화 흐름 변경: `docs/ARCHITECTURE.md`
  - MCP 서버, 인증(OAuth), 동의 화면, 환경, 배포 변경: `supabase/README.md`
  - 파일 추가와 삭제, 설정 방법, 명령어, 실행 방법 변경: 해당 폴더의 `README.md` (`ios/README.md`, `supabase/README.md`)와 루트 `README.md`
  - 새 문서를 추가하거나 폴더 구조가 바뀌면 `CLAUDE.md`의 폴더 구조와 루트 `README.md`의 문서 목록도 고칩니다.
  - 작업을 마치기 전에 위 문서 중 고칠 것이 없는지 확인하고, 고친 문서와 이유를 짧게 보고합니다.
- `docs/DB_DESIGN.md`, `docs/ARCHITECTURE.md`, 각 `README.md`, `CLAUDE.md`의 갱신은 따로 커밋하지 않고, 관련 작업 커밋에 함께 넣습니다. 커밋을 나누자고 제안할 때도 이 문서 변경은 별도 커밋으로 떼지 않습니다.
- 시험용 DB가 따로 없어서 마이그레이션은 원격에 바로 적용됩니다. 적용 전에 SQL을 다시 읽고 `supabase db push --dry-run`으로 대상 파일을 확인합니다.
- 이미 원격 DB에 적용한 마이그레이션 파일을 지울 때는 `supabase migration repair`로 원격 이력도 맞춰야 하므로, 사용자에게 확인받고 진행합니다. `supabase db reset --linked`는 원격의 Auth 계정과 Supabase 기본 트리거까지 지우므로 되도록 쓰지 않습니다.
- 설명은 한국어 존댓말로 하고, 한자는 쓰지 않습니다.
