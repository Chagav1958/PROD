declare @objname varchar(255)
select @objname = objname from ##gen_gobj

declare @action int, @uid int
declare @grantee varchar(255)
declare @msg varchar(500)
declare @i int, @cnt int

create table #g (action int, uid int, rownum int identity)

insert into #g (action, uid)
select p.action, p.uid
from sysprotects p, sysobjects o
where p.id = o.id and o.name = @objname and o.uid = 1
and p.action != 151
and user_name(p.uid) is not null

select @cnt = @@rowcount, @i = 1

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
            when 282 then 'DELETE STATISTICS'
            when 320 then 'UPDATE STATISTICS'
            when 326 then 'TRUNCATE TABLE'
            else 'PERM_' + convert(varchar, @action)
          end
        + ' ON dbo.' + @objname
        + ' TO ' + @grantee
    print @msg
    print 'go'
    set @i = @i + 1
end

drop table #g
go
