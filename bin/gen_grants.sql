-- Export all GRANTS (dbo) to single file. Sybase ASE 15.5.
set nocount on
go
-- Cursor declared in its own batch (ASE rule)
declare obj_cursor cursor for
select name from sysobjects where uid = 1 and type in ('P', 'U', 'V', 'FN', 'TF', 'TR')
order by name
go
-- Loop body - separate batch
declare @objname varchar(255), @msg varchar(500)
declare @action int, @uid int, @grantee varchar(255)

open obj_cursor
fetch obj_cursor into @objname

while @@sqlstatus = 0
begin
    create table #g (action int, uid int, rownum int identity)

    insert into #g (action, uid)
    select p.action, p.uid
    from sysprotects p, sysobjects o
    where p.id = o.id and o.name = @objname and o.uid = 1
    and p.action != 151
    and user_name(p.uid) is not null

    declare @i int, @cnt int
    select @cnt = 0, @i = 1
    select @cnt = count(*) from #g

    while @i <= @cnt
    begin
        select @action = action, @uid = uid from #g where rownum = @i
        select @grantee = user_name(@uid)

        select @msg = 'GRANT '
            + case @action
                when 193 then 'SELECT'
                when 195 then 'INSERT'
                when 196 then 'DELETE'
                when 197 then 'UPDATE'
                when 224 then 'EXECUTE'
                else 'UNKNOWN(' + ltrim(str(@action)) + ')'
              end
            + ' ON ' + @objname
            + ' TO ' + @grantee
        print @msg

        select @i = @i + 1
    end

    if @cnt > 0
    begin
        print 'go'
        print ''
    end

    drop table #g

    fetch obj_cursor into @objname
end

close obj_cursor
deallocate obj_cursor
go
