USE [tksSmx];
GO

/*
  $Ny戻り品QRの元レコードへ終了日時を設定する。
  洗浄方法の値にかかわらず先に本ストアドを実行し、正常終了後に
  SmxNyuSheetを実行してT_シートリーダへ実績を作成する。

  入力順はソケットサーバーINIのPARAM1～PARAM12と一致させること。
  戻り値は result、msg、ストアドRETURN値の順で出力される。
*/
CREATE OR ALTER PROCEDURE [dbo].[SmxNyuFinish]
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

    DECLARE @allowed_destination varchar(255) = '1000020880';
    DECLARE @seq_int int = TRY_CONVERT(int, @original_seq);
    DECLARE @source_destination varchar(255);
    DECLARE @source_child varchar(255);
    DECLARE @source_id int;
    DECLARE @finished varchar(30);
    DECLARE @cleaning_int int = TRY_CONVERT(int, @cleaning_method);
    DECLARE @lock_result int;
    DECLARE @lock_resource nvarchar(255) = N'T_SmxTrc_入庫_' + ISNULL(CONVERT(nvarchar(20), @seq_int), N'INVALID');

    -- 例外時を含め、未設定の出力値が返らないよう初期化する。
    SELECT @result = 9, @msg = '終了日時の更新に失敗しました';

    -- 本ストアドは元連番を持つ$Ny QR専用とする。
    IF LEFT(@qr, 3) <> '$Ny' OR @seq_int IS NULL
    BEGIN
        SELECT @result = 1, @msg = '元の連番が正しくありません';
        RETURN 0;
    END;

    -- 洗浄方法0も有効。入力可能な非負整数であることだけを確認する。
    IF @cleaning_int IS NULL OR @cleaning_int < 0
    BEGIN
        SELECT @result = 5, @msg = '洗浄方法を数字で指定してください';
        RETURN 0;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 同じ元連番の二重更新を直列化する。
        EXEC @lock_result = sys.sp_getapplock
            @Resource = @lock_resource,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 10000;

        IF @lock_result < 0
            THROW 50001, '入庫更新ロックを取得できませんでした', 1;

        -- ロック取得後に元レコードを再取得し、登録直前の状態を検証する。
        SELECT TOP (1)
            @source_id = [ID],
            @source_destination = CONVERT(varchar(255), [出庫先CD]),
            @source_child = CONVERT(varchar(255), [出庫品目]),
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

        -- 再送時は正常扱いとし、後続のシートリーダ登録を続行できるようにする。
        IF @finished IS NOT NULL
        BEGIN
            COMMIT TRANSACTION;
            SELECT @result = 0, @msg = '終了日時は更新済みです';
            RETURN 0;
        END;

        UPDATE [dbo].[T_SmxTrc]
        SET [終了日時] = GETDATE()
        WHERE [ID] = @source_id;

        COMMIT TRANSACTION;
        SELECT @result = 0, @msg = '終了日時を更新しました';
        RETURN 0;
    END TRY
    BEGIN CATCH
        -- 途中で失敗した更新は残さない。
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT @result = 9, @msg = '終了日時の更新に失敗しました';
        RETURN 0;
    END CATCH;
END;
GO
