 CREATE PROCEDURE dbo.usp_add_report_to_reestr_t2
(
    @rep_id	        numeric(10, 0)
    , @reestr_id_out    numeric(10, 0) output
    , @ErrMsg       varchar (255) output
    , @debug        int = 0
)
AS
BEGIN
    -- SYBASE-6836 АИС. ЭЦП. Автоматизация  
 реестров ФУ. 2020-08-04 Сердюков А. И.
    -- SYBASE-17607  Чага В.И.  2025-07-31  Добавление новых типов реестров на в
	 ыплату
    -- Процедура usp_add_report_to_reestr_t2:
    -- /*Добавляем отчёт в реестр ФУ.*/   Так не здорово. 
    -- В таблице аудита  
 отчётов записи по изменению статуса отчёта и добавления отчёта в реестр меняютс
	 я местами.
    -- Поэтому процедура будет только возвращать ID реестра,
    -- а добавлять отчёт в реестр мы будет позже.
    -- Процедура вызывается при изменении статуса отчё 
 та на "Подтверждён" ('A')
    -- из триггера tu_ais_report (для бумажных актов) 
    -- или из процедуры usp_ecp_report для электронных актов. 
    
    --declare @debug int  -- Флаг работы в режиме отладки = 1 (0 - боевой режим)
	 
    --set @debug = 1      
  -- В режиме отладки процедура запускается тестировщиком.
    
    declare     
      --@ErrMsg       varchar (255)
      @res          int
    , @status_new   int
    
    , @rep_state char(1)
    , @rep_state_new char(1)
    , @rep_cdp_key varchar(64)
  
    , @sign_elec int
    , @send_state varchar(1)
    , @send_path varchar(500)

    -- Парметры реестра ФУ
    , @reestr_type_id_new int
    , @reestr_id	numeric(10, 0)
    , @reestr_name	varchar(255)
    , @reestr_date	datetime
    , @reestr_date_end	dat 
 etime
    , @reestr_date_pay	datetime -- Дата оплаты (необходима для фд.) Определяется
	  как следующий понедельник.
    , @state	int
    , @reestr_id_next	numeric(10, 0)
    , @state_next	int
    , @add_report_to_reestr int
    -- Для определения периода дл 
 я реестра
    , @Today datetime
    , @Day_Number_Now int
    --, @Day_to_Monday_back int    
    , @Day_back_to_Begin int    --Дней назад было начало периода реестра    
    , @Day_Number_Begin int     --День начала периода реестра
    
    set @res = 0
 
     set @add_report_to_reestr = 0   -- Сбросим флаг дабавления отчёта в реестр 
	 ФУ
                                                                    -- Определяе
	 м тип реестра ФУ для отчёта @rep_id и пишем сообщение об ошибке, если ч
	 то не так.
            
                                                          -- Меняем запрос на фу
	 нкцию 
                                                                    --create fun
	 ction dbo.fn_reestr_type_id(
                                                             
         --  @rep_id numeric(10)     -- ID отчёта
                                                                    --  , @test_
	 id int)         -- Проверять наличие отчёта в реестре/запросе на выплат
	 у и статус отчёта "Подтверждён" и выдавать ошибку
      
                                                                --returns int

    select @reestr_type_id_new	= dbo.fn_reestr_type_id(@rep_id, 0)

    if @debug = 1 begin
        select '@reestr_type_id_new' = @reestr_type_id_new, "Тип реестра ФУ" = r
	 t.ree 
 str_type_id, rt.reestr_type_name 
        from dbo.ais_cat_reestr_type rt
        where rt.reestr_type_id = @reestr_type_id_new
    end
    
    -- Ищем реестр по полученному типу реестра и по дате подтверждения отчёта (э
	 то сегодня, сейчас).
    if @reest 
 r_type_id_new in (1, 6, 14, 15 ) begin
        if @debug = 1 begin
            print "Добавим акт в реестр для ФУ."
        end 

                                                                    -- Найдём пе
	 риод реестра по дате подтверждения отчёта.
   
       set @Today = current_date()                     -- Берём текущую дату, по
	 скольку отчёт получил статус "Подтверждён" только сейчас.
        --set @Today = "2025-10-16"                     -- Для отладки Берём нуж
	 ную дату, проверяем работу на 2025-10- 
 23.

        set @Day_Number_Now = DATEPART(dw, @Today)
        
                                                                    -- Считаем с
	 колько дней назад было начало периода реестра.
                                                                
      -- Для @reestr_type_id_new = 1 (ФЛ-АД) Понедельник (2 день второй).
                                                                    -- Для @rees
	 tr_type_id_new = 2 (ФЛ-ДВОУ) Пятница (6 день шестой).
        set @Day_Number_Begin = case @reestr_typ 
 e_id_new
                                    when 1 then 2
                                    when 6 then 6
                                    when 14 then 2
                                    when 15 then 6
                                    --else - 
 1
                                end
        set @Day_back_to_Begin = @Day_Number_Now - @Day_Number_Begin   
        if @Day_back_to_Begin < 0
            set @Day_back_to_Begin = @Day_back_to_Begin + 7
        
        set @reestr_date = DATEADD(dd, -1  
 * @Day_back_to_Begin, @Today)    -- Начало периода
        set @reestr_date_end = DATEADD(dd, 7, @reestr_date)                -- Ок
	 ончание периода следующий такой же день недели 00:00:00
        set @reestr_date_pay = @reestr_date_end -- Дата оплаты. Опре 
 деляется как следующий такой же день недели.
        --Проверяем наличие реестра
        SELECT 
            @reestr_id = rr.reestr_id,   
            @state = rr.state
        FROM report_reestr rr   
        where rr.reestr_type_id = @reestr_type_id_new 
 
            and rr.reestr_date = @reestr_date
        -- Если даты окончания периода нет, то считаем, что реестра тоже нет (та
	 кими могут быть только реестры, созданные ранее этой доработки).
        and case when rr.reestr_date_end is not null then rr.re 
 estr_date_end else '2100-01-01' end = @reestr_date_end
        
        if @reestr_id is null begin
            -- Реестр не найден, надо создавать новый
            if @debug = 1 begin 
                print "Реестр не найден, надо создавать новый"
      
        end
            set @reestr_name = "Москва, СЗД, Регионы "                          
	 -- SYBASE-17607  Чага В.И.  2025-07-31    Наименование типа реестра бер
	 ем из функции uf_get_name_reestr_type
                + dbo.uf_get_name_reestr_type( @reestr_ 
 type_id_new, 'short' )
                + ' ' + convert(varchar(10), @reestr_date_pay, 105)
            INSERT INTO report_reestr (our_subj_id, reestr_date, reestr_type_id,
	  reestr_name, b2b, reestr_date_end, state
                        , reestr_date_send 
 , reestr_date_pay )
            VALUES (1, @reestr_date, @reestr_type_id_new, @reestr_name, 0, @rees
	 tr_date_end, 0, NULL, @reestr_date_pay)
            SELECT @res = @@ERROR
            IF ( @res <> 0 ) BEGIN
                set @ErrMsg = "RC = " + cast(@ 
 res as varchar(10)) + "." + "Ошибка добавления нового реестра на текущую неделю
	 ."
            END
            ELSE BEGIN
                set @reestr_id = @@identity     -- Получаем id созданного реестр
	 а
                set @add_report_to_reestr = 1   -- С 
 тавим флаг дабавления отчёта в реестр   
                set @state = 0                  -- Для созданного реестра переме
	 нная была NULL
                if @debug = 1 begin 
                    print "Реестр на текущую неделю создан reestr_id = %1!", @re
	 es 
 tr_id
                end
            END
        end
        if @reestr_id is not null begin
                                                                        -- Реест
	 р нашли, надо проверить его статус
                                               
                           --print "Реестр нашли, надо проверить его статус"
            if @state = 0 begin
                                                                        -- Стату
	 с отправки годится, добавим отчёт в реестр.
                set @ad 
 d_report_to_reestr = 1   -- Ставим флаг дабавления отчёта в реестр   
                if @debug = 1 begin 
                    print "Статус отправки: 0. Добавим акт в этот Реестр reestr_
	 id = %1!", @reestr_id
                end
            end
           
   if @state = 1 begin
                -- Этот реестр уже отправлен, надо проверить наличие реестра на 
	 следующую неделю.
                if @debug = 1 begin 
                    print "Этот реестр reestr_id = %1! уже отправлен, надо прове
	 рить наличие реест 
 ра на следующую неделю.", @reestr_id
                end
                set @reestr_date = @reestr_date_end     --Сдвигаем начало период
	 а на его конец (неделю или 7 дней)
                set @reestr_date_end = DATEADD(dd, 7, @reestr_date_end)     --Сд
	 виг 
 аем конец периода на неделю (7 дней)
                set @reestr_date_pay = @reestr_date_end -- Дата оплаты. Определя
	 ется как следующий понедельник.
                if @debug = 1 begin 
                    select '@reestr_date' = @reestr_date
             
             , '@reestr_date_end' = @reestr_date_end
                        , '@reestr_date_pay' = @reestr_date_pay
                        , '@reestr_date_pay_2' = DATEADD(dd, 7, @reestr_date_end
	 )     --Сдвигаем конец периода на неделю (7 дней)
          
            /* Adaptive Server has expanded all '*' elements in the following st
	 atement */ SELECT 
                        rr.reestr_id, rr.our_subj_id, rr.reestr_date, rr.reestr_
	 type_id, rr.register_datetime, rr.register_username, rr.reestr_name, rr
	 .b2b,  
 rr.last_update, rr.state, rr.reestr_date_end, rr.reestr_date_send, rr.reestr_da
	 te_pay, rr.email_address, rr.str_comment                               
	      
                    FROM report_reestr rr   
                    where rr.reestr_type_id = @reestr_ 
 type_id_new
                        and rr.reestr_date = @reestr_date
                                                                                
	 -- Если даты окончания периода нет, то считаем, что реестра тоже нет (т
	 акими могут быть только реестры, с 
 озданные ранее этой доработки).
                        and case when rr.reestr_date_end is not null then rr.ree
	 str_date_end else '2100-01-01' end = @reestr_date_end
                end
                SELECT 
                    @reestr_id_next = rr.rees 
 tr_id,   
                    @state_next = rr.state
                FROM report_reestr rr   
                where rr.reestr_type_id = @reestr_type_id_new
                    and rr.reestr_date = @reestr_date
                                              
                                -- Если даты окончания периода нет, то считаем, 
	 что реестра тоже нет (такими могут быть только реестры, созданные ранее
	  этой доработки).
                    and case when rr.reestr_date_end is not null then rr.reestr_
	 date_en 
 d else '2100-01-01' end = @reestr_date_end
                
                if @reestr_id_next is null begin
                    -- Реестр на следующую неделю не найден, надо создавать новы
	 й
                    if @debug = 1 begin 
                        
  print "Реестр на следующую неделю не найден, надо создавать новый"
                    end
                    
                    set @reestr_name = "Москва, СЗД, Регионы "                  
	         -- SYBASE-17607  Чага В.И.  2025-07-31    Наименование 
  типа реестра берем из функции uf_get_name_reestr_type
                        + dbo.uf_get_name_reestr_type( @reestr_type_id_new, 'sho
	 rt' )
                        + ' ' + convert(varchar(10), @reestr_date_pay, 105)

                    INSERT INTO repor 
 t_reestr (our_subj_id, reestr_date, reestr_type_id, reestr_name, b2b, reestr_da
	 te_end, state
                                , reestr_date_send, reestr_date_pay )
                    VALUES (1, @reestr_date, @reestr_type_id_new, @reestr_name, 
	 0, @reestr_d 
 ate_end, 0, NULL, @reestr_date_pay)
                    IF ( @res <> 0 ) BEGIN
                        --RollBack Trigger With RaisError 20007 'Ошибка вставки 
	 нового реестра на следующую неделю.'
                        set @ErrMsg = "RC = " + cast(@res a 
 s varchar(10)) + "." + "Ошибка вставки нового реестра на следующую неделю."
                    END
                    ELSE BEGIN
                        set @reestr_id_next = @@identity    -- Получаем id созда
	 нного реестра
                        set @a 
 dd_report_to_reestr = 1       -- Ставим флаг дабавления отчёта в реестр   
                        set @state_next = 0                 -- Для созданного ре
	 естра переменная была NULL
                        if @debug = 1 begin 
                             
 print "Реестр на следующую неделю создан reestr_id = %1!", @reestr_id
                        end
                    END
                end
                if @reestr_id_next is not null begin
                    -- Реестр на следующую неделю нашли, над 
 о проверить его статус
                    if @state_next = 0 begin
                                                                        -- Стату
	 с отправки годится, добавим отчёт в реестр.
                                                                
          --print "Статус отправки: 0, годится, добавим отчёт в реестр."
                        set @reestr_id = @reestr_id_next
                        set @add_report_to_reestr = 1   -- Ставим флаг дабавлени
	 я отчёта в реестр   
                        i 
 f @debug = 1 begin 
                            print "Статус отправки: 0. Добавим акт в этот Реестр
	  reestr_id = %1!", @reestr_id
                        end
                    end
                    if @state_next = 1 begin
                        set  
 @res = -200
                        set @ErrMsg = "RC = " + cast(@res as varchar(10)) + "." 
	 + "Реестр на следующую неделю reestr_id_next = " + cast(@reestr_id_next
	  as varchar(10)) + " уже отправлен, а это бардак."
                        if @debug = 1 beg 
 in 
                            print "Реестр на следующую неделю reestr_id_next = %
	 1! уже отправлен, а это бардак.", @reestr_id_next
                        end
                        -- Ничего не делаем.
                    end
                end
     
         end
                                                                        --if @st
	 ate is null begin
                                                                            -- Т
	 ак не должно быть, но всё же. Ничего не делаем.
                  
                                                            --print "Статус отпр
	 авки: NULL. Так не должно быть, но всё же. Ничего не делаем."
                                                                        --end
        end
        if @add_report_t 
 o_reestr = 1 begin
            -- Просто вернём ID реестра.
            set @reestr_id_out = @reestr_id
            
                                                                        -- Добав
	 им отчёт в реестр @reestr_id
                              
                                            --update ais_report
                                                                        --set re
	 estr_id = @reestr_id
                                                                        --where 
	 rep_id = @r 
 ep_id
                                                                        
                                                                        --SELECT
	  @res = @@ERROR
                                                                        
        
                                                                  --IF ( @res <>
	  0 ) BEGIN
                                                                            --Ro
	 llBack Trigger With RaisError 20008 'Ошибка вставки отчёта в реестр.'
                
                                                          --    set @ErrMsg = "R
	 C = " + cast(@res as varchar(10)) + "." + "Ошибка вставки отчёта в реес
	 тр reestr_id = " + cast(@reestr_id as varchar(10))
                                                       
                   --END
                                                                        --ELSE B
	 EGIN
                                                                        --     s
	 et @ErrMsg = "Отчёт добавлен в реестр reestr_id = " + cast(@reestr 
 _id as varchar(10)) + ". " + @reestr_name
                                                                        --END
        end
        -- Если добавлять отчёт в реестр нельзя, @reestr_id_out = 0 так и остане
	 тся.
    end
    else begin
                
                                                          --Если реестр не типов
	  (1, 6, 14, 15 )  @reestr_type_id_new in (1, 6)
        set @reestr_id_out = 0
                                                                        -- SYBAS
	 E-17607  Чага В.И 
 .  2025-07-31  Берем названия из таблицы 
        Select @ErrMsg = Reestr_Type_Name FROM dbo.ais_cat_reestr_type Where ree
	 str_type_id = @reestr_type_id_new

    end
    return @res
END                                                                        
