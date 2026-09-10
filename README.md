# Snowflake World Tour Tokyo 2026 — CoCo Demo

Disclaimer / 免責事項

[EN] All code and content in this repository is provided for demonstration and educational purposes only. This content is not an official product.

[JA] このリポジトリ内のすべてのコード・コンテンツは、デモおよび学習目的のみ を意図して提供されています。公式プロダクトではありません。



Snowflake World Tour Tokyo 2026 の Breakout セッション用の Snowflake CoCo (Cortex Code) を活用した AI 駆動開発のデモです。

> **すべてのデータは合成データです。実在の個人・企業・取引を含みません。**

| デモ | 時間 | テーマ | ディレクトリ |
|------|------|--------|------------|
| **Demo 1: Impact Radar** | 6分 | SQL カラム削除が下流 AI アセットを壊すかを 検知 | `demo1/` |
| **Demo 2: Fraud Investigation** | 10分 | データ → 特徴量 → XGBoost → バッチ/リアルタイム推論 → モニタリング → Agent → アプリ | `demo2/` |

---

## 前提条件

- Python 3.10 以上
- [uv](https://docs.astral.sh/uv/) (Python パッケージマネージャー)
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) (PAT 接続設定済み)
- CoCo Desktop または CoCo CLI
- Snowflake アカウント (Enterprise Edition 以上、Cortex AI 有効)

### データベース

すべてのオブジェクトは `TSHO_SWT_TOKYO_26` に作成します。他のデータベースは変更しません。

---

## Demo 1: Impact Radar (6分)

SQL のカラム削除が下流の AI アセット (Semantic View、Cortex Agent、外部 BI) を壊すかを `GET_LINEAGE` で検知する CoCo プラグイン。

```
FCT_ORDERS (DISCOUNT_AMT 削除)
  → AGG_SALES_DAILY (Dynamic Table)  — MEDIUM
  → SV_SALES (Semantic View)         — HIGH
  → SALES_AGENT (Cortex Agent)       — HIGH
```

### セットアップ

```bash
snow sql -c <Connection Name> -f demo1/setup/01_staging_tables.sql
snow sql -c <Connection Name> -f demo1/setup/02_marts.sql
snow sql -c <Connection Name> -f demo1/setup/03_semantic_view.sql
snow sql -c <Connection Name> -f demo1/setup/04_agent.sql
snow sql -c <Connection Name> -f demo1/setup/05_verify_lineage.sql
```

### プラグイン (オフラインテスト)

```bash
uv run python demo1/plugins/impact-radar/impact_radar.py \
  --offline demo1/plugins/impact-radar/fixtures/fct_orders_drop_two_cols.json
```

### クリーンアップ

```bash
snow sql -c <Connection Name> -f demo1/setup/99_cleanup.sql
# または: bash demo1/reset_demo1.sh
```

---

## Demo 2: Fraud Investigation (10分)

### アーキテクチャ

| レイヤー | 技術 |
|----------|------|
| Raw データ | テーブル (`TSHO_SWT_TOKYO_26.FRAUD`) |
| 変換 | Dynamic Table `FRAUD_FEATURES` (target lag: 1時間) |
| 訓練データ | `TSHO_SWT_TOKYO_26.FRAUD_ML.TRAINING_DATASET` |
| 学習 | XGBoost (snowflake-ml-python) |
| 推論 | `mv.run()` (Adaptive Warehouse) |
| モデル管理 | Snowflake Model Registry |
| モニタリング | Model Monitor (ドリフト検知) |
| リアルタイム推論 | Inference Service + Gateway (SPCS、任意) |
| Agent | Cortex Agent (Analyst + Search + data_to_chart) |
| アプリケーション | Snowflake App Runtime (Next.js) |
| 開発支援 | Snowflake CoCo (Desktop / CLI) |

Private Preview 依存なし。バッチ推論にコールドスタートなし (`mv.run()` は Compute Pool 不要)。

### セットアップ

```bash
# 1. アカウント初期設定 (ACCOUNTADMIN)
snow sql -c <Connection Name> -f demo2/setup/00_account_prerequisites.sql
snow sql -c <Connection Name> -f demo2/setup/01_create_tables.sql
snow sql -c <Connection Name> -f demo2/setup/02_create_transformation_layer.sql
snow sql -c <Connection Name> -f demo2/setup/03_create_feature_store.sql
snow sql -c <Connection Name> -f demo2/setup/04_create_model_objects.sql

# 2. 合成データ生成・アップロード (ドリフト検知用に60日バックデート)
uv run python demo2/scripts/generate_synthetic_data.py --backdate-days 60
uv run python demo2/scripts/upload_data.py

# 3. モデル学習 + バッチ推論 (ノートブック)
# demo2/notebooks/02_train_fraud_model.ipynb を開いて全セル実行

# 4. Agent オブジェクト (Cortex Search + Semantic View + Agent)
snow sql -c <Connection Name> -f demo2/setup/05_create_agent_objects.sql

# 5. Model Monitor
snow sql -c <Connection Name> -f demo2/setup/06_create_model_monitor.sql

# 6. App Runtime デプロイ
cd demo2/app && snow app deploy --connection <Connection Name>
```

### 主要 URL・確認場所

| リソース | 場所 |
|----------|------|
| App Runtime | `snow app deploy` の出力に表示される URL |
| Model Monitor | Snowsight → AI & ML → Models → `FRAUD_DETECTION_XGBOOST` → バージョン → Monitor タブ |
| Lineage | Snowsight → Data → `FRAUD_SCORES_ENRICHED` → Lineage タブ |
| Agent | Snowsight → AI & ML → Agents → `FRAUD_INVESTIGATOR` |

### クリーンアップ

```bash
snow sql -c <Connection Name> -f demo2/setup/99_cleanup.sql
# または: bash demo2/reset_demo2.sh
```

---

## 設定可能な変数

データベース名・ウェアハウス名は各 SQL ファイル先頭の `SET` 文で変更可能です。

| 変数 | デフォルト値 |
|------|-------------|
| `database_name` | `TSHO_SWT_TOKYO_26` |
| `warehouse_name` | `TSHO_WH_XL` |
| 接続名 | `<Connection Name: ご自身の環境をお使いください>` |

---

## フォールバック対応表

| 問題 | フォールバック |
|------|------------|
| `mv.run()` タイムアウト | `TSHO_WH_XL` にフォールバック |
| ドリフトが表示されない | `PREDICTION_LOG` のデータ期間を確認。バックデートデータを再生成 |
| Agent が応答しない | `FRAUD_SCORES` の SQL 結果を直接表示 |
| App Runtime のデプロイが反映されない | 事前デプロイ済みの SSO URL を開く |

---

## CoCo スラッシュコマンド一覧

| コマンド | 説明 |
|----------|------|
| `/help` | 利用可能なコマンド一覧 |
| `/changelog` | CLI のリリースノート表示 |
| `/connections` | Snowflake 接続の確認・追加・編集・削除 |
| `/model` | 使用するモデルの選択 |
| `/sql-writes on\|off\|status` | SQL 書き込みの制御 |
| `/clear` | 会話をリセット（新規セッション開始） |
| `/cls` | 画面のみクリア（会話は維持） |
| `/resume` | 過去セッションの復元 |
| `/compact` | 表示モードの切り替え |
| `/plugin` | プラグインの一覧・管理 |
| `/agents` | バックグラウンドエージェントの管理 |
| `/monitors` | 長時間実行プロセスの監視 |
| `/mcp` | MCP サーバーの管理・再接続 |
| `/docs` | Snowflake ドキュメントを開く |
| `/index` | リポジトリ全文検索インデックス構築 |
| `/fork` | 会話を分岐 |
| `/rewind` | 会話を巻き戻し（Esc+u で undo） |
| `/import-claude-config` | Claude Code の設定を取り込み |
| `/automations` | 自動化タスクの管理 |

## CoCo 主要更新 (2026年4月〜)

### CoCo CLI

| バージョン | 日付 | 主な更新 |
|-----------|------|---------|
| 1.1.65 | 2026-08-11 | Data exploration subagent、管理者向け managed settings enforcement、MCP サーバーの Snowflake 認証 |
| 1.1.53 | — | `--private` セッション、Claude Code 設定インポート (`/import-claude-config`)、MCP OAuth authorization server override |
| 1.1.52 | — | `cortex agent-studio` コマンド GA、MCP OAuth client secrets、subagent の model inherit |
| 1.1.47 | — | MCP OAuth (リモート/ヘッドレス対応)、FIPS 140 モード、`/monitors` コマンド、`COCO_ADDITIONAL_QUERY_TAGS` |
| 1.1.41 | — | Team mode (マルチエージェント)、`/connections` 管理強化、Plugin discovery 改善 |
| 1.1.27 | — | Named Restricted Session Scope、FIPS 140、Windows 署名 CLI |
| 1.1.8 | — | `cortex exec` (CI/CD 非対話実行)、`cortex workspace`、Restricted Session Scope |
| 1.0.77 | — | `/changelog`、`/sql-writes`、`/mcp` マネージャー刷新、`/index` 全文検索 |
| 1.0.65 | — | Plugin マーケットプレイス、ランタイム Plugin リフレッシュ |
| 1.0.59 | — | Postgres 接続と SQL ワークフロー、ACP エディタ連携 |

### CoCo in Snowsight (2026年4月〜)

| 日付 | 機能 | フェーズ |
|------|------|---------|
| 2026-08-27 | Subagents | GA |
| 2026-08-20 | Restrict this chat (RSS) | Private Preview |
| 2026-08-14 | Automations | Private Preview |
| 2026-08-10 | Per-turn file changes summary | GA |
| 2026-08-04 | Agent-requested plan mode | GA |
| 2026-07-22 | Concurrent chats and fullscreen / Cloud Agents | GA |
| 2026-07-07 | Conversation sharing | GA |
| 2026-06-26 | Automatic context management | GA |


### 参考リンク

- [CoCo CLI Changelog](https://docs.snowflake.com/en/user-guide/cortex-code/changelog)
- [CoCo in Snowsight Changelog](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-snowsight/changelog)
- [CoCo Desktop Release Notes](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-desktop/release-notes)
- [CoCo CLI Reference](https://docs.snowflake.com/en/user-guide/cortex-code/cli-reference)
- [Overview of Snowflake CoCo](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code)


## ライセンス

Apache License 2.0
