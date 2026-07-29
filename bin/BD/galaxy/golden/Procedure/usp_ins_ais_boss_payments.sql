 CREATE PROCEDURE dbo.usp_ins_ais_boss_payments 
(  @rep_id            numeric(10,0)
    , @Message      varchar( 1000 )  Output
    , @Rc               integer             Output
    , @debug        int = 0
)
AS
BEGIN
-- SYBASE-17531 Чага В.И.  05.08.2025 
  . Повторное включение отчета в реестр БОСС
-- SYBASE-17477 Чага В.И.  18.07.2025 . Создать ХП для вставки данных в таблицу 
	 БОСС
-- SYBASE-17782 Чага В.И.  12.09.2025 . Отображение информации из таблицы БОСС в
	  окно "Отчеты"
Declare @status int, @iError in 
 t, @iRowCount int, @NameProcedure varchar(100), @bNew Bit, @sMsg varchar(1000) 
	 

    Set    @bNew = Case                                    -- SYBASE-17782   Пар
	 аметр определяет - это новый документ или документ надо обновить и запи
	 сать заново с новыми да 
 нными 
                                    When Exists( Select * From dbo.ais_boss_paym
	 ents Where rep_id = @rep_id   )
                                        Then 0
                                    Else 1
                                End
           
   , @NameProcedure = 'usp_ins_ais_boss_payments'
            , @sMsg = ''
             
    if @bNew = 0 Select @status = state  From dbo.ais_boss_payments  Where rep_i
	 d = @rep_id                 -- Документ не новый старые данные будут уд
	 алены и будет со 
 зданы новые данные по указаному rep_id
                
                
    if  @bNew = 0 and isNull(@status, 99 ) in ( 0, 1, 2 )                       
	                                                  -- Обновление данных в
	 озможно только при отрицательно 
 м статусе существующей записи с   указаным rep_id
        Begin
            Set @Message = 'В таблице ais_boss_payments уже ЕСТЬ запись с rep_id
	   = ' + isNull( Cast( @rep_id as varchar(50) ) , 'Null' ) + ', и статус
	 ом = ' + isNull( Cast( @status as varcha 
 r(50) ) , 'Null' ) 
            Set @Rc = -1
                                                                                
	                                 if @debug = 1 Select @NameProcedure, 'L
	 ine 35', @Message as '@Message', @Rc as '@Rc'               
                                       -- Режим отладки 
            Return -1
        End

     select  r.rep_id                    as rep_id                  -- ID отчета
	              
           , r.ag_id                       as ag_id                    
 -- ID договора
           , r.cash_flow_code         as cfc                      -- Cash flow c
	 ode
           , c.upd_com_sum          as upd_com_sum      -- Сумма отчета
            , c.system                   as system              -- Для связи с o
	 ss_a 
 greement и с ais_policy
            , c.entity_id                  as entity_id             -- Для связи
	  с ais_entity_data
            , c.insure_kind               as insure_kind         -- Для связи с 
	 ais_cat_insure_kind
            , c.ais_policy_id    
           as ais_policy_id        -- -- Для связи с ais_policy
            , r.department_code      as department_code
             , r.external_number      as external_number     -- Номер отчета
            , r.external_date          as external_date     
      -- Дата отчета
            , r.rep_state               as rep_state
        into #temp_1
    from        dbo.ais_report            r   
        JOIN    dbo.ais_commission    c      ON        c.rep_id = r.rep_id 
    Where  r.rep_id = @rep_id 
        
  and  r.rep_com_type = 'C'
        and  r.rep_type = 'A' 
        and  r.flag_official in ( 0, 3 )    -- Тип КВ 
        
    Select @iError = @@error, @iRowCount = @@rowcount        
                                                
                       
                                                                                
	            if @debug = 1 begin                                         
	             -- Режим отладки 
                                                                            
                                          select @NameProcedure, 'Line 58 ',@rep
	 _id as '@rep_id' 
                                                                                
	                                     Select @NameProcedure, 'ais_report'
	 , rep_c 
 om_type as 'rep_com_type', rep_type as 'rep_type', flag_official as 'flag_offic
	 ial', ais_report.rep_id, ais_report.create_date, ais_report.date_from, 
	 ais_report.date_to, ais_report.rep_type, ais_report.sale_id, ais_report
	 .agent_id, ais_report.rep_number,  
 ais_report.rep_state, ais_report.ag_id, ais_report.rep_com_type, ais_report.dep
	 artment_code, ais_report.cash_flow_code, ais_report.currency, ais_repor
	 t.rep_sum, ais_report.period_id, ais_report.req_id, ais_report.system, 
	 ais_report.our_subj_id, ais_report 
 .com_pay_type_id, ais_report.link_rep_id, ais_report.flag_official, ais_report.
	 export_status, ais_report.reestr_id, ais_report.b2b, ais_report.externa
	 l_number, ais_report.entity_id, ais_report.basis_ag_id, ais_report.cdp_
	 key, ais_report.id_dover, ais_repo 
 rt.send_state, ais_report.rep_full_name, ais_report.send_path, ais_report.exter
	 nal_date, ais_report.last_update, ais_report.sign_elec, ais_report.cdp_
	 filial_id, ais_report.partner_sign, ais_report.doc_issue_place, ais_rep
	 ort.prior_rep_id, ais_report.dover 
 _type, ais_report.legate_id, ais_report.id_edover, ais_report.partner_dover_typ
	 e, ais_report.change_confirm_state_date, ais_report.confirm_date 
                                                                                
	                                
               from dbo.ais_report where rep_id = @rep_id
                                                                                
	                                     if ( Select Count(1) from #temp_1 )
	  < 1 
                                          
                                                                                
	 Begin
                                                                                
	                                             Select @NameProcedure,'Табл
	 ица #temp_1 пуста.' 
 
                                                                                
	                                             if ( Select Count(1) from d
	 bo.ais_report Where rep_id = @rep_id ) < 1
                                                             
                                                                     Select @Nam
	 eProcedure,'В таблице ais_report нет записи с rep_id = ' + isNull( Cast
	 ( @rep_id as varchar(50) ) , 'Null' )
                                                                    
                                                          Else
                                                                                
	                                                 Begin
                                                            
                                                                          if ( S
	 elect Count(1) 
                                                                                
	                                                             from       
	  dbo.repo 
 rt_reestr   rr  
                                                                                
	                                                                 JOIN   
	  dbo.ais_report       r      ON r.reestr_id = rr.reestr_id and r.rep_id
	  = @rep_id
      
                                                                                
	                                                         Where rep_id = 
	 @rep_id ) < 1
                                                                                
	             
                                              Select @NameProcedure,'В таблице r
	 eport_reestr нет записи с reestr_id = ' + isNull( Cast( r.reestr_id as 
	 varchar(50) ) , 'Null' )
                                                                                
	  
                                                             From dbo.ais_report
	        r  Where r.rep_id = @rep_id
                                                                                
	                                                 End
          
                                                                                
	                                 End
                                                                                
	                                     Else/* Adaptive Server h 
 as expanded all '*' elements in the following statement */ 
                                                                                
	                                         Select @NameProcedure,'#temp_1'
	 , #temp_1.rep_id, #temp_1.ag_id, #temp_1.cfc 
 , #temp_1.upd_com_sum, #temp_1.system, #temp_1.entity_id, #temp_1.insure_kind, 
	 #temp_1.ais_policy_id, #temp_1.department_code, #temp_1.external_number
	 , #temp_1.external_date, #temp_1.rep_state from #temp_1
                                                  
                                                                end        


    
    if @iError <> 0 or ( Select Count(1) from #temp_1 ) < 1
        Begin
                                                                                
	                     
                  if @debug = 1  Select @NameProcedure, 'Line 85', '@@rowcount =
	  ', @iRowCount, '@@error = ', @iError                                  
	                   -- Режим отладки 
            if @@error <> 0
                Set @Message = 'Ошибка за 
 писи ( @@error = ' + isNull( Cast( @@error as varchar(50) ) , 'Null' ) + ' ) во
	  временную таблицу из ais_report записи с rep_id  = ' + isNull( Cast( @
	 rep_id as varchar(50) ) , 'Null' )
            Else
                Set @Message = 
                    C 
 ase
                        When ( Select Count(1) from ais_report Where rep_id = @r
	 ep_id ) < 1
                            Then 'В таблице ais_report нет записи с rep_id = ' +
	  isNull( Cast( @rep_id as varchar(50) ) , 'Null' )
                        When 
  ( Select isNull( Cast( reestr_id as varchar(50) ) , 'Null' ) from ais_report W
	 here rep_id = @rep_id ) = 'Null'
                            Then 'В таблице ais_report для записи с rep_id = ' +
	  isNull( Cast( @rep_id as varchar(50) ) , 'Null' ) + '  ID реес 
 тра ФУ пуст ( reestr_id = Null )'
                        When ( Select Count(1) from report_reestr  rr JOIN ais_r
	 eport  r  ON r.reestr_id = rr.reestr_id and  r.rep_id = @rep_id ) < 1 
                            Then 'В таблице ais_report для записи для  
 с rep_id = ' + isNull( Cast( @rep_id as varchar(50) ) , 'Null' ) + ' не существ
	 ует ID реестра ФУ в report_reestr. '
                       When ( Select Count(1) from ais_commission Where rep_id =
	  @rep_id ) < 1
                            Then 'В таблице  
 ais_commission нет записей с rep_id = ' + isNull( Cast( @rep_id as varchar(50) 
	 ) , 'Null' )
                        Else
                            'Нет записей удовлетворяющих требованиям'
                    End
            Set @Rc = -2
                
                                                                                
	                   if @debug = 1 Select @NameProcedure, 'Line 102', @Mes
	 sage as '@Message', @Rc as '@Rc'                                       
	              -- Режим отладки 
    
          Return -2
         End 
          
 
 
         Select rep_id = t.rep_id
                , ag_id = ag.ag_id 
                , cfc = t.cfc 
                , upd_com_sum = t.upd_com_sum
                , recep_name = substring(LTRIM(IsNull(ra.rec 
 ep_name, ora.reception_area_name)), 1, 8) 
                , department_code = IsNull(ik.department_code, t.department_code
	 )   
                , branch_code = convert ( Char(10), cbc.branch_code)  /*SYBASE-8
	 41 - стало*/
                , tab_number = ltr 
 im(ag.tab_number) 
                , subj_id = e.subj_id
                , external_number
                , external_date
                , rep_state
            into #temp_2                
        From        #temp_1                              t
     
         LEFT JOIN     dbo.oss_agreement              pol    ON (t.ais_policy_id
	  = pol.oss_policy_id and t.system = 'AVT')   
            LEFT JOIN     dbo.oss_reception_area         ora   ON (ora.reception
	 _area_id = pol.reception_area_id)
            LEFT 
  JOIN     dbo.ais_entity_data              e      ON (t.entity_id = e.entity_id
	  and e.date_to is null)
            LEFT JOIN     mis..cb_branch_code      cbc   ON cbc.our_subj_id = e.
	 company_id  
            LEFT JOIN     dbo.ais_cat_insure_kind         i 
 k      ON (ik.insure_kind_code = t.insure_kind)
            LEFT JOIN     dbo.ais_entity_basis             ag     ON (t.ag_id = 
	 ag.mis_ag_id)
            LEFT JOIN     dbo.ais_policy                     p       ON (t.ais_p
	 olicy_id = p.ais_policy_id  and t 
 .system <> 'AVT')
            LEFT JOIN     mis.dbo.reception_area   ra      ON (ra.recep_id = p.r
	 ecep_id)
            
                                                                                
	                                 if @debug = 1 begin     
                                                 -- Режим отладки 
                                                                                
	                                    Select @NameProcedure, 'Line 130 ','
	 #temp_2', #temp_2.rep_id, #temp_2.ag_i 
 d, #temp_2.cfc, #temp_2.upd_com_sum, #temp_2.recep_name, #temp_2.department_cod
	 e, #temp_2.branch_code, #temp_2.tab_number, #temp_2.subj_id, #temp_2.ex
	 ternal_number, #temp_2.external_date, #temp_2.rep_state from #temp_2
                                     
                                                                             end
	                
         Select  rep_id
                , rep_sum = sum(upd_com_sum)
                , subj_id, tab_number, recep_name, department_code, branch_code
            
      , external_number, external_date, rep_state, ag_id, cfc
            into #temp_3                
        From #temp_2 
        group by 
                  rep_id
                  , subj_id, tab_number, recep_name, department_code, branch_cod
	 e
       
             , external_number, external_date, rep_state, ag_id, cfc

                                                                                
	                                 if @debug = 1 begin                    
	                                 --  
 Режим отладки 
                                                                                
	                                     Select @NameProcedure,'Line 144 ','
	 #temp_3', #temp_3.rep_id, #temp_3.rep_sum, #temp_3.subj_id, #temp_3.tab
	 _number, #temp_3.r 
 ecep_name, #temp_3.department_code, #temp_3.branch_code, #temp_3.external_numbe
	 r, #temp_3.external_date, #temp_3.rep_state, #temp_3.ag_id, #temp_3.cfc
	  from #temp_3
                                                                                
	             
                      end  
 
        BEGIN TRAN    
                                                                                
	                        
            if  @bNew = 0                                                       
	                     
                      -- SYBASE-17782   этот документ надо обновить и записать з
	 аново с новыми данными                                                 
	                       
                Begin
                    Update dbo.ais_report                    
                         
                        Set boss_req  = 0
                            from    dbo.ais_report  r 
                                Where  r.rep_id = @rep_id   
                                
                    Select @iError = @@ 
 error, @iRowCount = @@rowcount   
                    
                    if @iError <> 0 
                        Begin 
                            Select @sMsg = m.description FROM master.dbo.sysmess
	 ages  m where m.error = @iError
                     
         Select @Message = 'Ошибка обновления данных. Set boss_req  = 0.  ' + is
	 Null( @sMsg, '') + ' ' + @Message
                                                                                
	                                                         if @de 
 bug = 1 Select @NameProcedure, 'Line 173', 'ROLLBACK TRAN', @Message as '@Messa
	 ge', @Rc as '@Rc' ,'@iError = ', @iError, '@iRowCount = ', @iRowCount -
	 - Режим отладки 
                            RAISERROR 99999 'Ошибка обновления данных. Set boss_
	 req  = 0 
 .  ' 
                            ROLLBACK TRAN
                            RETURN -1                        
                        End
                               
                    Delete   From dbo.ais_boss_payments Where rep_id = @rep_id  
	       
               -- Перед добавлениие новой информации снимаем отметку boss_req  =
	  1   
                                                                                
	                                               -- Есди добавление пройдё
	 т без ошибок, то тр 
 иггер ti_ais_boss_payments  вернёт обратно boss_req  = 1 
                    Select @iError = @@error, @iRowCount = @@rowcount   
                    
                    if @iError <> 0 
                        Begin 
                            Select  
 @sMsg = m.description FROM master.dbo.sysmessages  m where m.error = @iError
                            Select @Message = 'Ошибка удаления данных из dbo.ais
	 _boss_payments.' + isNull( @sMsg, '') + ' ' + @Message
                                            
                                                                                
	              if @debug = 1 Select @NameProcedure, 'Line 187', 'ROLLBACK
	  TRAN', @Message as '@Message', @Rc as '@Rc' ,'@iError = ', @iError, '@
	 iRowCount = ', @iRowCount -- Режим 
  отладки 
                            RAISERROR 99999 'Ошибка удаления данных из dbo.ais_b
	 oss_payments.' 
                            ROLLBACK TRAN
                            RETURN -1                        
                        End
                  
    
                End
            
            if ( Select Count(1) From #temp_3 Where  lTrim(isNull(tab_number, ''
	 )) = ''   or   tab_number is Null  )  > 0
                Begin                   -- Проверка - tab_number не может быть п
	 устым 
          
                    Set @Message = 'Ошибка данных. Поле tab_number не может быть
	  пустым.' --, @Rc = -1   
                                                                                
	                                                        if @debug = 1 S 
 elect @NameProcedure, 'Line 199', 'COMMIT TRAN', @Message as '@Message', @Rc as
	  '@Rc' ,'@iError = ', @iError, '@iRowCount = ', @iRowCount -- Режим отл
	 адки 
                            RAISERROR 99999 'Ошибка данных. Поле tab_number не м
	 ожет быть пустым.'  
 
                            COMMIT TRAN
                            RETURN -1                        
                End                                                        
                                                                             
                                         
            Insert into dbo.ais_boss_payments ( subj_id 
                , tab_number
                , rep_id
                , external_number, external_date
                , rep_sum
                , rep_state
 
                 , ag_id, cfc, recep_name, department_code, branch_code) 
            Select subj_id 
                , tab_number
                , rep_id
                , external_number, external_date
                , rep_sum
                , rep_sta 
 te
                , ag_id, cfc, recep_name, department_code, branch_code
            From #temp_3  
        
            Select @iError = @@error, @iRowCount = @@rowcount   
            
            if @iError <> 0 or @iRowCount < 1
                Begin 
  
                    Select @sMsg = m.description FROM master.dbo.sysmessages  m 
	 where m.error = @iError
                    Select @Message = 'Ошибка добавления данных в dbo.ais_boss_p
	 ayments.' + isNull( @sMsg, '') + ' ' + @Message
                    i 
 f @iRowCount < 1 Select  @sMsg = 'Нет данных для ввода. ' + isNull( @sMsg, '') 
	 
                                                                                
	                                                if @debug = 1 Select @Na
	 meProcedure, 'Line 219', 
  'ROLLBACK TRAN', @Message as '@Message', @Rc as '@Rc' ,'@iError = ', @iError, 
	 '@iRowCount = ', @iRowCount -- Режим отладки 
                    RAISERROR 99999 'Ошибка добавления данных в dbo.ais_boss_pay
	 ments.' 
                    ROLLBACK TRAN
        
              RETURN -1                        
                End
              
            Set @Rc = 0                                                         
	                                                        if @debug = 1 Se
	 lect @NameProcedure, ' 
 Line 224', 'Set @Rc = 0', 'COMMIT TRAN', @Message as '@Message', @Rc as '@Rc'  
	                                                   -- Режим отладки 
        COMMIT TRAN
    Return 0
    
 END                                                                   
