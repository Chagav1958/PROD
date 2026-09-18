-- Export all INDEXES (dbo) to single file. Sybase ASE 15.5.
set nocount on
go
-- Cursor declared in its own batch (ASE rule)
declare idx_cursor cursor for
select o.name, i.indid, i.status, i.name
from sysindexes i
inner join sysobjects o on i.id = o.id
where o.uid = 1 and o.type = 'U'
and i.indid > 0 and i.indid < 255
and i.name is not null
and not (i.status & 2048) = 2048
order by o.name, i.name
go
-- Loop body - separate batch
declare @tname varchar(255), @iid smallint, @istatus int, @iname varchar(255)
declare @keypos int, @colname varchar(255)
declare @cols varchar(2000), @msg varchar(500)

open idx_cursor
fetch idx_cursor into @tname, @iid, @istatus, @iname

while @@sqlstatus = 0
begin
    select @msg = 'IF EXISTS (SELECT * FROM sysindexes WHERE id=OBJECT_ID(''dbo.' + @tname + ''') AND name=''' + @iname + ''')'
    print @msg
    print 'BEGIN'
    select @msg = '    DROP INDEX ' + @tname + '.' + @iname
    print @msg
    select @msg = '    IF EXISTS (SELECT * FROM sysindexes WHERE id=OBJECT_ID(''dbo.' + @tname + ''') AND name=''' + @iname + ''')'
    print @msg
    select @msg = '        PRINT ''<<< FAILED DROPPING INDEX dbo.' + @tname + '.' + @iname + ' >>>'''
    print @msg
    print '    ELSE'
    select @msg = '        PRINT ''<<< DROPPED INDEX dbo.' + @tname + '.' + @iname + ' >>>'''
    print @msg
    print 'END'
    print 'go'
    print ''

    select @msg = 'CREATE'
    if (@istatus & 2) = 2 select @msg = @msg + ' UNIQUE'
    if @iid = 1 select @msg = @msg + ' CLUSTERED' else select @msg = @msg + ' NONCLUSTERED'
    select @msg = @msg + ' INDEX ' + @iname
    print @msg
    select @msg = '    ON dbo.' + @tname
    print @msg
    print '('

    select @keypos = 1, @cols = ''
    while 1 = 1
    begin
        select @colname = index_col(@tname, @iid, @keypos)
        if @colname is null break
        if @cols != '' select @cols = @cols + ', '
        select @cols = @cols + @colname
        select @keypos = @keypos + 1
    end
    select @msg = '    ' + @cols
    print @msg
    print ')'
    print 'go'
    print ''

    select @msg = 'IF EXISTS (SELECT * FROM sysindexes WHERE id=OBJECT_ID(''dbo.' + @tname + ''') AND name=''' + @iname + ''')'
    print @msg
    select @msg = '    PRINT ''<<< CREATED INDEX dbo.' + @tname + '.' + @iname + ' >>>'''
    print @msg
    print 'ELSE'
    select @msg = '    PRINT ''<<< FAILED CREATING INDEX dbo.' + @tname + '.' + @iname + ' >>>'''
    print @msg
    print 'go'
    print ''

    fetch idx_cursor into @tname, @iid, @istatus, @iname
end

close idx_cursor
deallocate idx_cursor
go
