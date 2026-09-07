import { querySnowflake } from "@/lib/snowflake"
import { NextRequest } from "next/server"

export const dynamic = "force-dynamic"

const DB = "TSHO_SWT_TOKYO_26"
const SCHEMA = "FRAUD"

export async function GET(request: NextRequest) {
  const txnId = request.nextUrl.searchParams.get("id")
  if (!txnId) {
    return Response.json({ error: "Missing 'id' parameter" }, { status: 400 })
  }

  const sanitized = txnId.replace(/[^a-zA-Z0-9_]/g, "")

  try {
    const rows = await querySnowflake(
      `SELECT * FROM ${DB}.${SCHEMA}.FRAUD_SCORES_ENRICHED
       WHERE TRANSACTION_ID = '${sanitized}'`,
      { callersRights: true }
    )
    return Response.json(rows)
  } catch (e) {
    console.error(new Date().toISOString(), "[transaction-lookup]", e)
    return Response.json(
      { error: e instanceof Error ? e.message : "Failed to fetch transaction" },
      { status: 500 }
    )
  }
}
