USE [tksSmx];
GO

/*
  SMX入庫実績をT_シートリーダへ作成する。
  通常QRはBHTで入力した洗浄方法が0の場合に実行する。
  $Ny QRはSmxNyuFinishで終了日時を更新した後、洗浄方法にかかわらず実行する。

  入力順はソケットサーバーINIのPARAM1～PARAM12と一致させること。
  戻り値は result、msg、ストアドRETURN値の順で出力される。
*/
CREATE OR ALTER PROCEDURE [dbo].[SmxNyuSheet]
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
    @msg             varchar(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @is_return bit = CASE WHEN LEFT(@qr, 3) = '$Ny' THEN 1 ELSE 0 END;
    DECLARE @allowed_destination varchar(255) = '1000020880';
    DECLARE @seq_int int = TRY_CONVERT(int, @original_seq);
    DECLARE @source_destination varchar(255);
    DECLARE @source_child varchar(255);
    DECLARE @parent_item varchar(255);
    DECLARE @process_date varchar(255);
    DECLARE @finished varchar(30);
    DECLARE @quantity_int int = TRY_CONVERT(int, @quantity);
    DECLARE @cleaning_int int = TRY_CONVERT(int, @cleaning_method);
    DECLARE @lock_result int;
    DECLARE @lock_resource nvarchar(255) = CASE
        WHEN @is_return = 1 THEN N'T_SmxTrc_入庫_' + ISNULL(CONVERT(nvarchar(20), @seq_int), N'INVALID')
        ELSE N'T_SmxTrc_通常入庫_' + CONVERT(nvarchar(20), CHECKSUM(@qr))
    END;

    -- 例外時を含め、未設定の出力値が返らないよう初期化する。
    SELECT @result = 9, @msg = 'T_シートリーダ登録に失敗しました';

    IF @quantity_int IS NULL OR @quantity_int < 1
    BEGIN
        SELECT @result = 4, @msg = '数量は1以上の整数で指定してください';
        RETURN 0;
    END;

    IF @cleaning_int IS NULL OR @cleaning_int < 0
    BEGIN
        SELECT @result = 5, @msg = '洗浄方法を数字で指定してください';
        RETURN 0;
    END;

    -- 通常QRは「QRの値」ではなくBHTで入力した洗浄方法0を登録条件とする。
    IF @is_return = 0 AND @cleaning_int <> 0
    BEGIN
        SELECT @result = 5, @msg = '洗浄方法0のときだけ登録できます';
        RETURN 0;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 同じ元連番または同じ通常QRの同時登録を直列化する。
        EXEC @lock_result = sys.sp_getapplock
            @Resource = @lock_resource,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 10000;

        IF @lock_result < 0
            THROW 50001, '入庫登録ロックを取得できませんでした', 1;

        IF @is_return = 1
        BEGIN
            -- $Nyは終了更新済みの元レコードから親品目と処理日を取得する。
            IF @seq_int IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 1, @msg = '元の連番が正しくありません';
                RETURN 0;
            END;

            SELECT TOP (1)
                @source_destination = CONVERT(varchar(255), [出庫先CD]),
                @source_child = CONVERT(varchar(255), [出庫品目]),
                @parent_item = CONVERT(varchar(255), [上位品目]),
                @process_date = CONVERT(varchar(255), [処理日]),
                @finished = NULLIF(LTRIM(RTRIM(CONVERT(varchar(30), [終了日時], 121))), '')
            FROM [dbo].[T_SmxTrc] WITH (UPDLOCK, HOLDLOCK)
            WHERE [連番] = @seq_int
            ORDER BY [ID] DESC;

            IF @source_destination IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 1, @msg = '元の連番が見つかりません';
                RETURN 0;
            END;

            IF @destination <> @allowed_destination
               OR @destination <> @source_destination
               OR @child_item <> @source_child
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 2, @msg = '商品が違います';
                RETURN 0;
            END;

            -- $Nyは必ずSmxNyuFinish成功後に登録する。
            IF @finished IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 5, @msg = '終了日時が更新されていません';
                RETURN 0;
            END;
        END
        ELSE
        BEGIN
            -- 通常QRはQRから取得した親品目・処理日を使用する。
            SET @parent_item = @biko;
            SET @process_date = @original_seq;

            IF @destination <> @allowed_destination
               OR NULLIF(LTRIM(RTRIM(@parent_item)), '') IS NULL
               OR NULLIF(LTRIM(RTRIM(@child_item)), '') IS NULL
               OR NOT EXISTS
                  (
                      SELECT 1
                      FROM [dbo].[T_data54]
                      WHERE [親図面番号] = @parent_item
                        AND [図番] = @child_item + '@' + @parent_item
                  )
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 2, @msg = '商品が違います';
                RETURN 0;
            END;
        END;

        -- 同じQRの再送は二重追加せず正常終了とする。
        IF EXISTS
        (
            SELECT 1
            FROM [dbo].[T_シートリーダ] WITH (UPDLOCK, HOLDLOCK)
            WHERE [bcd] = @qr
              AND [記号] = 'SMX入庫'
        )
        BEGIN
            COMMIT TRANSACTION;
            SELECT @result = 0, @msg = 'T_シートリーダ登録済みです';
            RETURN 0;
        END;

        -- Web版と同じ列対応でSMX入庫実績を追加する。
        INSERT INTO [dbo].[T_シートリーダ]
        (
            [bcd], [dt], [kbn], [biko], [図番累進], [記号],
            [NO], [数], [メモ], [図番], [場所]
        )
        VALUES
        (
            @qr, @process_date, 2, '', @child_item + '@' + @parent_item, 'SMX入庫',
            0, @quantity_int, 'SMX', @child_item + '@' + @parent_item, ''
        );

        COMMIT TRANSACTION;
        SELECT @result = 0, @msg = 'T_シートリーダに登録しました';
        RETURN 0;
    END TRY
    BEGIN CATCH
        -- 途中で失敗した登録は残さない。
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT @result = 9, @msg = 'T_シートリーダ登録に失敗しました';
        RETURN 0;
    END CATCH;
END;
GO
