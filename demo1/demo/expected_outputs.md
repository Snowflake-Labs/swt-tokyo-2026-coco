# Impact Radar 期待出力

## /impact-check 実行結果

```
============================================================
IMPACT RADAR — Column Removal Analysis
============================================================

[!!] DISCOUNT_AMT (TSHO_SWT_TOKYO_26.MARTS.FCT_ORDERS)
    Risk: HIGH
    Reason: Reaches SEMANTIC VIEW: SV_SALES
    Downstream (4):
      - AGG_SALES_DAILY (DYNAMIC TABLE) @ distance 1
        column: TOTAL_DISCOUNT
      - AGG_SALES_DAILY (DYNAMIC TABLE) @ distance 1
        column: TOTAL_NET
      - SV_SALES (SEMANTIC VIEW) @ distance 2
        column: Discount Amount
      - SALES_AGENT (CORTEX AGENT) @ distance 3
      - Q3 Exec Dashboard (EXTERNAL) @ distance 2
        column: DISCOUNT_AMT

[ok] LEGACY_STATUS_CD (TSHO_SWT_TOKYO_26.MARTS.FCT_ORDERS)
    Risk: LOW
    Downstream: none

============================================================
Overall: HIGH
COMMIT BLOCKED: AI assets or external BI would break silently.
Fix the downstream references or update the metric definitions.
============================================================
```

## メイン: SV_SALES の metric 式で DISCOUNT_AMT 参照を特定

CoCo に「Agent は本当に壊れる? 根拠を出して」と聞くと:

```
SV_SALES の metric "Total Net Revenue" は以下の式で定義されています:

  SUM(orders."Net Revenue")

"Net Revenue" は FCT_ORDERS で次のように計算されています:

  quantity * unit_price - discount_amt AS net_revenue

DISCOUNT_AMT を削除すると、net_revenue の計算が失敗し、
SV_SALES の "Total Net Revenue" metric が壊れます。
SALES_AGENT はこの metric を使って回答するため、
Agent は黙って間違った答えを返す可能性があります。
```

## commit 拒否 → 修正 → 通過

```
$ git commit -m "remove unused columns"
Impact Radar: HIGH RISK — commit blocked

$ # LEGACY_STATUS_CD だけ削除する修正を適用
$ git add demo1/demo/sql/fct_orders.sql
$ /impact-check

[ok] LEGACY_STATUS_CD (TSHO_SWT_TOKYO_26.MARTS.FCT_ORDERS)
    Risk: LOW
    Downstream: none

Overall: LOW
```
