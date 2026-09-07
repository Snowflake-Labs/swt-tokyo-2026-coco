# Investigation Playbook

> **注意**: この文書は合成データのデモ用です。

## Step 1: 初期トリアージ

1. `fraud_scores` テーブルから対象取引の `fraud_score` と `prediction` を取得する
2. スコアに基づくリスクレベルを `fraud_policy.md` の閾値テーブルで確認する
3. `FRAUD_SCORES_ENRICHED` ビューで取引の詳細と特徴量を確認する

## Step 2: 特徴量分析

以下の特徴量を確認し、不正の兆候を評価する:

### 取引特性
- `amount`: 通常の取引金額と比較して異常か
- `channel`: 顧客の通常チャネルと一致するか
- `txn_country` vs `customer_country`: クロスボーダー取引か

### 行動パターン
- `txn_count_1h`, `txn_count_24h`, `txn_count_7d`: 取引頻度の急増はあるか
- `amount_sum_24h`: 24時間の累積金額は通常範囲内か

### リスク要因
- `merchant_risk_level`: 高リスク加盟店か
- `account_age_days`: 新規アカウントからの高額取引か
- `country_changed_flag`: 顧客の居住国以外からの取引か

## Step 3: ポリシー照合

`fraud_policy.md` から該当するルールを検索し、以下を特定する:
- 適用される閾値とリスクレベル
- 必要なエスカレーションレベル
- 推奨される対応アクション

## Step 4: レポート作成

以下の情報を含む調査レポートを作成する:

```
取引ID:        [transaction_id]
スコア:        [fraud_score] (閾値: [threshold])
判定:          [prediction]
リスクレベル:  [Low/Medium/High/Critical]

主要な不正指標:
- [指標1]: [値] - [判定]
- [指標2]: [値] - [判定]

該当ポリシー:
- [ポリシー名/セクション]

推奨アクション:
1. [アクション1]
2. [アクション2]

根拠:
- データソース: [テーブル/ビュー名]
- ポリシー参照: [セクション]
```

## Step 5: フォローアップ

- 同一顧客の他の取引を確認
- 同一加盟店の他のフラグ付き取引を確認
- 必要に応じてエスカレーション
