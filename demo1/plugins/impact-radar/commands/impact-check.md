# /impact-check

SQL の列削除が下流の AI Agents や BI を壊すのかを調べます。

---

git stage (`git add` 済み) の SQL ファイルから削除される列を検出し、
GET_LINEAGE で下流の Dynamic Table、Semantic View、Cortex Agent、外部 BI への影響を分析してください。
HIGH リスクの場合は commit をブロックしてください。
