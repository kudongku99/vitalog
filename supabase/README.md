# supabase

Vitalog의 서버 쪽입니다. DB 스키마(마이그레이션)와 Supabase 설정이 있고, MCP 서버 Edge Function도 있습니다. 개발과 시험은 모두 원격 Supabase 프로젝트에서 합니다.

## 구성

| 경로 | 내용 |
| --- | --- |
| `migrations/` | DB 스키마 마이그레이션. 스키마의 원본입니다. |
| `config.toml` | Supabase CLI 설정 (프로젝트 ID `vitalog`) |
| `functions/vitalog-mcp/` | MCP 서버 Edge Function (TypeScript, Deno). 도구 6개. OAuth 토큰을 검증합니다. |

테이블 구조와 설계 이유는 [../docs/DB_DESIGN.md](../docs/DB_DESIGN.md)를 보세요.

## 프로젝트 연결

프로젝트 ref는 `CLAUDE.md`에 있습니다. 처음 한 번만 하면 됩니다.

```bash
supabase login
```

```bash
supabase link --project-ref <프로젝트 ref>
```

## 마이그레이션

| 용도 | 명령 |
| --- | --- |
| 새 마이그레이션 파일 만들기 | `supabase migration new <이름>` |
| 적용될 마이그레이션 미리 보기 | `supabase db push --dry-run` |
| 원격 DB에 적용 | `supabase db push` |

- DB 구조 변경은 반드시 마이그레이션 파일로 합니다. 대시보드에서 직접 고치지 않습니다.
- 모든 테이블에 RLS를 켜고 정책은 `user_id = auth.uid()` 기준으로 겁니다.
- 마이그레이션을 바꾸면 [../docs/DB_DESIGN.md](../docs/DB_DESIGN.md)도 함께 고칩니다.

### 주의

- 시험용 DB가 따로 없어서 `supabase db push`는 바로 원격 DB를 바꿉니다. 적용 전에 SQL을 다시 읽고 `--dry-run`으로 대상 파일을 확인한 뒤 실행합니다.
- 이미 원격에 적용한 마이그레이션 파일을 지울 때는 `supabase migration repair`로 원격 이력도 맞춥니다.
- `supabase db reset --linked`는 원격의 Auth 계정과 Supabase 기본 트리거까지 지우므로 되도록 쓰지 않습니다.
- 원격 데이터를 지우는 작업은 사용자 확인을 받은 뒤에 실행합니다.

## MCP 서버

`functions/vitalog-mcp/`에 있습니다. 도구는 `list_metrics`, `daily_summary`, `sleep_summary`, `workouts`, `metric_trend`, `run_sql`이고, 집계는 마이그레이션의 `mcp_*` 함수가 합니다. 명령은 다음과 같습니다.

| 용도 | 명령 |
| --- | --- |
| 배포 | `supabase functions deploy vitalog-mcp --no-verify-jwt` |
| 도구 시험 | `npx @modelcontextprotocol/inspector` (주소 `https://<프로젝트 ref>.supabase.co/functions/v1/vitalog-mcp`, 전송 방식 Streamable HTTP) |
| Claude Code 연결 | 클라이언트를 미리 등록한 뒤 `claude mcp add --transport http --client-id <클라이언트 ID> --callback-port <포트> vitalog https://<프로젝트 ref>.supabase.co/functions/v1/vitalog-mcp` 로 추가하고, 대화형 세션에서 `/mcp`로 인증합니다. 콜백 주소 `http://127.0.0.1:<포트>/callback`을 클라이언트의 리디렉션 주소로 등록해 두어야 합니다. 클라이언트 ID 없이 추가한 항목은 동적 등록이 꺼져 있어 실패하니 지우고 다시 추가하세요. |

- `--no-verify-jwt`는 Supabase 게이트웨이의 기본 JWT 검증을 끄는 옵션입니다. 토큰 검증은 서버 코드가 직접 하므로(토큰이 없으면 401), 끄지 않으면 인증 없이 열려야 하는 메타데이터 경로(`/oauth-protected-resource`)가 막힙니다.
- 배포는 사용자 확인을 받은 뒤에 실행합니다.

## OAuth 서버와 동의 화면

Claude가 건강 데이터를 읽으려면 사용자가 동의 화면에서 승인해야 합니다. 원격 프로젝트의 설정은 대시보드에서 합니다. `config.toml`의 Auth 설정은 CLI 기본값이라 원격에 맞지 않을 수 있으므로 `supabase config push`는 쓰지 않습니다.

- **OAuth 서버**: 대시보드의 Authentication > OAuth Server에서 켭니다. 동적 등록은 꺼 둡니다.
- **클라이언트 등록**: 대시보드의 Authentication > OAuth Apps > Add a new client에서 만듭니다. 리디렉션 주소는 정확히 일치해야 하며 와일드카드가 없습니다. claude.ai 커넥터의 콜백 주소는 `https://claude.ai/api/mcp/auth_callback`이고 `claude.com` 주소로 바뀔 수 있어 둘 다 등록합니다.
- **동의 화면**: [../consent/](../consent/oauth/consent/index.html)의 정적 HTML 한 장이고, Cloudflare Pages의 `vitalog-consent` 프로젝트(`https://vitalog-consent.pages.dev`)에 배포했습니다. 대시보드에서 Site URL을 이 주소로, 동의 화면 경로를 `/oauth/consent`로 맞춥니다. Auth는 사용자를 `<Site URL>/oauth/consent?authorization_id=...`로 보냅니다.
- **동의 화면 배포**: `consent/config.js`가 git에서 제외돼 있어 git 연동 대신 폴더를 직접 올립니다. 최신 `wrangler` 4.x는 Pages 프로젝트를 만들지 못해 3.x를 `npx`로만 실행합니다 (프로젝트에 추가하지 않습니다). 처음 한 번은 `npx wrangler@3.114.0 login`과 `npx wrangler@3.114.0 pages project create vitalog-consent --production-branch main`이 필요합니다 (Cloudflare 계정의 이메일 인증이 되어 있어야 합니다).

  ```bash
  mkdir -p build/consent && cp -R consent/index.html consent/oauth consent/config.js consent/_headers build/consent/
  ```

  ```bash
  npx wrangler@3.114.0 pages deploy build/consent --project-name vitalog-consent --branch main
  ```

  `_headers`는 다른 사이트의 프레임 안에 동의 화면을 띄우는 공격(클릭재킹)을 막는 보안 헤더입니다.
- **동의 화면 설정 파일**: `consent/config.example.js`를 `consent/config.js`로 복사해 프로젝트 주소와 공개 키(Publishable key)를 채웁니다. 이 파일은 git에서 제외됩니다.
- **토큰 검증**: MCP 서버가 `supabase-js`의 `auth.getClaims`로 직접 합니다. Supabase가 권하는 `@supabase/server` 미들웨어는 비대칭 서명 키가 필요하고 새 패키지를 들여와야 해서 쓰지 않았습니다.

## 운영

앱이 매일 동기화하는 동안 하는 정기 작업입니다. 원격 데이터를 바꾸거나 지우는 명령은 실행 전에 사용자 확인을 받습니다.

### 용량 확인

```bash
supabase inspect db db-stats --linked
```

```bash
supabase inspect db table-stats --linked
```

| DB 크기 | 행동 |
| --- | --- |
| 350MB | 경고. 테이블별 크기로 무엇이 차지하는지 봅니다. |
| 450MB | 아래 정기 정리를 하고, 그래도 부족하면 보관 기간을 줄입니다. 그다음에 Pro 전환(월 25달러)을 검토합니다. |

### 원본 정기 정리 (월 1회)

수치형 원본은 보관 기간(심박수 6개월, 고빈도 17개 유형 3개월)을 넘으면 지웁니다. 유형 목록의 기준은 `ios/Vitalog/HealthCatalog.swift`의 `QuantityRetention`입니다. `daily_stats`는 지우지 않고, 지운 원본은 아이폰의 HealthKit에 그대로 있습니다.

```bash
supabase db query --linked "delete from quantity_samples where (type = 'heart_rate' and start_at < now() - interval '6 months') or (type in ('active_energy_burned','basal_energy_burned','distance_walking_running','step_count','physical_effort','walking_speed','walking_step_length','walking_double_support_percentage','walking_asymmetry_percentage','headphone_audio_exposure','environmental_audio_exposure','respiratory_rate','stair_ascent_speed','stair_descent_speed','environmental_sound_reduction','flights_climbed','distance_cycling') and start_at < now() - interval '3 months')"
```

- 지운 뒤에도 파일 크기는 바로 줄지 않고, 새 행이 그 공간을 다시 씁니다. 크기를 실제로 줄여야 하면 `vacuum full quantity_samples`를 쓰되 테이블이 잠기므로 동기화가 없는 시간에 실행합니다.
- 보관 기간을 바꾸면 앱의 `QuantityRetention`과 이 SQL, `docs/DB_DESIGN.md`의 "용량 계획"을 함께 고칩니다.

### 백업 (월 1회)

```bash
supabase db dump --linked -f <저장소 밖 경로>/vitalog-schema-$(date +%F).sql
```

```bash
supabase db dump --linked --data-only --use-copy -f <저장소 밖 경로>/vitalog-data-$(date +%F).sql
```

- 건강 데이터가 들어 있으므로 받은 파일은 바로 암호화해서 보관하고, 저장소와 공개된 곳에는 두지 않습니다. 예: `gzip <파일>` 뒤에 `openssl enc -aes-256-cbc -pbkdf2 -in <파일>.gz -out <파일>.gz.enc`.
- 로그인 계정(Auth)은 덤프에 포함되지 않습니다. 복원이 필요하면 계정을 다시 만들고 `user_id`를 새 계정 값으로 맞춰야 합니다.

### 일시정지

앱이 매일 동기화하면 무료 프로젝트는 활동 상태로 유지됩니다. 일주일 넘게 동기화가 끊기면 일시정지될 수 있습니다. 그런 일정이 있으면 출발 전에 앱을 한 번 동기화하고, 일시정지되면 대시보드에서 복원합니다. 복원 가능 기간은 [Supabase 문서](https://supabase.com/docs/guides/platform/free-project-pausing)를 확인하세요.

### 앱 재설치 (주 1회)

무료 개발자 계정의 앱은 프로파일 만료(7일)로 멈춥니다. 아이폰을 연결하고 저장소 루트에서 실행합니다. 자세한 내용은 [../ios/README.md](../ios/README.md)를 보세요.

```bash
scripts/reinstall.sh
```

## 비밀 값

- 서비스 키(service_role, secret)는 앱 코드, 저장소, 로그 어디에도 넣지 않습니다.
- `.temp/`는 git에서 제외되어 있습니다.

## 원격 프로젝트

- 프로젝트 ref는 `CLAUDE.md`에 있고, CLI 로그인과 `supabase link`가 되어 있습니다.
- 무료 한도는 DB 500MB입니다. 올릴 범위는 정했습니다 ([../docs/DB_DESIGN.md](../docs/DB_DESIGN.md)의 "용량 계획").
