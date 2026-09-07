# Expected Outputs

デモの各ステップで期待される出力の例。
Agent が応答しない場合やネットワーク問題時のバックアップとして使用。

---

## 1. データ理解 (Iceberg プロファイリング)

```
RAW_TRANSACTIONS:      50,000 rows
RAW_CUSTOMER_PROFILES:  1,000 rows
RAW_MERCHANT_PROFILES:    500 rows

RAW_TRANSACTIONS:
  NULL率: 全列 0%
  重複 transaction_id: 0 件
  最新 transaction_ts: 2025-06-29 (approx)
  fraud rate: 3.0%
```

## 2. パイプライン (FRAUD_FEATURES)

```
FRAUD_FEATURES Dynamic Table:
  50,000 rows
  主要特徴量: txn_count_1h, amount_sum_24h, country_changed_flag, ...
  Target lag: 60 minutes
```

## 3. ML (XGBoost)

```
Model: FRAUD_DETECTION_XGBOOST
  Accuracy:  ~0.97
  Precision: ~0.85
  Recall:    ~0.75
  F1:        ~0.80
  ROC-AUC:   ~0.95

FRAUD_SCORES: 50,000 rows
  Predicted fraud: ~1,800 (~3.6%)
```

## 4. Agent Q&A の例

**質問**: 取引ID TXN00000001 の不正スコアを教えてください

**期待される回答** (概要):
```
TXN00000001:
  - Fraud Score: 0.1234
  - Prediction: Legitimate (score < 0.5)
  - Amount: ¥XX,XXX
  - Channel: web
  - Risk Level: Low (score < 0.3)
  - 推奨: 定期レビュー対象。即時対応不要。
  - 根拠: FRAUD_SCORES_ENRICHED テーブル、fraud_policy.md Section 1
```
