#!/bin/bash
#
# Description   : This script performs the database deployment based on the list of files in the deployment directory when compared with the same list on the database
#				  It then recreates all the database objects i.e. packages, functions, triggers, views etc.
#                 Finally it compiles all invalid objects in all schemas.
# $1 = Oracle database name
# $2 = SCOTT password
# $3 = OE password
# $3 = HR password

DB=$1
DBUSER1=SCOTT
DBUSER2=OE
DBUSER3=HR
DBPWD1=$2
DBPWD2=$3
DBPWD3=$4
VFILE=VERSIONS_DATA.txt
CURRENT_TIME=$(date +'%d_%m_%y_%H_%M_%S')

#----
# Functions
#----

function showUsage() {
   echo "Syntax: $SCRIPTNAME  <database name> <password for SCOTT schema> <password for OE schema> <password for HR schema>"
}

function log() {
   #---
   # Display indented output line prefixed with date/time.
   # $1 = message
   # $2 = indent level (optional)
   #---
   printf "%s: % $((${2:-0} * 2))s%s\n" "$(date +'%d/%m/%y %H%M')" "" "$1"
}

function checkTnsPing() {
   #---
   # $1 = DB TNS e.g. ORCL
   #---
   DB=$1

   tnsping $DB >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      log "Error: DB TNS Name '$DB' does not appear to be valid." 1
      exit 1
   fi
}

function checkOracleLogin() {
   USER=$1
   PWD=$2
   DB=$3

   sqlplus -s /nolog >/dev/null 2>&1 <<-SQL
      whenever sqlerror exit 1
      connect ${USER}/${PWD}@${DB}
      exit 0
SQL
   if [ $? -ne 0 ]; then
      log "Error: Password for user '${USER}' is not valid or there is a database problem." 1
      exit 1
   fi
}

function create_logs_dir() {
   mkdir -p ./logs
   mkdir -p ./logs/bkp
   mv -f ./logs/*.log ./logs/bkp 2>/dev/null
   log "Logs directory created"
}

function privilegecheck()
{
	log "Checking privileges for $1"
sqlplus -s /nolog >>./logs/${CURRENT_TIME}_$1_$3_Privilege_Check.log 2>&1 <<-SQL
whenever sqlerror exit 1
connect $1/$2@${DB}
Set serveroutput on
DECLARE
SesCount NUMBER;
ObjCount NUMBER;
BEGIN
SELECT count(*) into SesCount FROM session_privs where privilege in( 'CREATE TABLE','CREATE SEQUENCE','CREATE PROCEDURE','CREATE TRIGGER','CREATE VIEW','CREATE TYPE');
SELECT count(*) into ObjCount FROM all_tab_privs where table_name='VERSIONS' and table_schema='SCOTT' AND privilege='INSERT';
IF NOT (SesCount >= 6 AND ObjCount>=1)
    THEN RAISE_APPLICATION_ERROR(-20123, 'Insufficient privileges to proceed. Please verify!');
END IF;
END;
/
SQL

if [ $? != 0 ]
then
 log "Error: Privilege checks failed for $1"
 exit 1
fi	
}

function predeploy() {

log "Verifying whether the DML scripts have appropriate filename"
for filename in $(ls Deployment/5_DML); do	
			if [[ $filename == *[@]* ]]
			then
			log "Error: Incorrect filename. Please address immediately. $filename" 1
			exit 1
			fi
done
log "Verified. Accurate filenames."

   log "Building the object file for deployment"
	for f in $(ls Full_Schema_DDL/)
		do
		if [[ -d Full_Schema_DDL/${f} ]]; then
			for foldername in $(ls Full_Schema_DDL/${f})
			do
			if [ $foldername == Packages ]; then
				ls Full_Schema_DDL/${f}/$foldername -1 | grep -v '^BuildAll' | grep '.pks$' | sed 's/^/@@/' > Full_Schema_DDL/${f}/$foldername/BuildAll$foldername.sql
				ls Full_Schema_DDL/${f}/$foldername -1 | grep -v '^BuildAll' | grep '.pkb$' | sed 's/^/@@/' >> Full_Schema_DDL/${f}/$foldername/BuildAll$foldername.sql
			else
				ls Full_Schema_DDL/${f}/$foldername -1 | grep -v '^BuildAll' | sed 's/^/@@/' > Full_Schema_DDL/${f}/$foldername/BuildAll$foldername.sql
			fi
			done
		fi
	done
	if [ $? -ne 0 ]; then
      log "Error: Unable to build the object file for deployment" 1
      exit 1
	  else
	  log "Built the object file for deployment"
   fi


   log "Obtaining filename list from database"
   sqlplus -s /nolog >>./logs/${CURRENT_TIME}_${DB}_Predeploy.log 2>&1 <<-SQL
      whenever sqlerror exit 1
      connect ${DBUSER1}/${DBPWD1}@${DB}
	  @./Version_Check.sql
      @./Version_Load.sql
	  exit 0
	SQL
	if [ $? -ne 0 -o ! -f $VFILE ]; then
      log "Error: Unable to obtain filename list from database" 1
      exit 1
	  else
	  log "Obtained list of filenames from database"
   fi
}

function list_invalid_objects() {
   log "Listing Invalid Objects $1 deployment for $2"
   sqlplus -s /nolog >>./logs/${CURRENT_TIME}_${DB}_$2_invalid_objects_$1_deployments.log 2>&1 <<-SQL
      whenever sqlerror exit 1
	  set heading off
	  set linesize 1000
      connect $2/$3@${DB}
      SELECT owner,
        object_type,
        object_name
		  FROM all_objects
		 WHERE status = 'INVALID';
      exit 0
	SQL
	if [ $? -ne 0 ]; then
      log "Error: Unable to obtain invalid objects list for $2" 1
      exit 1
	  else
	  log "Listed Invalid Objects $1 deployment for $2"
   fi
}

function deploy_scripts() {
	log "Deploying script changes"
	
	for f in $(ls Deployment/)
		do
		log "Entering into $f"
	if [[ -d Deployment/${f} ]]; then
#		for filename in `ls Deployment/$f | sort -V`; do
		for filename in $(ls -v Deployment/${f}); do
		if [[ ! -d Deployment/${f}/${filename} ]]; then
			countexistence=$(grep -c "$filename" VERSIONS_DATA.txt)
			if [ $countexistence != 1 ]; then
				schname=${filename%__*}
				lschname=${schname,,}
				inpname=${1,,}
			if [ $lschname == $inpname ]; then
	   log "Deploying script changes for $1"
		sqlplus -s /nolog >>./logs/${CURRENT_TIME}_${DB}_$1_script.log 2>&1 <<-SQL
		whenever sqlerror exit 1 ROLLBACK
		connect $1/$2@${DB}
		@./Deployment/$f/$filename
		insert into $DBUSER1.versions(FILENAME) values ('$filename');
		commit;
		SQL
		if [ $? -ne 0 ]; then
			log "Error: Unable to deploy script changes for $1" 1
			exit 1
		else
			log "Deployed $1 script changes"
		fi
			fi
			fi	
		fi
		done
		fi
done
}

function deploy_objects() {
   	for f in $(ls Full_Schema_DDL/)
		do
			if [ ${f^^} == $1 ]; then	
				log "Deploying $f schema object changes"
	  sqlplus -s /nolog >>./logs/${CURRENT_TIME}_${DB}_$1_object.log 2>&1 <<-SQL
      whenever sqlerror exit 1
      connect $1/$2@${DB}
	  @./Full_Schema_DDL/$1/Functions/BuildAllFunctions.sql
	  @./Full_Schema_DDL/$1/Packages/BuildAllPackages.sql
	  @./Full_Schema_DDL/$1/Procedures/BuildAllProcedures.sql
	  @./Full_Schema_DDL/$1/Views/BuildAllViews.sql
      exit 0
	SQL
	if [ $? -ne 0 ]; then
			log "Error: Unable to deploy schema object changes for $1" 1
			exit 1
		else
			log "Deployed $1 schema object changes"
	fi
			fi
		done
}

function recompile() {
   log "Compiling only invalid objects for $1"
   sqlplus -s /nolog >>./logs/${CURRENT_TIME}_${DB}_$1_recompile.log 2>&1 <<-SQL
   whenever sqlerror exit 1
   connect $1/$2@$DB
   	   @Compile_Views.sql
       EXEC DBMS_UTILITY.COMPILE_SCHEMA( schema => '$1', compile_all => FALSE);

   exit 0
SQL
if [ $? -ne 0 ]; then
			log "Error: Unable to compile only invalid objects for $1" 1
			exit 1
		else
			log "Invalid objects compiled for $1"
	fi
}

#----
# Main Stuff
#----
umask u=rwx,g=rw,o=rw

SCRIPTNAME=$(basename $0)

if [ $# -ne 4 ]; then
   showUsage
   exit 1
fi

log "$SCRIPTNAME started."

# The following checks will exit the script from within the function call if an issue is encountered
checkTnsPing $DB

checkOracleLogin $DBUSER1 $DBPWD1 $DB
checkOracleLogin $DBUSER2 $DBPWD2 $DB
checkOracleLogin $DBUSER3 $DBPWD3 $DB

create_logs_dir
# Obtains the list of all files that were last executed on the database
privilegecheck $DBUSER1 $DBPWD1
privilegecheck $DBUSER2 $DBPWD2
privilegecheck $DBUSER3 $DBPWD3
predeploy

# Deploys the release changes into the target database.
list_invalid_objects BEFORE $DBUSER1 $DBPWD1
list_invalid_objects BEFORE $DBUSER2 $DBPWD2
list_invalid_objects BEFORE $DBUSER3 $DBPWD3
deploy_scripts $DBUSER1 $DBPWD1
deploy_scripts $DBUSER2 $DBPWD2
deploy_scripts $DBUSER3 $DBPWD3
deploy_objects $DBUSER1 $DBPWD1
deploy_objects $DBUSER2 $DBPWD2
deploy_objects $DBUSER3 $DBPWD3
recompile $DBUSER1 $DBPWD1
recompile $DBUSER2 $DBPWD2
recompile $DBUSER3 $DBPWD3
list_invalid_objects AFTER $DBUSER1 $DBPWD1
list_invalid_objects AFTER $DBUSER2 $DBPWD2
list_invalid_objects AFTER $DBUSER3 $DBPWD3