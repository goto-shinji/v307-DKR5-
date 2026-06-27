# SMX入庫 SocketサーバーINI設定

## 文書区分

| 項目 | 内容 |
|---|---|
| MD分類 | 設定 |
| 設定日 | 2026-06-21 |
| 対象 | `ソケットサーバ/ini` |
| 文字コード | CP932（Shift-JIS） |

## 設定変更

| INI | `SQLSTR` | OUTPUT数 | 用途 |
|---|---|---:|---|
| `SmxNyu.ini` | `SmxNyu` | 2 | 登録本処理。通常QRは洗浄方法000でシート登録、000以外で`T_SmxTrc`追加。`$Ny`は消込＋シート登録 |
| `SmxNyuItem.ini` | `SmxNyuItem` | 6 | 品名・元レコード照会 |

`SmxNyu.ini`のINPUTは既存の`Soc.YmdSend`形式で、`bhtid`、`bhtdate`、`bhttime`、`syaincd`、`dt`、`scandata`、`zno`、`rno`、`nyusuu`、`syusuu`、`zaisuu`、`biko`の順です。`biko`を洗浄方法（`000`形式）として扱います。

`SmxNyuItem.ini`のINPUTは、`bhtid`、`bhtdate`、`bhttime`、`syaincd`、`nonyudate`、`qr`、`destination`、`original_seq`、`child_item`、`quantity`、`cleaning_method`、`biko`の順です。

`original_seq`は`varchar`です。`$Ny`では元連番、通常QRではQR内の処理日を渡します。`biko`には登録時の親品目を渡します。

接続文字列は既存`SmxNyu.ini`に合わせ、次の値を設定しています。

```ini
CONNECTSTR=Data Source=.;Initial Catalog=tksSmx;Integrated Security=True;
```

## 判断理由

| 判断 | 理由 |
|---|---|
| 既存SMX接続文字列を使用 | 同じDB・同じSocketサーバー経路で動作させるため |
| `SmxNyu`は既存INPUT順を維持 | 提示電文および既存`Soc.YmdSend`送信形に合わせるため |
| 品名照会と登録を分離 | `SmxNyuItem`で確認し、登録本処理は`SmxNyu`へ集約するため |
| INIをCP932で保存 | Socketサーバーの既存INIおよび日本語値と文字コードを合わせるため |

## 削除済みINI

| 日時 | INI | 理由 |
|---|---|---|
| 2026-06-27 | `SmxNyuSheet.ini` | 登録本処理を`SmxNyu`へ集約したため |
| 2026-06-27 | `SmxNyuFinish.ini` | 登録本処理を`SmxNyu`へ集約したため |

## 未対応・保留事項

| 区分 | 内容 |
|---|---|
| 未対応 | 本番Socketサーバーへの配置、接続確認、サービス再起動 |
| 保留 | 本番環境がSQL認証の場合の接続文字列差替え |
