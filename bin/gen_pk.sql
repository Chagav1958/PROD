-- Export all PRIMARY KEYS (dbo) to single file. Sybase ASE 15.5.
set nocount on
go
-- Cursor declared in its own batch (ASE rule)
declare pk_cursor cursor for
select o.name, i.name
from sysindexes i
inner join sysobjects o on i.id = o.id
where o.uid = 1 and o.type = 'U'
and i.indid = 1 and (i.status & 2048) = 2048
and i.name is not null
order by o.name
go
-- Loop body - separate batch
declare @tname varchar(255), @pkname varchar(255)
declare @iid smallint, @keypos int, @colname varchar(255)
declare @cols varchar(2000), @msg varchar(500)

open pk_cursor
fetch pk_cursor into @tname, @pkname

while @@sqlstatus = 0
begin
    select @iid = 1

    select @msg = 'ALTER TABLE dbo.' + @tname
    print @msg
    select @msg = '    ADD CONSTRAINT ' + @pkname + ' PRIMARY KEY'
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

    fetch pk_cursor into @tname, @pkname
end

close pk_cursor
deallocate pk_cursor
go
