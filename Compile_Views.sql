SET HEADING OFF 
set feedback off;
SPOOL INVALID_VIEWS.txt

select 'alter ' || object_type|| ' ' || object_name || ' compile;'
from user_objects 
where object_type in ('VIEW') 
and status = 'VALID' order by object_type , object_name;

SPOOL OFF
set feedback on;

@@INVALID_VIEWS.txt
