 CREATE PROCEDURE dbo.usp_ais_boss_pay_process
(
    @rep_id	            numeric(10, 0)              -- ID отчёта
    , @sprocess        varchar (255)               -- Вид обработки :
                                                             -- 'e' или  
 'exclude' или '' - Исключение отчета
    , @debug           int = 0                        -- Флаг работы в режиме от
	 ладки = 1 (0 - боевой режим)
    , @sReturnAction varchar (100)    output   -- Возвращаемое действие 
    , @Msg              varchar (100 
 0)  output   -- Сообщение процедуры
    , @iRc                int                   output  -- Код завершения процед
	 уры
 )
AS
BEGIN
    -- SYBASE-17533 Чага В.И. 20.08.2025 Исключение отчета из таблицы выплат ФУ
    -- SYBASE-17531 Чага В.И. 05.08.2025 По 
 вторное включение отчета в реестр БОСС   
    -- SUPRT-16345   Чага В.И.  18.02.2026  АИС - реестры ФЛ
    -- SUPRT-18340   Чага В.И.  09.07.2026
    declare @reestr_type_id int, @status int, @Comment varchar(1000)
        , @sResult varchar(1000),  @erro 
 r int, @RowCount int, @RC_exec int, @RC_return int, @sMessage varchar(1000)
        , @TypeProc varchar (255), @boss_register_id  numeric(10,0) , @rep_state
	  varchar(1) , @NameProcedure varchar(100) 
        
        -- Подготовка к работе.  Проверка данны 
 х.
        
        Set @iRc = 0, @sReturnAction = '', @boss_register_id = 0, @NameProcedure
	  = 'usp_ais_boss_pay_process'
        
        Select @reestr_type_id =  dbo.fn_reestr_type_id (@rep_id, 1 )    -- , 1 
	 - означает, что в функции включена ПОЛНАЯ пр 
 оверка 
        if @reestr_type_id Not in ( 1, 6 ) 
        Begin
            Set @Msg = 'Не обрабатываемый тип реестра ( ' + Convert( varchar(10)
	 , @reestr_type_id ) + ' )'
            Set @iRc = -1
                                                         
                                                     if @debug = 1 Select @NameP
	 rocedure, 'Line 41', @Msg as '@Msg', @iRc as '@iRc'
            return @iRc
        End
        
        If isNull(@sprocess,'') = '' Set @TypeProc = 'e'
        Else Set  @Typ 
 eProc = Lower(Left(@sprocess, 1))
            
        if @TypeProc = 'е' Set @TypeProc = 'e'
            
        If @TypeProc Not in ( 'e', 'i' )
        Begin
            Set @Msg = 'Вид обработки неизвестен ( ' + isNull(@sprocess,'') + ' 
	 )'
           
   Set @iRc = -1
                                                                                
	                         if @debug = 1 Select @NameProcedure, 'Line 54',
	  @Msg as '@Msg', @iRc as '@iRc'
            return @iRc
        End
            
        
  if @TypeProc = 'e'
        Begin
            if ( Select isNull(boss_req,0) From ais_report Where rep_id = @rep_i
	 d ) = 0 
                Begin
                    Set @Msg =  "Отчет не включен в реестр на выплату"
                    Set @iRc = -1 
     
                                                                                
	                                  if @debug = 1 Select @NameProcedure, '
	 Line 64', @Msg as '@Msg', @iRc as '@iRc'
                    return @iRc
                End
        End  
 
        
        if @TypeProc = 'i'
        Begin
            if ( Select isNull(boss_req,0) From ais_report Where rep_id = @rep_i
	 d ) = 1 
            Begin
                Set @Msg =  "Отчет уже был включен в реестр на выплату"
                Set @iRc  
 = -1 
                                                                                
	                                 if @debug = 1 Select @NameProcedure, 'L
	 ine 75', @Msg as '@Msg', @iRc as '@iRc'
                return @iRc
            End
        End 
  
                                                    -- Достаточно одна любая зап
	 ись 
        Select Top 1 @status = state, @Comment = comment, @boss_register_id = is
	 Null( boss_register_id, 0 ) 
            From dbo.ais_boss_payments 
            Where rep_ 
 id = @rep_id 
            Order by ID desc 
            
        Set @RowCount = @@rowcount, @error = @@ERROR
                                                                                
	                                         if @debug = 1 Select @Nam 
 eProcedure, 'Line 86', @RowCount as '@RowCount', @error as '@error', @status as
	  '@status',  @boss_register_id as '@boss_register_id',  @Comment as '@C
	 omment'              
        if @RowCount = 0 
        Begin
            if Exists( Select * From dbo.ai 
 s_boss_payments_audit Where rep_id = @rep_id ) and @TypeProc = 'i'
                Begin
                    Set @Comment = '', @boss_register_id = Null, @status = -2
                End
            Else
                Begin
                if   @TypePro 
 c = 'i'
                Begin
                    execute @RC_exec = dbo.usp_ins_ais_boss_payments @rep_id = @
	 rep_id , @Message = @sMessage   Output, @Rc = @RC_return   Output, @deb
	 ug = @debug
                    
                                          
                                                                        if @debu
	 g = 1 Select @NameProcedure, @TypeProc as '@TypeProc', 'Line 99', @sMes
	 sage as '@sMessage', @RC_exec as '@RC_exec', @RC_return as '@RC_return'
	 
                    if @RC_return 
  = -1 or @RC_exec = -1
                    Begin
                        Set @Msg = @Msg + ', @sMessage = ' + isNull( @sMessage, 
	 'Null' ) + ', @RC_return = ' + isNull( Convert( varchar(20), @RC_return
	 ),'Null')  + ', @RC_exec = ' + isNull( Convert( varchar 
 (20), @RC_exec), 'Null'  )
                        Set @iRc = -1
                                                                                
	                             if @debug = 1 Select @NameProcedure, @TypeP
	 roc as '@TypeProc', 'Line 104', @Msg as 
  '@Msg', @iRc as '@iRc'
                      
                        return @iRc
                    End
                    Set @sReturnAction = 'boss_req = 1;state=0'                 
	                                                                      
              
                                                                                
	                                 if @debug = 1 Select @NameProcedure, 'L
	 ine 109  execute dbo.usp_ins_ais_boss_payments  @rep_id = ' + Convert( 
	  varchar(50),  @rep 
 _id ), @Msg as '@Msg', @iRc as '@iRc'
                    return @RC_return
                End
                Set @Msg = 'Записей в ais_boss_payments не обнаружено ( rep_id =
	  ' + Convert( varchar(10), @rep_id ) + ' )'
                Set @iRc = -1
      
                                                                                
	                                 if @debug = 1 Select @NameProcedure, 'L
	 ine 113', @Msg as '@Msg', @iRc as '@iRc'
                return @iRc
            End
        End 
        
  
        Select @rep_state = rep_state from dbo.ais_report where rep_id = @rep_id
	  
            
        if @rep_state <> 'A'
        Begin
            Set @Msg = 'Отчет должен быть в статусе "Подтвержден"'
            Set @iRc = -1
                       
                                                                                
	    if @debug = 1 Select @NameProcedure, @TypeProc as '@TypeProc',  'Lin
	 e 124', @Msg as '@Msg', @iRc as '@iRc'
            return @iRc
        End
            
        -- Вид об 
 работки 'exclude'  - Исключение отчета
        if   @TypeProc in ( 'e' )   
        Begin
 
            Select @Msg = 
                Case @status
                    When  0 then
                                    Case @boss_register_id 
               
                           When 0 then 'Отчет исключен из реестра выплат'
                                        Else 'Ошибка обработки. Документ взят в 
	 обработку ( boss_register_id = ' + Convert(  varchar(50),  @boss_regist
	 er_id ) + ' ), но статус = 0 '
 
                                     End
                    When  1 then 'Отчет отправлен на выплату'
                    When  2 then 'Отчет отправлен на выплату'
                    When -1 then 'Отчет исключен из реестра выплат. ' + isNull( 
	 'По отчету  
 есть ошибка ' + @Comment, ''  )
                    When -2 then 'Отчет не включен в реестр на выплату'
                    When -3 then 'Отчет не включен в реестр на выплату'
                    Else 'Статус записи "' + isNull( Cast(@status as varchar(25 
 5)), 'Null' ) + '" не определён для обработки '
                End
                , @iRc = 
                Case @status
                    When  0 then 
                                    Case @boss_register_id      
                                  
        When 0 then 0
                                        Else -1                     -- Ошибка об
	 работки на стороне БОСС.  Документ взят в обработку, но статус 0 не изм
	 енен.
                                    End
                    When -1 then 0
   
                   Else -1
                End

                                                                                
	                         if @debug = 1 Select @NameProcedure, @TypeProc 
	 as '@TypeProc', 'Line 157', @status as '@status', @Msg as 
  '@Msg', @iRc as '@iRc'
            if @status Not in ( 0, -1 ) return @iRc
         
            Update dbo.ais_boss_payments
                Set state = Case @status 
                                    When 0 Then -3        -- Меняем статус запис
	 и c 0  
 на "-3" - неактивная запись
                                    Else -2                     -- Меняем статус
	  записи c "-1" на "-2"
                                End
            From dbo.ais_boss_payments
            Where rep_id = @rep_id
            
  
            set @RowCount = @@rowcount, @error = @@ERROR
                                                                                
	                         if @debug = 1 Select @NameProcedure, @TypeProc 
	 as '@TypeProc', 'Line 169', @RowCount as '@RowCo 
 unt', @error as '@error'
            
            if @error <> 0 begin
                Set @Msg = @Msg + " Ошибка Update ais_boss_payments ( ERROR " + 
	 convert(varchar(5), @error) + ' ) '  
                Set @iRc = -1
                                     
                                                                     if @debug =
	  1 Select @NameProcedure, @TypeProc as '@TypeProc', 'Line 174', @status
	  as '@status', @Msg as '@Msg', @iRc as '@iRc'
                return @iRc
            end
            
   
           -- В поле ais_report.boss_req убираем блокировку
            Update dbo.ais_report
                Set boss_req = 0
            From dbo.ais_report
            Where rep_id = @rep_id  
            
            set @RowCount = @@rowcount, @error  
 = @@ERROR
                                                                                
	                         if @debug = 1 Select @NameProcedure, @TypeProc 
	 as '@TypeProc', 'Line 186', @RowCount as '@RowCount', @error as '@error
	 '
            
         
     if @error <> 0 begin
                Set @Msg = @Msg + " Ошибка Update ais_report ( ERROR " + convert
	 (varchar(5), @error) + ' ) '  
                Set @iRc = -1
                                                                                
	           
                if @debug = 1 Select @NameProcedure, @TypeProc as '@TypeProc', '
	 Line 190', @status as '@status', @Msg as '@Msg', @iRc as '@iRc'
                return @iRc
            end
            
            Set @sReturnAction = 'boss_req = 0;state='  
 + isNull(Convert( varchar(50), Case @status 
                                                                                
	                                     When 0 Then -3        -- Меняем ста
	 тус записи c 0 на "-3" - неактивная запись
                 
                                                                                
	                      Else -2                     -- Меняем статус запис
	 и c "-1" на "-2"
                                                                                
	          
                         End ),'Null')
        End
             
        -- Вид обработки 'include'  - Повторное включение отчета в реестр БОСС
        if   @TypeProc in ( 'i' )   
        Begin
            Select @Msg = 
                Case @status
      
                When  0 then 'Отчет уже включен в реестр на выплату. Необходимо 
	 исключить отчет.'
                    When  1 then 'Отчет передан в БОСС на выплату'
                    When  2 then 'Отчет передан в БОСС на выплату'
                    When 
  -1 then 'Необходимо исключить отчет из реестра выплат'
                    When -2 then 'Отчет включен в реестр на выплату'
                    When -3 then 'Отчет включен в реестр на выплату'
                    Else 'Статус записи "' + isNull( Cast(@st 
 atus as varchar(255)), 'Null' ) + '" не определён для обработки '
                End
                , @iRc = 
                Case @status
                    When -2 then 0
                    When -3 then 0
                    Else -1
                 
 End
                                                                                
	                         if @debug = 1 Select @NameProcedure, @TypeProc 
	 as '@TypeProc', 'Line 219', @status as '@status', @Msg as '@Msg', @iRc 
	 as '@iRc'
            if @sta 
 tus Not in ( -2, -3 ) return @iRc
                           
            execute @RC_exec = dbo.usp_ins_ais_boss_payments @rep_id = @rep_id ,
	  @Message = @sMessage   Output, @Rc = @RC_return   Output, @debug = @de
	 bug
            
                          
                                                                                
	 if @debug = 1 Select @NameProcedure, @TypeProc as '@TypeProc', 'Line 22
	 4', @sMessage as '@sMessage', @RC_exec as '@RC_exec', @RC_return as '@R
	 C_return'
            
            
  if @RC_return = -1 or @RC_exec = -1
            Begin
                Set @Msg = @Msg + ', @sMessage = ' + isNull( @sMessage, 'Null' )
	  + ', @RC_return = ' + isNull( Convert( varchar(20), @RC_return),'Null'
	 )  + ', @RC_exec = ' + isNull( Convert( varchar(2 
 0), @RC_exec), 'Null'  )
                Set @iRc = -1
                                                                                
	                     if @debug = 1 Select @NameProcedure, @TypeProc as '
	 @TypeProc', 'Line 230', @Msg as '@Msg', @iRc as ' 
 @iRc'
              
                return @iRc
            End
                
            
            Set @sReturnAction = 'boss_req = 1;state=0'
                                                                                
	                          
 if @debug = 1 Select @NameProcedure, @TypeProc as '@TypeProc', 'Line 237', @sRe
	 turnAction as '@sReturnAction', @Msg as '@Msg', @iRc as '@iRc'
        End               
        return @iRc
END                                                                
