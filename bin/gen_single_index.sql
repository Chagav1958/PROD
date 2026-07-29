set nocount on
go

declare @tid int, @iid smallint, @istatus int, @iname sysname
declare @keypos int, @colname sysname, @cols varchar(2000), @msg varchar(500)

select @tid = id from sysobjects where name = @tabname and uid = 1
if @tid is not null
begin
    select @iid = indid, @istatus = status, @iname = name
    from sysindexes where id = @tid and name = @idxname

    if @iname is not null
    begin
        select @msg = 'IF EXISTS (SELECT * FROM sysindexes WHERE id=OBJECT_ID(''dbo.' + @tabname + ''') AND name=''' + @idxname + ''')'
        print @msg
        print 'BEGIN'
        select @msg = '    DROP INDEX ' + @tabname + '.' + @idxname
        print @msg
        select @msg = '    IF EXISTS (SELECT * FROM sysindexes WHERE id=OBJECT_ID(''dbo.' + @tabname + ''') AND name=''' + @idxname + ''')'
        print @msg
        print '        PRINT ''<<< FAILED DROPPING INDEX dbo.' + @tabname + '.' + @idxname + ' >>>'''
        print '    ELSE'
        print '        PRINT ''<<< DROPPED INDEX dbo.' + @tabname + '.' + @idxname + ' >>>'''
        print 'END'
        print 'go'
        print ''

        select @msg = 'CREATE'
        if (@istatus & 2) = 2 select @msg = @msg + ' UNIQUE'
        if @iid = 1 select @msg = @msg + ' CLUSTERED' else select @msg = @msg + ' NONCLUSTERED'
        select @msg = @msg + ' INDEX ' + @iname
        print @msg
        select @msg = '    ON dbo.' + @tabname
        print @msg
        print '('

        select @keypos = 1, @cols = ''
        while 1 = 1
        begin
            select @colname = index_col(@tabname, @iid, @keypos)
            if @colname is null break
            if @cols != '' select @cols = @cols + ', '
            select @cols = @cols + @colname
            select @keypos = @keypos + 1
        end
        print '    ' + @cols
        print ')'
        print 'go'

        select @msg = 'IF EXISTS (SELECT * FROM sysindexes WHERE id=OBJECT_ID(''dbo.' + @tabname + ''') AND name=''' + @idxname + ''')'
        print @msg
        print '    PRINT ''<<< CREATED INDEX dbo.' + @tabname + '.' + @idxname + ' >>>'''
        print 'ELSE'
        print '    PRINT ''<<< FAILED CREATING INDEX dbo.' + @tabname + '.' + @idxname + ' >>>'''
        print 'go'
    end
end
go
