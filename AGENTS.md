# AGENTS.md

このリポジトリは、Snowflake CoCo、Apache Iceberg、Snowflake ML、Cortex Agents、
Streamlit in Snowflake を使った公開デモです。

## 最優先事項

1. GitHub に公開しても安全なコードだけを生成すること。
2. 実データ、個人情報、認証情報、PAT、パスワード、アカウント識別子を絶対にコミットしないこと。
3. Snowflake オブジェクト名は環境変数または設定ファイルから取得し、SQL へ直接ハードコードしないこと。
4. セットアップ処理は何度実行しても壊れないように冪等にすること。
5. 破壊的な DROP/OR REPLACE は、明示的な `--reset` フラグがある場合だけ実行すること。
6. ACCOUNTADMIN を常用しないこと。初回のアカウント設定とデモオブジェクト作成を分離すること。
7. SQL、Python、アプリコードを生成したら、実行前に変更内容・必要権限・作成されるオブジェクトを説明すること。
8. すべてのデータ処理は Snowflake の RBAC 境界内で行うこと。
9. Preview または Private Preview の機能は本線にせず、利用できない場合のフォールバックを必ず実装すること。
10. README には、前提条件、権限、コスト、リージョン、既知の制約、削除方法を明記すること。
