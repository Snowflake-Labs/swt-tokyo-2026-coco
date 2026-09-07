# Impact Radar Plugin

SQL の変更が下流の何を壊すかを GET_LINEAGE で調べ、危険なら commit をブロックする。

## 有効化条件

- CoCo Desktop または CLI が Snowflake に接続済みであること
- VIEW LINEAGE 権限があること (PUBLIC に既定で付与)

## 提供機能

| 種類 | 名前 | 説明 |
|------|------|------|
| Skill | impact-check | git add 済み SQL から削除列を検出し、下流影響を分析 |
| Command | /impact-check | 上記 skill の入口 |

## 安全性

- 読み取り専用 (GET_LINEAGE + git diff のみ)
- DDL/DML を実行しない
- 外部ネットワーク通信を行わない
