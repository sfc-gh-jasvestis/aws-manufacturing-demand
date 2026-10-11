import { NextResponse } from 'next/server';
import { demoPlatform } from '@/lib/platform';
import { executeQuery } from '@/lib/snowflake';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET() {
  try {
    const [kpis, trend, types, items, freshness, risk, holdout, forecast, live, liveSummary, anomalies, alerts] = await Promise.all([
      executeQuery<{ TITLE: string; DISPLAY: string; STATUS: string }>(
        'SELECT TITLE, DISPLAY, STATUS FROM CURATED.KPI_SUMMARY ORDER BY SORT_ORDER'),
      executeQuery<{ PERIOD: string; EXCEPTIONS: number | null; STOCKOUTS: number | null }>(`
        SELECT TO_CHAR(METRIC_DATE, 'YYYY-MM-DD') AS PERIOD,
               EXCEPTION_COUNT AS EXCEPTIONS, STOCKOUT_COUNT AS STOCKOUTS
        FROM CURATED.TREND_ANALYSIS ORDER BY METRIC_DATE`),
      executeQuery<{ EXCEPTION_TYPE: string; EXCEPTIONS: number; STOCKOUTS: number }>(`
        SELECT EXCEPTION_TYPE, EXCEPTION_COUNT AS EXCEPTIONS, STOCKOUT_COUNT AS STOCKOUTS
        FROM CURATED.EXCEPTION_SUMMARY ORDER BY STOCKOUT_COUNT DESC, EXCEPTION_COUNT DESC`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ENTITY_ID, ENTITY_NAME, REGION, CATEGORY, RISK_TIER, EVENT_COUNT, DEMAND_UNITS, EXCEPTION_COUNT,
               STOCKOUT_COUNT, EXPEDITED_COUNT, EXCEPTION_STOCKOUT_PCT, PLAN_REVIEW_PCT, ROUND(DEMAND_VALUE_SGD / 1e6, 2) AS DEMAND_VALUE_SGD_M
        FROM CURATED.PERFORMANCE_SUMMARY ORDER BY ENTITY_ID LIMIT 200`),
      executeQuery<{ RAW_WATERMARK: string | null; CURATED_WATERMARK: string | null }>(`
        SELECT (SELECT TO_CHAR(MAX(EVENT_DATE), 'YYYY-MM-DD') FROM RAW.ITEM_DAILY) AS RAW_WATERMARK,
               (SELECT TO_CHAR(MAX(METRIC_DATE), 'YYYY-MM-DD') FROM CURATED.TREND_ANALYSIS) AS CURATED_WATERMARK`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ENTITY_ID, TO_CHAR(SCORED_AS_OF, 'YYYY-MM-DD') AS SCORED_AS_OF, STOCKOUT_PROB_7D, RISK_BAND
        FROM ML.STOCKOUT_RISK_SCORES ORDER BY STOCKOUT_PROB_7D DESC`),
      executeQuery<Record<string, string | number | null>>(
        'SELECT N, BASE_RATE, PRECISION_AT_50, RECALL_AT_50 FROM ML.STOCKOUT_RISK_HOLDOUT_METRICS'),
      executeQuery<Record<string, string | number | null>>(`
        SELECT TO_CHAR(FORECAST_DATE, 'YYYY-MM-DD') AS PERIOD, DEMAND_UNITS, LOWER_BOUND, UPPER_BOUND
        FROM ML.DEMAND_FORECAST ORDER BY FORECAST_DATE`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ITEM_ID, TO_CHAR(EVENT_TS, 'YYYY-MM-DD HH24:MI:SS') AS EVENT_TS, ROUND(ORDER_VALUE_SGD, 0) AS ORDER_VALUE_SGD,
               REQUESTED_LEAD_HRS, STATUS, TO_CHAR(LOADED_AT, 'YYYY-MM-DD HH24:MI:SS TZH:TZM') AS LOADED_AT
        FROM RAW.LIVE_DEMAND ORDER BY EVENT_TS DESC LIMIT 25`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT COUNT(*) AS N, COUNT_IF(STATUS = 'EXCEPTION') AS EXCEPTIONS,
               TO_CHAR(MAX(LOADED_AT), 'YYYY-MM-DD HH24:MI:SS TZH:TZM') AS LAST_LOADED,
               ROUND(MEDIAN(DATEDIFF('second', SENT_TS, CONVERT_TIMEZONE('UTC', LOADED_AT)::TIMESTAMP_NTZ)), 0) AS MEDIAN_LAG_S
        FROM RAW.LIVE_DEMAND`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ENTITY_ID, TO_CHAR(EVENT_DATE, 'YYYY-MM-DD') AS EVENT_DATE, ROUND(FORECAST_ERROR, 2) AS FORECAST_ERROR,
               ROUND(EXPECTED, 2) AS EXPECTED, ROUND(UPPER_BOUND, 2) AS UPPER_BOUND
        FROM ML.FORECAST_ERROR_ANOMALIES WHERE IS_ANOMALY ORDER BY EVENT_DATE DESC, ENTITY_ID LIMIT 50`),
      executeQuery<Record<string, string | number | null>>(`
        SELECT ITEM_ID, TO_CHAR(EVENT_TS, 'YYYY-MM-DD HH24:MI:SS') AS EVENT_TS, ROUND(ORDER_VALUE_SGD, 0) AS ORDER_VALUE_SGD,
               REQUESTED_LEAD_HRS, SOP_HINT
        FROM APP.ALERT_LOG ORDER BY ALERTED_AT DESC, EVENT_TS DESC LIMIT 25`),
    ]);
    const numberOrNull = (value: unknown): number | null => {
      if (value === null || value === undefined) return null;
      const numeric = Number(value);
      if (!Number.isFinite(numeric)) throw new Error('Non-numeric measure in curated contract');
      return numeric;
    };
    const watermark = freshness[0]?.CURATED_WATERMARK ?? null;
    const ageDays = watermark ? (Date.now() - Date.parse(`${watermark}T00:00:00Z`)) / 86400000 : null;
    return NextResponse.json({
      platform: demoPlatform(),
      kpiCards: kpis.map((row) => ({ title: row.TITLE, value: row.DISPLAY, status: row.STATUS })),
      timeseries: trend.map((row) => ({ period: row.PERIOD, exceptions: numberOrNull(row.EXCEPTIONS), stockouts: numberOrNull(row.STOCKOUTS) })),
      categories: types.map((row) => ({ category: row.EXCEPTION_TYPE, exceptions: numberOrNull(row.EXCEPTIONS), stockouts: numberOrNull(row.STOCKOUTS) })),
      entities: items.map((row) => ({
        id: row.ENTITY_ID, name: row.ENTITY_NAME, region: row.REGION, category: row.CATEGORY, tier: row.RISK_TIER,
        units: numberOrNull(row.DEMAND_UNITS), exceptions: numberOrNull(row.EXCEPTION_COUNT), stockouts: numberOrNull(row.STOCKOUT_COUNT),
        expedited: numberOrNull(row.EXPEDITED_COUNT), stockoutRate: numberOrNull(row.EXCEPTION_STOCKOUT_PCT),
        value: numberOrNull(row.DEMAND_VALUE_SGD_M), planReview: numberOrNull(row.PLAN_REVIEW_PCT), events: numberOrNull(row.EVENT_COUNT),
      })),
      reviewRisk: items.map((row) => ({
        name: row.ENTITY_NAME, compliance: numberOrNull(row.PLAN_REVIEW_PCT), stockouts: numberOrNull(row.STOCKOUT_COUNT),
      })).filter((row) => row.compliance !== null && row.stockouts !== null),
      sourceWatermark: watermark,
      rawWatermark: freshness[0]?.RAW_WATERMARK ?? null,
      stale: ageDays === null || ageDays > 2,
      pipelineBehind: freshness[0]?.RAW_WATERMARK !== watermark,
      requestedAt: new Date().toISOString(),
      synthetic: true,
      risk: risk.map((row) => ({
        id: row.ENTITY_ID, scoredAsOf: row.SCORED_AS_OF,
        probability: numberOrNull(row.STOCKOUT_PROB_7D), band: row.RISK_BAND,
      })),
      holdout: holdout[0] ? {
        n: numberOrNull(holdout[0].N), baseRate: numberOrNull(holdout[0].BASE_RATE),
        precision: numberOrNull(holdout[0].PRECISION_AT_50), recall: numberOrNull(holdout[0].RECALL_AT_50),
      } : null,
      forecast: forecast.map((row) => ({
        period: row.PERIOD, value: numberOrNull(row.DEMAND_UNITS),
        lower: numberOrNull(row.LOWER_BOUND), upper: numberOrNull(row.UPPER_BOUND),
      })),
      modelStatus: holdout[0] ? 'holdout_evaluated' : 'missing',
      live: live.map((row) => ({
        id: row.ITEM_ID, eventTs: row.EVENT_TS, amount: numberOrNull(row.ORDER_VALUE_SGD),
        leadHrs: numberOrNull(row.REQUESTED_LEAD_HRS), status: row.STATUS, loadedAt: row.LOADED_AT,
      })),
      liveSummary: {
        n: numberOrNull(liveSummary[0]?.N), exceptions: numberOrNull(liveSummary[0]?.EXCEPTIONS),
        lastLoaded: liveSummary[0]?.LAST_LOADED ?? null, medianLagSeconds: numberOrNull(liveSummary[0]?.MEDIAN_LAG_S),
      },
      anomalies: anomalies.map((row) => ({
        id: row.ENTITY_ID, date: row.EVENT_DATE, forecastError: numberOrNull(row.FORECAST_ERROR),
        expected: numberOrNull(row.EXPECTED), upper: numberOrNull(row.UPPER_BOUND),
      })),
      alerts: alerts.map((row) => ({
        id: row.ITEM_ID, eventTs: row.EVENT_TS, amount: numberOrNull(row.ORDER_VALUE_SGD),
        leadHrs: numberOrNull(row.REQUESTED_LEAD_HRS), hint: row.SOP_HINT,
      })),
    }, { headers: { 'Cache-Control': 'no-store' } });
  } catch {
    return NextResponse.json({ error: 'Demand planning data is unavailable. Verify the core deployment and application role.' },
      { status: 503, headers: { 'Cache-Control': 'no-store' } });
  }
}
