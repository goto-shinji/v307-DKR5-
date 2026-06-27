USE [tksSmx];
GO

/*
  SMX入庫の品名・登録元情報を照会する。
  通常QRはQR内の親品目・子品目をT_data54で照合する。
  $Ny QRは元連番のT_SmxTrcを照合し、登録に必要な元情報を返す。

  入力順はソケットサーバーINIのPARAM1～PARAM12と一致させること。
  戻り値は result、msg、parent_item、item_name、original_qty、
  master_cleaning、ストアドRETURN値の順でソケット応答へ出力される。
*/
CREATE OR ALTER PROCEDURE [dbo].[SmxNyuItem]
    @bhtid           varchar(20),
    @bhtdate         varchar(10),
    @bhttime         varchar(8),
    @syaincd         varchar(3),
    @nonyudate       varchar(10),
    @qr              varchar(8000),
    @destination     varchar(255),
    @original_seq    varchar(255),
    @child_item      varchar(255),
    @quantity        varchar(50),
    @cleaning_method varchar(50),
    @biko            varchar(255),
    @result          int OUTPUT,
    @msg             varchar(255) OUTPUT,
    @parent_item     varchar(255) OUTPUT,
    @item_name       varchar(255) OUTPUT,
    @original_qty    varchar(50) OUTPUT,
    @master_cleaning varchar(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- $Nyは戻り品QR、その他は通常QRとして扱う。
    DECLARE @is_return bit = CASE WHEN LEFT(@qr, 3) = '$Ny' THEN 1 ELSE 0 END;
    DECLARE @allowed_destination varchar(255) = '1000020880';
    DECLARE @seq_int int = TRY_CONVERT(int, @original_seq);
    DECLARE @source_destination varchar(255);
    DECLARE @source_child varchar(255);
    DECLARE @finished varchar(30);
    DECLARE @item_found bit = 0;

    -- 途中で終了した場合にも、必ず判定可能な初期値を返す。
    SELECT
        @result = 9,
        @msg = '品名照会失敗',
        @parent_item = '',
        @item_name = '',
        @original_qty = '',
        @master_cleaning = '';

    -- 出庫先はWeb版SMX入庫と同じ許可値に限定する。
    IF @destination <> @allowed_destination
    BEGIN
        SELECT @result = 6, @msg = '出庫先が違います';
        RETURN @result;
    END;

    IF @is_return = 1
    BEGIN
        -- $Nyは連番をキーに元の出庫実績を取得する。
        IF @seq_int IS NULL
        BEGIN
            SELECT @result = 1, @msg = '元連番不正';
            RETURN @result;
        END;

        SELECT TOP (1)
            @source_destination = CONVERT(varchar(255), [出庫先CD]),
            @source_child = CONVERT(varchar(255), [出庫品目]),
            @parent_item = CONVERT(varchar(255), [上位品目]),
            @original_qty = CONVERT(varchar(50), [数量]),
            @finished = NULLIF(LTRIM(RTRIM(CONVERT(varchar(30), [終了日時], 121))), '')
        FROM [dbo].[T_SmxTrc]
        WHERE [連番] = @seq_int
        ORDER BY [ID] DESC;

        IF @source_destination IS NULL
        BEGIN
            SELECT @result = 1, @msg = '元連番なし';
            RETURN @result;
        END;

        -- QRの出庫先・子品目が元レコードと一致することを確認する。
        IF @destination <> @source_destination
        BEGIN
            SELECT @result = 6, @msg = '出庫先が違います';
            RETURN @result;
        END;

        IF @child_item <> @source_child
        BEGIN
            SELECT @result = 2, @msg = '商品が違います';
            RETURN @result;
        END;

        IF @finished IS NOT NULL
        BEGIN
            SELECT @result = 3, @msg = '登録済';
            RETURN @result;
        END;
    END
    ELSE
    BEGIN
        -- 通常QRはBHTが送った親品目・数量を照会結果へ引き継ぐ。
        SET @parent_item = @biko;
        SET @original_qty = @quantity;

        IF NULLIF(LTRIM(RTRIM(@parent_item)), '') IS NULL
           OR NULLIF(LTRIM(RTRIM(@child_item)), '') IS NULL
        BEGIN
            SELECT @result = 2, @msg = '商品が違います';
            RETURN @result;
        END;
    END;

    -- 品名と洗浄方法の初期値は品目マスタから取得する。
    SELECT TOP (1)
        @item_found = 1,
        @item_name = ISNULL(CONVERT(varchar(255), [品名]), ''),
        @master_cleaning = ISNULL(CONVERT(varchar(50), [洗浄方法]), '')
    FROM [dbo].[T_data54]
    WHERE [親図面番号] = @parent_item
      AND [図番] = @child_item + '@' + @parent_item
    ORDER BY [ID];

    -- 通常QRは品目マスタに存在する商品だけを入庫対象とする。
    IF @is_return = 0 AND @item_found = 0
    BEGIN
        SELECT @result = 1, @msg = '品名なし';
        RETURN @result;
    END;

    SELECT @result = 0, @msg = 'OK';
    RETURN 0;
END;
GO
