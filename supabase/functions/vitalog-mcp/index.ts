import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { type Context, Hono } from "hono";
import { z } from "zod";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const DATE = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "YYYY-MM-DD 형식");

const SCHEMA_GUIDE = `Vitalog 건강 데이터 DB (Postgres, 모든 테이블은 로그인한 사용자 본인 행만 보입니다).
시각(*_at)은 UTC timestamptz이고, day 컬럼은 기기 시간대(서울) 기준 date입니다.

- daily_stats(type, day, sum, avg, min, max): 일별 통계. 아이폰과 워치 중복이 제거된 값이라 걸음 수 같은 합계는 반드시 이 테이블을 쓰세요. 합계형(step_count 등)은 sum, 측정형(heart_rate 등)은 avg/min/max만 채워집니다.
- activity_summaries(day, active_energy_kcal, exercise_time_min, stand_hours와 각 *_goal): 활동 링
- workouts(uuid, activity_type, start_at, end_at, duration_s, total_energy_kcal, total_distance_m)
- category_samples(type, value, start_at, end_at): 수면 단계(type='sleep_analysis', value는 asleep_core/asleep_deep/asleep_rem/awake/in_bed) 등
- quantity_samples(type, value, start_at, end_at): 수치형 원본. 약 200만 행이므로 반드시 type과 start_at 범위로 좁히세요. 이 값을 그냥 더하면 아이폰과 워치 중복으로 부풀려집니다.
- other_samples(type, payload jsonb, start_at, end_at): 심전도, 설문 등
- characteristics(biological_sex, blood_type, date_of_birth), sources(id, name, product_type), sync_log

조회문 하나(SELECT 또는 WITH)만 쓸 수 있고, 행은 최대 1000개까지 돌려줍니다.`;

const RESOURCE_URL = `${SUPABASE_URL}/functions/v1/vitalog-mcp`;
const METADATA_PATH = "/oauth-protected-resource";
const METADATA_URL = `${RESOURCE_URL}${METADATA_PATH}`;

const app = new Hono();

function unauthorized(c: Context, description: string) {
  return c.json({ error: "unauthorized", error_description: description }, 401, {
    "WWW-Authenticate": `Bearer resource_metadata="${METADATA_URL}"`,
  });
}

async function userClient(req: Request): Promise<SupabaseClient | null> {
  const match = req.headers.get("Authorization")?.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${match[1]}` } },
    auth: { persistSession: false },
  });
  try {
    const { data, error } = await client.auth.getClaims(match[1]);
    if (error || !data?.claims.sub || data.claims.role !== "authenticated") return null;
    return client;
  } catch {
    return null;
  }
}

function buildServer(db: SupabaseClient): McpServer {
  const server = new McpServer({ name: "vitalog", version: "0.1.0" });

  const call = async (fn: string, args?: Record<string, unknown>) => {
    const { data, error } = await db.rpc(fn, args);
    if (error) {
      return {
        isError: true,
        content: [{ type: "text" as const, text: `오류: ${error.message}` }],
      };
    }
    return { content: [{ type: "text" as const, text: JSON.stringify(data) }] };
  };

  server.registerTool("list_metrics", {
    description:
      "저장된 건강 데이터의 유형별 기간과 건수를 보여 줍니다. 어떤 데이터가 있는지 모를 때 가장 먼저 호출하세요. daily_stats의 type 값이 metric_trend에 넣을 수 있는 이름입니다.",
    inputSchema: {},
  }, () => call("mcp_list_metrics"));

  server.registerTool("daily_summary", {
    description:
      "기간별 일별 걸음 수, 활동 에너지(kcal), 운동 시간(분)을 돌려줍니다. 기기에서 중복을 제거해 계산한 값입니다. 한 번에 최대 400일입니다.",
    inputSchema: { from: DATE, to: DATE },
  }, ({ from, to }) => call("mcp_daily_summary", { p_from: from, p_to: to }));

  server.registerTool("sleep_summary", {
    description:
      "날짜별 수면 요약입니다. 총 수면 시간(asleep_min), 코어/깊은/렘 수면, 깨어 있던 시간, 침대에 있던 시간, 취침과 기상 시각(서울 시간)을 분 단위로 돌려줍니다. night는 기상한 날짜이고, 기간 평균도 함께 줍니다.",
    inputSchema: { from: DATE, to: DATE },
  }, ({ from, to }) => call("mcp_sleep_summary", { p_from: from, p_to: to }));

  server.registerTool("workouts", {
    description:
      "기간별 운동 목록(최근 순)과 종류별 요약(횟수, 총 시간, 에너지, 거리)을 돌려줍니다. 횟수는 total_count입니다. 목록은 limit개까지만 주므로 많은 기간은 요약을 보세요.",
    inputSchema: { from: DATE, to: DATE, limit: z.number().int().min(1).max(200).default(30) },
  }, ({ from, to, limit }) => call("mcp_workouts", { p_from: from, p_to: to, p_limit: limit }));

  server.registerTool("metric_trend", {
    description:
      "daily_stats의 한 유형을 일, 주, 월 단위로 묶은 추이입니다. 구간마다 일수, 평균, 최솟값, 최댓값을 주고, 합계형 유형은 total도 줍니다. 유형 이름은 list_metrics의 daily_stats type을 쓰세요 (예: resting_heart_rate, heart_rate_variability_sdnn, body_mass, vo2_max, step_count). 합계형은 평균이 하루 합계의 평균입니다.",
    inputSchema: {
      type: z.string(),
      from: DATE,
      to: DATE,
      bucket: z.enum(["day", "week", "month"]).default("week"),
    },
  }, ({ type, from, to, bucket }) =>
    call("mcp_metric_trend", { p_type: type, p_from: from, p_to: to, p_bucket: bucket }));

  server.registerTool("run_sql", {
    description: `다른 도구로 답하기 어려운 질문을 위한 읽기 전용 SQL 조회입니다. 8초 안에 끝나야 합니다.\n\n${SCHEMA_GUIDE}`,
    inputSchema: {
      query: z.string(),
      max_rows: z.number().int().min(1).max(1000).default(200),
    },
  }, ({ query, max_rows }) => call("mcp_run_sql", { p_query: query, p_max_rows: max_rows }));

  return server;
}

app.get(`*${METADATA_PATH}`, (c) =>
  c.json({
    resource: RESOURCE_URL,
    authorization_servers: [`${SUPABASE_URL}/auth/v1`],
    bearer_methods_supported: ["header"],
  }));

app.all("*", async (c) => {
  try {
    const db = await userClient(c.req.raw);
    if (!db) return unauthorized(c, "유효한 액세스 토큰이 필요합니다");
    const server = buildServer(db);
    const transport = new WebStandardStreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true,
    });
    await server.connect(transport);
    return await transport.handleRequest(c.req.raw);
  } catch (e) {
    return c.json({ error: (e as Error).message }, 500);
  }
});

Deno.serve(app.fetch);
