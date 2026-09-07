# data/

## 合成データ仕様

`scripts/generate_synthetic_data.py` で生成される合成データです。
実在の個人・企業・取引を含みません。

### customer_profiles.parquet

| 列名 | 型 | 説明 |
|------|------|------|
| customer_id | string (UUID) | 顧客ID |
| country | string | 居住国 (JP, US, GB, SG, DE) |
| account_age_days | int | アカウント開設からの日数 |
| customer_segment | string | 顧客区分 (individual, premium, business, student) |

### merchant_profiles.parquet

| 列名 | 型 | 説明 |
|------|------|------|
| merchant_id | string | 加盟店ID (M00000形式) |
| merchant_country | string | 加盟店所在国 |
| merchant_category | string | 業種 (electronics, grocery, travel, ...) |
| risk_level | string | リスク水準 (low: 60%, medium: 30%, high: 10%) |

### transactions.parquet

| 列名 | 型 | 説明 |
|------|------|------|
| transaction_id | string | 取引ID (TXN00000000形式) |
| customer_id | string | 顧客ID (customer_profilesへの外部キー) |
| merchant_id | string | 加盟店ID (merchant_profilesへの外部キー) |
| transaction_ts | timestamp | 取引日時 (2025-01-01 〜 2025-06-30) |
| amount | float | 取引金額 |
| currency | string | 通貨 (JPY, USD, GBP, SGD, EUR) |
| country | string | 取引実行国 |
| channel | string | チャネル (web, mobile, pos, atm) |
| device_id | string | デバイスID |
| is_fraud | int | 不正フラグ (0=正常, 1=不正, デフォルト3%) |

### 生成方法

```bash
python scripts/generate_synthetic_data.py
```

オプション:
- `--fraud-ratio 0.05` — 不正比率を変更
- `--num-transactions 100000` — 取引件数を変更
