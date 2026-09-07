import { querySnowflake } from "@/lib/snowflake"

const DB = "TSHO_SWT_TOKYO_26"
const SCHEMA = "FRAUD"

export async function DriftBadge() {
  try {
    const rows = await querySnowflake(
      `SELECT
         AVG(CASE WHEN scored_at >= DATEADD(DAY, -30, CURRENT_TIMESTAMP()) THEN fraud_score END) AS recent_avg,
         AVG(CASE WHEN scored_at < DATEADD(DAY, -30, CURRENT_TIMESTAMP()) THEN fraud_score END) AS baseline_avg
       FROM ${DB}.${SCHEMA}.PREDICTION_LOG`
    )
    const row = rows[0] || {}
    const recent = Number(row.RECENT_AVG ?? row.recent_avg ?? 0)
    const baseline = Number(row.BASELINE_AVG ?? row.baseline_avg ?? 0)
    const driftDetected = baseline > 0 && (recent - baseline) / baseline > 0.2

    return (
      <span
        className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-medium ${
          driftDetected
            ? "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
            : "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
        }`}
      >
        {driftDetected ? "Drift Detected" : "Model Stable"}
      </span>
    )
  } catch {
    return (
      <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
        Drift: N/A
      </span>
    )
  }
}
