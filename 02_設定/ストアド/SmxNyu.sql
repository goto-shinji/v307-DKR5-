USE [tksSmx];
GO

/*
  SMX入庫を1つの呼出名で処理する。

  電文例:
  SmxNyu^BHTID^BHT日付^BHT時刻^社員CD^納入日^QR全文^子@親^^数量^0^0^洗浄方法

  通常QR:
    洗浄方法000以外はT_SmxTrcへ追加し、T_シートリーダへは追加しない。
    洗浄方法000はT_シートリーダへ追加し、T_SmxTrcへは追加しない。

  $Ny QR:
    元T_SmxTrcの終了日時を更新し、T_シートリーダへ追加する。

  戻り値は result、msg、ストアドRETURN値の順で出力される。
*/
CREATE OR ALTER PROCEDURE [dbo].[SmxNyu]
    @bhtid    varchar(255),
    @bhtdate  varchar(255),
    @bhttime  varchar(255),
    @syaincd  varchar(255),
    @dt       varchar(50),
    @scandata varchar(8000),
    @zno      varchar(255),
    @rno      varchar(255),
    @nyusuu   int,
    @syusuu   int,
    @zaisuu   int,
    @biko     varchar(255),
    @result   int OUTPUT,
    @msg      varchar(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @allowed_destination varchar(255) = '1000020880';
    DECLARE @qr varchar(8000) = ISNULL(@scandata, '');
    DECLARE @is_return bit = CASE WHEN LEFT(ISNULL(@scandata, ''), 3) = '$Ny' THEN 1 ELSE 0 END;
    DECLARE @cleaning_int int = TRY_CONVERT(int, @biko);
    DECLARE @quantity_int int = TRY_CONVERT(int, @nyusuu);
    DECLARE @destination varchar(255) = '';
    DECLARE @seq_int int;
    DECLARE @child_item varchar(255) = '';
    DECLARE @parent_item varchar(255) = '';
    DECLARE @process_date varchar(255) = NULLIF(LTRIM(RTRIM(@dt)), '');
    DECLARE @store varchar(255) = '';
    DECLARE @required_date varchar(255) = '';
    DECLARE @plant varchar(255) = '';
    DECLARE @voucher_no varchar(255) = '';
    DECLARE @lot varchar(255) = '';
    DECLARE @storage_location varchar(255) = '';
    DECLARE @source_destination varchar(255);
    DECLARE @source_child varchar(255);
    DECLARE @source_id int;
    DECLARE @finished varchar(30);
    DECLARE @next_seq int;
    DECLARE @lock_result int;
    DECLARE @lock_resource nvarchar(255);
    DECLARE @qr_xml xml;
    DECLARE @at_pos int;

    SELECT @result = 9, @msg = '入庫登録失敗';

    BEGIN TRY
        INSERT INTO dbo.t_log(memo)
        SELECT CONCAT(
            '[SmxNyu]',
            ' bhtid=', @bhtid,
            ' bhtdate=', @bhtdate,
            ' bhttime=', @bhttime,
            ' syaincd=', @syaincd,
            ' dt=', @dt,
            ' qr=', @scandata,
            ' zno=', @zno,
            ' rno=', @rno,
            ' nyusuu=', CONVERT(varchar(20), @nyusuu),
            ' syusuu=', CONVERT(varchar(20), @syusuu),
            ' zaisuu=', CONVERT(varchar(20), @zaisuu),
            ' biko=', @biko
        );
    END TRY
    BEGIN CATCH
        -- ログ出力失敗で入庫本処理を止めない。
    END CATCH;

    SET @qr_xml = TRY_CONVERT(xml,
        '<x><i>' +
        REPLACE(
            REPLACE(
                REPLACE(
                    REPLACE(ISNULL(@qr, ''), '&', '&amp;'),
                    '<', '&lt;'),
                '>', '&gt;'),
            ',', '</i><i>') +
        '</i></x>');

    IF @qr_xml IS NULL
    BEGIN
        SELECT @result = 1, @msg = 'QR不正';
        RETURN @result;
    END;

    IF @quantity_int IS NULL OR @quantity_int < 1
    BEGIN
        SELECT @result = 4, @msg = '数量不正';
        RETURN @result;
    END;

    IF @cleaning_int IS NULL OR @cleaning_int < 0
    BEGIN
        SELECT @result = 5, @msg = '洗浄不正';
        RETURN @result;
    END;

    IF @is_return = 1
    BEGIN
        SET @destination = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[2])[1]', 'varchar(255)'))), '');
        SET @seq_int = TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[3])[1]', 'varchar(255)'))), ''));
        SET @child_item = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[4])[1]', 'varchar(255)'))), '');
        SET @quantity_int = TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[5])[1]', 'varchar(50)'))), ''));
        SET @cleaning_int = TRY_CONVERT(int, NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[6])[1]', 'varchar(50)'))), ''));
    END
    ELSE
    BEGIN
        SET @destination = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[1])[1]', 'varchar(255)'))), '');
        SET @store = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[4])[1]', 'varchar(255)'))), '');
        SET @required_date = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[6])[1]', 'varchar(255)'))), '');
        SET @process_date = COALESCE(NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[7])[1]', 'varchar(255)'))), ''), @process_date);
        SET @plant = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[9])[1]', 'varchar(255)'))), '');
        SET @voucher_no = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[10])[1]', 'varchar(255)'))), '');
        SET @lot = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[11])[1]', 'varchar(255)'))), '');
        SET @storage_location = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[12])[1]', 'varchar(255)'))), '');

        SET @at_pos = CHARINDEX('@', ISNULL(@zno, ''));
        IF @at_pos > 0
        BEGIN
            SET @child_item = NULLIF(LTRIM(RTRIM(LEFT(@zno, @at_pos - 1))), '');
            SET @parent_item = NULLIF(LTRIM(RTRIM(SUBSTRING(@zno, @at_pos + 1, 255))), '');
        END
        ELSE
        BEGIN
            SET @parent_item = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[2])[1]', 'varchar(255)'))), '');
            SET @child_item = NULLIF(LTRIM(RTRIM(@qr_xml.value('(/x/i[3])[1]', 'varchar(255)'))), '');
        END;
    END;

    IF @quantity_int IS NULL OR @quantity_int < 1
    BEGIN
        SELECT @result = 4, @msg = '数量不正';
        RETURN @result;
    END;

    IF @cleaning_int IS NULL OR @cleaning_int < 0
    BEGIN
        SELECT @result = 5, @msg = '洗浄不正';
        RETURN @result;
    END;

    IF @destination <> @allowed_destination
    BEGIN
        SELECT @result = 6, @msg = '出庫先が違います';
        RETURN @result;
    END;

    IF @child_item IS NULL OR (@is_return = 0 AND @parent_item IS NULL)
    BEGIN
        SELECT @result = 2, @msg = '商品が違います';
        RETURN @result;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @is_return = 1
        BEGIN
            IF @seq_int IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 1, @msg = '元連番不正';
                RETURN @result;
            END;

            SET @lock_resource = N'T_SmxTrc_入庫_' + CONVERT(nvarchar(20), @seq_int);
            EXEC @lock_result = sys.sp_getapplock
                @Resource = @lock_resource,
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 10000;

            IF @lock_result < 0
                THROW 50001, '更新ロック失敗', 1;

            SELECT TOP (1)
                @source_id = [ID],
                @source_destination = CONVERT(varchar(255), [出庫先CD]),
                @source_child = CONVERT(varchar(255), [出庫品目]),
                @parent_item = CONVERT(varchar(255), [上位品目]),
                @process_date = COALESCE(CONVERT(varchar(255), [処理日]), @process_date),
                @finished = NULLIF(LTRIM(RTRIM(CONVERT(varchar(30), [終了日時], 121))), '')
            FROM [dbo].[T_SmxTrc] WITH (UPDLOCK, HOLDLOCK)
            WHERE [連番] = @seq_int
            ORDER BY [ID] DESC;

            IF @source_destination IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 1, @msg = '元連番なし';
                RETURN @result;
            END;

            IF @destination <> @source_destination
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 6, @msg = '出庫先が違います';
                RETURN @result;
            END;

            IF @child_item <> @source_child
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 2, @msg = '商品が違います';
                RETURN @result;
            END;

            IF @finished IS NOT NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @result = 3, @msg = '登録済';
                RETURN @result;
            END;

            UPDATE [dbo].[T_SmxTrc]
            SET [終了日時] = GETDATE()
            WHERE [ID] = @source_id;

            IF NOT EXISTS
            (
                SELECT 1
                FROM [dbo].[T_シートリーダ] WITH (UPDLOCK, HOLDLOCK)
                WHERE [bcd] = @qr
                  AND [記号] = 'SMX入庫'
            )
            BEGIN
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
            END;

            COMMIT TRANSACTION;
            SELECT @result = 0, @msg = '入庫登録';
            RETURN 0;
        END;

        IF @cleaning_int = 0
        BEGIN
            SET @lock_resource = N'T_SmxTrc_通常入庫_' + CONVERT(nvarchar(20), CHECKSUM(@qr));
            EXEC @lock_result = sys.sp_getapplock
                @Resource = @lock_resource,
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 10000;

            IF @lock_result < 0
                THROW 50002, '登録ロック失敗', 1;

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
            SELECT @result = 0, @msg = '入庫登録';
            RETURN 0;
        END;

        EXEC @lock_result = sys.sp_getapplock
            @Resource = N'T_SmxTrc_連番',
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 10000;

        IF @lock_result < 0
            THROW 50003, '連番ロック失敗', 1;

        SELECT @next_seq = ISNULL(MAX([連番]), 0) + 1
        FROM [dbo].[T_SmxTrc] WITH (UPDLOCK, HOLDLOCK);

        INSERT INTO [dbo].[T_SmxTrc]
        (
            [自IPアドレス], [現在日付], [BHT側時刻], [社員CD],
            [出庫先CD], [出庫品目], [上位品目], [棚番],
            [数量], [所要日], [処理日], [プラント],
            [伝票番号], [ロット], [保管場所], [洗浄方法],
            [QRコード], [連番], [開始日時], [終了日時], [備考]
        )
        VALUES
        (
            LEFT(ISNULL(@syaincd, ''), 15), LEFT(ISNULL(@bhtdate, ''), 50), LEFT(ISNULL(@bhttime, ''), 50), LEFT(@syaincd, 50),
            LEFT(@destination, 50), LEFT(@child_item, 50), LEFT(@parent_item, 50), LEFT(@store, 50),
            CONVERT(decimal(18, 3), @quantity_int), LEFT(@required_date, 50), LEFT(@process_date, 50), LEFT(@plant, 50),
            LEFT(@voucher_no, 50), LEFT(@lot, 50), LEFT(@storage_location, 50), RIGHT('000' + CONVERT(varchar(3), @cleaning_int), 3),
            LEFT(@qr, 255), @next_seq, GETDATE(), NULL, LEFT(@rno, 255)
        );

        COMMIT TRANSACTION;
        SELECT @result = 0, @msg = CONVERT(varchar(20), @next_seq);
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT @result = 9, @msg = '入庫登録失敗';
        RETURN @result;
    END CATCH;
END;
GO
