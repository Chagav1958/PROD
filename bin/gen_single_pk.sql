set nocount on
go

declare @tid int, @iid smallint, @iname sysname
declare @keypos int, @colname sysname, @cols varchar(2000), @msg varchar(500)

select @tid = id from sysobjects where name = @tabname and uid = 1
if @tid is not null
begin
    select @iid = indid from sysindexes
    where id = @tid and name = @pkname and indid = 1 and (status & 2048) = 2048

    if @iid is not null
    begin
        select @msg = 'ALTER TABLE dbo.' + @tabname
        print @msg
        select @msg = '    ADD CONSTRAINT ' + @pkname + ' PRIMARY KEY'
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
    end
end
go
