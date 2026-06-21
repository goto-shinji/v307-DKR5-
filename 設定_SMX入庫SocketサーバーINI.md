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
| `SmxNyuItem.ini` | `SmxNyuItem` | 6 | 品名・元レコード照会 |
| `SmxNyuSheet.ini` | `SmxNyuSheet` | 2 | `T_シートリーダ`登録 |
| `SmxNyuFinish.ini` | `SmxNyuFinish` | 2 | `T_SmxTrc.終了日時`更新 |

全INIのINPUTは、`bhtid`、`bhtdate`、`bhttime`、`syaincd`、`nonyudate`、`qr`、`destination`、`original_seq`、`child_item`、`quantity`、`cleaning_method`、`biko`の順です。

`original_seq`は`varchar`です。`$Ny`では元連番、通常QRではQR内の処理日を渡します。`biko`には登録時の親品目を渡します。

接続文字列は既存`SmxNyu.ini`に合わせ、次の値を設定しています。

```ini
CONNECTSTR=Data Source=.;Initial Catalog=tksSmx;Integrated Security=True;
```

## 判断理由

| 判断 | 理由 |
|---|---|
| 既存SMX接続文字列を使用 | 同じDB・同じSocketサーバー経路で動作させるため |
| 3コマンドでINPUT順を統一 | BHT側の共通送信関数を利用し、項目ずれを防ぐため |
| INIをCP932で保存 | Socketサーバーの既存INIおよび日本語値と文字コードを合わせるため |

## 未対応・保留事項

| 区分 | 内容 |
|---|---|
| 未対応 | 本番Socketサーバーへの配置、接続確認、サービス再起動 |
| 保留 | 本番環境がSQL認証の場合の接続文字列差替え |
