-- ╨У╨╡╨╜╨╡╤А╨░╤Ж╨╕╤П CREATE TABLE (Sybase ASE 15.5)
-- ╨Шь  ЄрсышЎ√ яхЁхфр╕Єё  ўхЁхч Ёыюсры№эє■ тЁхьхээє■ ЄрсышЎє ##gen_tname
go
declare @tname varchar(255)
, @sname varchar(255)
, @sname_out varchar(255)
, @tname_out varchar(255)
, @line varchar(1000)

select @tname = tname from ##gen_tname
select @tname_out = name from sysobjects where id = object_id(@tname)
select @sname_out = user_name(uid) from sysobjects where id = object_id(@tname)

if @tname_out is null
begin
    select @line = '-- Table not found: ' + @tname
    print @line
    drop table ##gen_tname
    return
end

select @line = 'CREATE TABLE ' + @sname_out + '.' + @tname_out
print @line
print '('
go

-- Declare cursor — оlinstvennыy v svoyom batch
declare c_cols cursor for
select c.colid, c.name, t.name, c.length, c.prec, c.scale, c.status
from syscolumns c join systypes t on c.usertype = t.usertype
where c.id = object_id((select tname from ##gen_tname))
order by c.colid
go

-- Cursor loop — vse v odnom batche (declare + open + fetch + while + close)
declare @colid int, @cname varchar(255), @typename varchar(50)
, @len int, @prec int, @scale int, @status int
, @is_first bit, @line varchar(1000)

select @is_first = 1
open c_cols
fetch c_cols into @colid, @cname, @typename, @len, @prec, @scale, @status

while @@sqlstatus = 0
begin
    if @typename = 'timestamp'
        select @line = '    ' + @cname + '  timestamp NULL'
    else
    begin
        select @line = '    ' + @cname + '  ' + @typename
        if @typename in ('char','varchar','nchar','nvarchar','binary','varbinary')
            select @line = @line + '(' + convert(varchar, @len) + ')'
        else if @typename in ('numeric','decimal')
            select @line = @line + '(' + convert(varchar, @prec) + ', ' + convert(varchar, @scale) + ')'
        else if @typename in ('float','real')
            select @line = @line + '(' + convert(varchar, @prec) + ')'
        if (@status & 128) = 128 select @line = @line + ' identity'
        else if (@status & 8) = 8 select @line = @line + ' NOT NULL'
        else select @line = @line + ' NULL'
    end

    if @is_first = 1 select @is_first = 0
    else select @line = ',' + @line

    print @line

    fetch c_cols into @colid, @cname, @typename, @len, @prec, @scale, @status
end

close c_cols
print ')'
go

drop table ##gen_tname
go
