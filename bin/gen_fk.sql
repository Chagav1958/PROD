-- Export all FOREIGN KEYS (dbo) to single file. Sybase ASE 15.5.
set nocount on
go
-- Single cursor over all FK constraints (declared in own batch - ASE rule)
declare fk_main_cursor cursor for
select o.name, r.constrid, r.reftabid, o2.name, o3.name
from sysreferences r
inner join sysobjects o on r.tableid = o.id
inner join sysobjects o2 on r.reftabid = o2.id
inner join sysobjects o3 on r.constrid = o3.id
where o.uid = 1
order by o.name, o3.name
go
-- Loop body - separate batch
declare @tname varchar(255), @constrid int, @rid int
declare @rtname varchar(255), @fkname varchar(255)
declare @keypos int, @cname varchar(255), @rcname varchar(255)
declare @ncols int
declare @msg varchar(500), @cols varchar(2000), @rcols varchar(2000)

open fk_main_cursor
fetch fk_main_cursor into @tname, @constrid, @rid, @rtname, @fkname

while @@sqlstatus = 0
begin
    select @msg = 'ALTER TABLE dbo.' + @tname
    print @msg
    select @msg = '    ADD CONSTRAINT ' + @fkname + ' FOREIGN KEY'
    print @msg
    print '('

    select @ncols = 1
    if (select fokey2 from sysreferences where constrid = @constrid) > 0 select @ncols = 2
    if (select fokey3 from sysreferences where constrid = @constrid) > 0 select @ncols = 3
    if (select fokey4 from sysreferences where constrid = @constrid) > 0 select @ncols = 4
    if (select fokey5 from sysreferences where constrid = @constrid) > 0 select @ncols = 5
    if (select fokey6 from sysreferences where constrid = @constrid) > 0 select @ncols = 6
    if (select fokey7 from sysreferences where constrid = @constrid) > 0 select @ncols = 7
    if (select fokey8 from sysreferences where constrid = @constrid) > 0 select @ncols = 8
    if (select fokey9 from sysreferences where constrid = @constrid) > 0 select @ncols = 9
    if (select fokey10 from sysreferences where constrid = @constrid) > 0 select @ncols = 10

    select @cols = ''
    select @keypos = 1
    while @keypos <= @ncols
    begin
        select @cname = null
        if @keypos = 1 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey1 = c.colid
        if @keypos = 2 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey2 = c.colid
        if @keypos = 3 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey3 = c.colid
        if @keypos = 4 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey4 = c.colid
        if @keypos = 5 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey5 = c.colid
        if @keypos = 6 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey6 = c.colid
        if @keypos = 7 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey7 = c.colid
        if @keypos = 8 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey8 = c.colid
        if @keypos = 9 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey9 = c.colid
        if @keypos = 10 select @cname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.tableid = c.id and r.fokey10 = c.colid
        if @cname is null break
        if @cols != '' select @cols = @cols + ', '
        select @cols = @cols + @cname
        select @keypos = @keypos + 1
    end
    select @msg = '    ' + @cols
    print @msg
    print ')'

    select @msg = '    REFERENCES dbo.' + @rtname
    print @msg
    print '('

    select @rcols = ''
    select @keypos = 1
    while @keypos <= @ncols
    begin
        select @rcname = null
        if @keypos = 1 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey1 = c.colid
        if @keypos = 2 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey2 = c.colid
        if @keypos = 3 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey3 = c.colid
        if @keypos = 4 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey4 = c.colid
        if @keypos = 5 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey5 = c.colid
        if @keypos = 6 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey6 = c.colid
        if @keypos = 7 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey7 = c.colid
        if @keypos = 8 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey8 = c.colid
        if @keypos = 9 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey9 = c.colid
        if @keypos = 10 select @rcname = c.name from sysreferences r, syscolumns c where r.constrid = @constrid and r.reftabid = c.id and r.refkey10 = c.colid
        if @rcname is null break
        if @rcols != '' select @rcols = @rcols + ', '
        select @rcols = @rcols + @rcname
        select @keypos = @keypos + 1
    end
    select @msg = '    ' + @rcols
    print @msg
    print ')'
    print 'go'
    print ''

    fetch fk_main_cursor into @tname, @constrid, @rid, @rtname, @fkname
end

close fk_main_cursor
deallocate fk_main_cursor
go
