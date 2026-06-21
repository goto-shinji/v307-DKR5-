# SMX入庫用ストアド

## 文書区分

| 項目 | 内容 |
|---|---|
| MD分類 | 設定 |
| 対象DB | `tksSmx` |
| 作成日 | 2026-06-21 |

## ファイル

| ファイル | 呼出名 | 処理 |
|---|---|---|
| `SmxNyuItem.sql` | `SmxNyuItem` | 通常QRは`T_data54`、`$Ny`は元連番を照合し、親品目・品名・数量・マスタ洗浄方法を返す |
| `SmxNyuSheet.sql` | `SmxNyuSheet` | 通常QRの入力洗浄方法0、または終了更新後の`$Ny`を`T_シートリーダ`へ追加する |
| `SmxNyuFinish.sql` | `SmxNyuFinish` | `$Ny`の`T_SmxTrc.終了日時`を洗浄方法にかかわらず更新する |

各SQLは`CREATE OR ALTER PROCEDURE`を使用します。SQL Serverへ適用する際は、対象DBとテーブル定義を確認してから実行してください。

## INPUT項目順

Socketサーバーの各INIでは、呼出名を除く受信項目を次の順にINPUTパラメータへ割り当てます。先頭6項目が他の山寺・SMX通信と共通で、以降がSMX戻り品入庫の個別項目です。

| 受信位置 | ストアド引数 | 内容 |
|---:|---|---|
| 2 | `@bhtid` | BHTID |
| 3 | `@bhtdate` | BHT日付 |
| 4 | `@bhttime` | BHT時間 |
| 5 | `@syaincd` | 社員CD |
| 6 | `@nonyudate` | 納入日 |
| 7 | `@qr` | QR全文 |
| 8 | `@destination` | 出庫先 |
| 9 | `@original_seq` | `$Ny`は元の連番、通常QRはQR内の処理日 |
| 10 | `@child_item` | 子品目 |
| 11 | `@quantity` | 数量 |
| 12 | `@cleaning_method` | 洗浄方法 |
| 13 | `@biko` | 親品目（通常QR・`$Ny`ともBHTから送信） |

## OUTPUT項目順

| 呼出名 | OUTPUT |
|---|---|
| `SmxNyuItem` | `@result`、`@msg`、`@parent_item`、`@item_name`、`@original_qty`、`@master_cleaning` |
| `SmxNyuSheet` | `@result`、`@msg` |
| `SmxNyuFinish` | `@result`、`@msg` |

Socketサーバー側では、OUTPUTの後ろにストアドのRETURN値が付加されます。`@result=0`が正常です。

## DB処理

| 処理 | 内容 |
|---|---|
| 商品照会 | 通常QRは`T_data54`、`$Ny`は`T_SmxTrc.連番`で照合する |
| 品名取得 | `T_data54.親図面番号=上位品目`かつ`T_data54.図番=子品目@上位品目`で検索する |
| シートリーダ登録 | 通常QRは入力洗浄方法0のとき、`$Ny`は終了更新後に実行し、`図番累進`と`図番`へ`子品目@親品目`を登録する |
| 終了更新 | `$Ny`は洗浄方法にかかわらず、元レコードの`終了日時`を`GETDATE()`で更新する |
| 同時実行制御 | `$Ny`は元連番、通常QRはQR単位の`sp_getapplock`と`UPDLOCK, HOLDLOCK`で二重登録を防ぐ |

登録可能な出庫先はWeb版の既定値に合わせ、各ストアド内の`@allowed_destination`を`1000020880`としています。環境が異なる場合は適用前に変更してください。

## Socketサーバー側の設定

Socketサーバー用INIは次の場所へ追加済みです。

| 呼出名 | INI |
|---|---|
| `SmxNyuItem` | `ソケットサーバ/ini/SmxNyuItem.ini` |
| `SmxNyuSheet` | `ソケットサーバ/ini/SmxNyuSheet.ini` |
| `SmxNyuFinish` | `ソケットサーバ/ini/SmxNyuFinish.ini` |

既存`SmxNyu.ini`に合わせ、接続先は`Data Source=.;Initial Catalog=tksSmx;Integrated Security=True;`、文字コードはCP932です。配置先環境で接続方式が異なる場合は変更してください。

## 未対応・保留事項

| 区分 | 内容 |
|---|---|
| 未対応 | SQL Serverへのストアド適用 |
| 未対応 | 本番SocketサーバーへのINI配置とサービス再起動 |
| 保留 | 実環境の`T_SmxTrc`、`T_data54`、`T_シートリーダ`の列型・既定値との最終照合 |
