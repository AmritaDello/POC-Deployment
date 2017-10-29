spool version_check_status.txt
SET SERVEROUTPUT ON
declare
nCount NUMBER;
v_sql LONG;

begin
SELECT count(*) into nCount FROM user_tables where table_name = 'VERSIONS';
IF(nCount <= 0)
THEN
v_sql:='
create table VERSIONS
(
FILENAME VARCHAR2(1000),
LOAD_DATE DATE DEFAULT SYSDATE
)';
execute immediate v_sql;
ELSE
DBMS_OUTPUT.PUT_LINE('VERSIONS Table exists');
END IF;
end;
/
spool off