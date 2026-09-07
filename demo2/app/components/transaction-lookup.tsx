"use client"

import { useState } from "react"

const DB = "TSHO_SWT_TOKYO_26"
const SCHEMA = "FRAUD"

export function TransactionLookup() {
  const [txnId, setTxnId] = useState("")
  const [result, setResult] = useState<Record<string, unknown> | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")

  async function handleSearch() {
    if (!txnId.trim()) return
    setLoading(true)
    setError("")
    setResult(null)
    try {
      const res = await fetch(`/api/transaction?id=${encodeURIComponent(txnId.trim())}`)
      const data = await res.json()
      if (data.error) {
        setError(data.error)
      } else if (data.length === 0) {
        setError(`Transaction ${txnId} not found.`)
      } else {
        setResult(data[0])
      }
    } catch (e) {
      setError("Failed to fetch transaction data.")
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="space-y-4">
      <h2 className="text-lg font-semibold">Transaction Lookup</h2>
      <div className="flex gap-2">
        <input
          type="text"
          value={txnId}
          onChange={(e) => setTxnId(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleSearch()}
          placeholder="TXN00000001"
          className="flex-1 border rounded-lg px-3 py-2 text-sm bg-background"
        />
        <button
          onClick={handleSearch}
          disabled={loading}
          className="px-4 py-2 rounded-lg bg-primary text-primary-foreground text-sm font-medium hover:opacity-90 disabled:opacity-50"
        >
          {loading ? "..." : "Search"}
        </button>
      </div>
      {error && <p className="text-sm text-red-500">{error}</p>}
      {result && (
        <div className="border rounded-lg p-4 space-y-2">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <Metric label="Fraud Score" value={Number(result.FRAUD_SCORE ?? 0).toFixed(4)} />
            <Metric
              label="Prediction"
              value={Number(result.PREDICTION ?? 0) === 1 ? "FRAUD" : "Legitimate"}
            />
            <Metric label="Amount" value={Number(result.AMOUNT ?? 0).toLocaleString()} />
            <Metric label="Channel" value={String(result.CHANNEL ?? "—")} />
          </div>
          <details className="mt-3">
            <summary className="text-sm cursor-pointer text-muted-foreground">
              Feature Details
            </summary>
            <pre className="mt-2 text-xs bg-muted/50 p-3 rounded overflow-auto max-h-64">
              {JSON.stringify(result, null, 2)}
            </pre>
          </details>
        </div>
      )}
    </div>
  )
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="text-lg font-semibold">{value}</p>
    </div>
  )
}
