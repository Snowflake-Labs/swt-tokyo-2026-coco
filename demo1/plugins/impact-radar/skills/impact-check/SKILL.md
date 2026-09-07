# impact-check

user-invocable: true

git add 済み SQL の列削除を検出し、GET_LINEAGE で下流影響を分析する。

## When to Use

- SQL ファイルを編集して git add した後、commit する前
- データエンジニアがテーブルやビューのカラムを削除・リネームしようとしているとき
- 「この変更で何が壊れるか」を事前に知りたいとき

## Inputs

- `git diff --staged -- *.sql`: git add 済み SQL ファイルの差分
- GET_LINEAGE (SNOWFLAKE.CORE): 列単位の下流依存
- impact-radar.yml (任意): データベース名、スキーママッピング

## Steps

1. `git diff --staged` から `*.sql` ファイルの変更を抽出する
2. ファイルパスまたは CREATE 文から変更対象の FQN を特定する
3. diff の `-` 行にあるが `+` 行にない識別子を「削除列」とする
4. 全削除列の GET_LINEAGE を UNION ALL で 1往復実行する
5. 下流を分類する:
   - native (table, view, dynamic table) → MEDIUM
   - Semantic View / Cortex Agent → HIGH
   - EXTERNAL (BI ツール等) → HIGH
   - なし → LOW
6. 人間向けレポートと JSON を出力する
7. HIGH の場合は exit code 1 で commit を拒否する

## Safety Constraints

- 読み取り専用。DDL/DML を一切実行しない
- GET_LINEAGE のみ使用 (VIEW LINEAGE 権限で十分)
- 外部ネットワーク通信を行わない
- 秘密情報を読み取らない

## Expected Output

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
============================================================
```
