#!/bin/bash

#Function declaration
BACKUP_F_D()
{

	SRC=$2
	PRACTICE_DIR="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH"
	RUNNER=$3
	BACKUP_DIR=${PRACTICE_DIR}/backup/${RUNNER}/$TS

   echo "Creating backup directory ${BACKUP_DIR}..."
   mkdir -p ${BACKUP_DIR}
   mkdir -p ${BACKUP_DIR}/backup_dir
   mkdir -p ${BACKUP_DIR}/backup_file

   if (($? != 0 ))
   then
      echo "Failed to create directory ${BACKUP_DIR}"
   else
      echo "Successfully created directory ${BACKUP_DIR}"
   fi
   echo

	#Copy logic
   if [[ -d ${SRC} ]]
   then
      echo "${SRC} is a directory."
      echo "Copying the DIRECTORY to specified backup location ${BACKUP_DIR}..."
      cp -r ${SRC} "${BACKUP_DIR}/backup_dir"

      if (( $? != 0 ))
      then
         echo "Directory copy FAILED!"
      else
         echo "Directory copy SUCCESSFUL!"
      fi

   elif [[ -f ${SRC} ]]
   then
      echo "${SRC} is a file."
      echo "Copying the FILE to specified backup location ${BACKUP_DIR}..."
      cp ${SRC} "${BACKUP_DIR}/backup_file"

      if (( $? != 0 ))
      then
         echo "File copy FAILED!"
      else
         echo "File copy SUCCESSFUL!"
      fi

   else
      echo "${SRC} does not exist. Please re-run the script."
      exit 1
   fi
   echo

	#validate

	echo "Showing ${SRC} in specific backup directory:"
	if [[ -f ${SRC} ]] 
	then
		echo "${BACKUP_DIR}/backup_dir :::"
		ls -ltr ${BACKUP_DIR}/backup_file
	else
		echo "${BACKUP_DIR}/backup_dir :::"
		ls -ltr ${BACKUP_DIR}/backup_dir
	fi

	echo "Showing timestamped backup: "
	ls -ltr ${PRACTICE_DIR}/backup/${RUNNER}
}

DATABASE_BACKUP() 
{
   #-database status
   DBCHECKLOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/dbcheck.log"

   #-settiing database environment variable dynamically
	ENV_FILE="/home/oracle/scripts/oracle_env_APEXDB.sh"
	if [[ ! -f ${ENV_FILE} ]] 
	then
		echo "Environment file not found. Stopping."
		exit 1
	fi
   source ${ENV_FILE}

   BACKUP_DIR="/backup/AWSJAN26/DATAPUMP/APEXDB"

   PARFILE="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/backup_ENOCH.par"
	EXPDP_LOG="expdp_APEXDB_ENOCH.log"
	EXPDP_LOG_PATH=${BACKUP_DIR}/${EXPDP_LOG}
	DUMP_FILE="expdp_APEXDB_ENOCH.dmp"

	#-boolean check
	if ( ps -ef | grep pmon | grep APEXDB )
	then
		echo "The APEXDB database instance is up and running!"
	else
		echo "THE APEXDB DATABASE IS DOWN!"
		exit 1
	fi
	echo

	#-get database open status
	sqlplus ${DB_USER}/${DB_PASS} <<EOF > ${DBCHECKLOG}
set echo on feedback on term on pagesize 0
select status from v\$instance;
EOF

	#-checking file for open status
	if ( grep "OPEN" ${DBCHECKLOG} )
	then
		echo "The database is open for backup."
	else
		echo "The database is not open. Backup cannot occur."
		exit 1
	fi
	echo

	#-creating backup config file
	echo "userid=${DB_USER}" >> ${PARFILE}
	echo "schemas=STACK_TEMP" >> ${PARFILE}
	echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
	echo "logfile=${EXPDP_LOG}" >> ${PARFILE}
	echo "directory=DATA_PUMP_DIR" >> ${PARFILE}
	
	expdp parfile=${PARFILE}
	if [[ $? != 0 ]] 
	then
		echo "Error: expdp failed."
		exit 1
	fi
	echo

	#-check log file for success
	if ( grep "successfully completed" ${EXPDP_LOG_PATH} )
	then
		echo "Backup completed successfully."
	else
		echo "Backup failed. /home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/dbcheck.logCheck log: ${EXPDP_LOG_PATH}"
		exit 1
	fi
	echo

	#-confirm database backup
	echo "Confirming database backup..."
	ls -ltr ${BACKUP_DIR}
}


#variable declarations
SCRIPT_FUNC=$1
TS=$(date "+%m-%d-%Y_%H-%M-%S")

#Case statements: function declaration
case ${SCRIPT_FUNC} in
backup_f_d)
	#utilization check
	echo "The number of command-line arguments in this script is: $#"
	if (( $# != 3 ))
	then
  		echo "You did not run this script correctly. Please run like below:"
  		echo "UTILITY: <SCRIPT_NAME> <SRC> <RUNNER>"
  		echo "e.g script_name home/oracle/file.txt backup"
  		echo

		read -p "Do you need help running this script? :" ANSWER
			if [[ ${ANSWER} == 'y' ]]
			then
				echo "You have opted for help..."
				read -p "Enter the script name: " SCRIPT_FUNC
				read -p "Enter the source file: " SRC
				read -p "Enter the runner name: " RUNNER
			else
				exit 1
			fi
	fi
	echo

	SRC=$3
	RUNNER=$2
	
	#Call function BACKUP_F_D
  	echo "Calling ${SCRIPT_FUNC} function... "
  	BACKUP_F_D "backup_f_d" ${SRC} ${RUNNER}
	;;
database_backup)
	#utilization check
   echo "The number of command-line arguments in this script is: $#"
   if (( $# != 1 ))
   then
      echo "You did not run this script correctly. Please run like below:"
      echo "UTILITY: <SCRIPT_NAME> <DBCHECKLOG> <RUNNER>"
      echo "e.g database_backup ./dbcheck.log enoch"
      echo

      read -p "Do you need help running this script? :" ANSWER
	      if [[ ${ANSWER} == 'y' ]]
         then
            echo "You have opted for help..."
            read -p "Enter the script name: " SCRIPT_FUNC
			else
				exit 1
			fi
   fi
	echo
		
   #Call function BACKUP_F_D
   echo "Calling ${SCRIPT_FUNC} function... "
	DATABASE_BACKUP "database_backup"
	;;
database_import)
	;;
secure_copy)
	;;
data_migration)
	;;
AWS)
	;;	
*)
	echo "${SCRIPT_FUNC} was not found in this code."
	exit 1
	;;
esac

