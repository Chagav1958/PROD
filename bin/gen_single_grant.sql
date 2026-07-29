set nocount on
go

declare @action int, @uid int
declare @grantee varchar(255)
declare @msg varchar(500)

declare g_cursor cursor for
select p.action, p.uid
from sysprotects p, sysobjects o
where p.id = o.id and o.name = @objname and o.uid = 1
and p.action != 151
and user_name(p.uid) is not null

open g_cursor
fetch g_cursor into @action, @uid
while @@sqlstatus = 0
begin
    select @grantee = user_name(@uid)
    select @msg = 'GRANT '
        + case @action
            when 193 then 'SELECT'
            when 195 then 'INSERT'
            when 196 then 'DELETE'
            when 197 then 'UPDATE'
            when 224 then 'EXECUTE'
            when 282 then 'DELETE STATISTICS'
            when 320 then 'UPDATE STATISTICS'
            when 326 then 'TRUNCATE TABLE'
            else 'PERM_' + convert(varchar, @action)
          end
        + ' ON dbo.' + @objname
        + ' TO ' + @grantee
    print @msg
    print 'go'
    fetch g_cursor into @action, @uid
end
close g_cursor
deallocate cursor g_cursor
go
