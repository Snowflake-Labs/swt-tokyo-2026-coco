import { Suspense } from "react"
import { querySnowflake } from "@/lib/snowflake"
import { TransactionLookup } from "@/components/transaction-lookup"
import { DriftBadge } from "@/components/drift-badge"

export const dynamic = "force-dynamic"

const DB = "TSHO_SWT_TOKYO_26"
const SCHEMA = "FRAUD"

async function getRecentScores() {
  try {
    const rows = await querySnowflake(
      `SELECT transaction_id, fraud_score, prediction
       FROM ${DB}.${SCHEMA}.FRAUD_SCORES
       QUALIFY ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY fraud_score DESC) = 1
       ORDER BY fraud_score DESC LIMIT 10`
    )
    return rows
  } catch (e) {
    console.error("[getRecentScores]", e)
    return []
  }
}

async function getStats() {
  try {
    const rows = await querySnowflake(
      `WITH deduped AS (
         SELECT * FROM ${DB}.${SCHEMA}.FRAUD_SCORES
         QUALIFY ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY fraud_score DESC) = 1
       )
       SELECT
         COUNT(*) AS total,
         SUM(prediction) AS flagged,
         AVG(fraud_score) AS avg_score
       FROM deduped`
    )
    const r = rows[0] || {}
    return {
      total: r.TOTAL ?? r.total ?? 0,
      flagged: r.FLAGGED ?? r.flagged ?? 0,
      avg_score: r.AVG_SCORE ?? r.avg_score ?? 0,
    }
  } catch (e) {
    console.error("[getStats]", e)
    return { total: 0, flagged: 0, avg_score: 0 }
  }
}

export default async function Home() {
  const [topScores, stats] = await Promise.all([
    getRecentScores(),
    getStats(),
  ])

  return (
    <main className="w-full py-8 px-4 max-w-6xl mx-auto space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Fraud Investigation Console</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Synthetic Data — Demo Only
          </p>
        </div>
        <Suspense fallback={<span className="text-sm">Loading drift...</span>}>
          <DriftBadge />
        </Suspense>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <StatCard label="Total Transactions" value={stats.total?.toLocaleString() ?? "0"} />
        <StatCard label="Flagged" value={stats.flagged?.toLocaleString() ?? "0"} />
        <StatCard
          label="Avg Score"
          value={typeof stats.avg_score === "number" ? stats.avg_score.toFixed(4) : "—"}
        />
      </div>

      <TransactionLookup />

      <div>
        <h2 className="text-lg font-semibold mb-3">Top 10 Highest Fraud Scores</h2>
        <div className="border rounded-lg overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-muted/50">
              <tr>
                <th className="text-left p-3">Transaction ID</th>
                <th className="text-right p-3">Fraud Score</th>
                <th className="text-right p-3">Prediction</th>
              </tr>
            </thead>
            <tbody>
              {topScores.length === 0 ? (
                <tr>
                  <td colSpan={3} className="p-3 text-center text-muted-foreground">
                    No data available
                  </td>
                </tr>
              ) : (
                topScores.map((row: Record<string, unknown>, i: number) => (
                  <tr key={i} className="border-t">
                    <td className="p-3 font-mono text-xs">
                      {String(row.TRANSACTION_ID ?? row.transaction_id ?? "")}
                    </td>
                    <td className="p-3 text-right">
                      {Number(row.FRAUD_SCORE ?? row.fraud_score ?? 0).toFixed(4)}
                    </td>
                    <td className="p-3 text-right">
                      {Number(row.PREDICTION ?? row.prediction ?? 0) === 1 ? "FRAUD" : "OK"}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </main>
  )
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="border rounded-lg p-4">
      <p className="text-sm text-muted-foreground">{label}</p>
      <p className="text-2xl font-bold mt-1">{value}</p>
    </div>
  )
}
