#!/bin/bash

#Function declaration
SCP()
{
	#Check if server is active/discoverable
	if ( ! nslookup ${DST_SERV} )
	then
		echo "Server ${DST_SERV} is not active!"
		exit 1
	fi

	#Secure copy command
	scp -i ${PEM_KEY} ${SRC} ${DST_USER}@${DST_SERV}:${DST_PATH}
	if (( $? != 0 ))
	then
		echo "Secure copy FAILED!"
	else
		echo "Secure copy SUCCESSFUL!"
	fi	
}

BACKUP_F_D()
{
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

   #-settiing database environment variable dynamically
	if [[ ! -f ${ENV_FILE} ]] 
	then
		echo "Environment file not found. Stopping."
		exit 1
	fi
   source ${ENV_FILE}

   PARFILE="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/backup_${RUNNER}.par"
	EXPDP_LOG="${SCHEMA}_backup_${TS}.log"
	EXPDP_LOG_PATH=${DATA_DUMP}/${EXPDP_LOG}
	DUMP_FILE="${SCHEMA}_backup_${TS}.dmp"

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
	echo "userid=${DB_USER}" > ${PARFILE}
	echo "schemas=${SCHEMA}" >> ${PARFILE}
	echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
	echo "logfile=${EXPDP_LOG}" >> ${PARFILE}
	echo "directory=DATA_PUMP_DIR" >> ${PARFILE}
	
	expdp parfile=${PARFILE}

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
	ls -ltr ${DATA_PUMP}
}


#variable declarations
SCRIPT_FUNC=$1
TS=$(date "+%m-%d-%Y_%H-%M-%S")

PRACTICE_DIR="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH"

ENV_FILE="/home/oracle/scripts/oracle_env_${DBNAME}.sh"
DATA_PUMP="/backup/AWSJAN26/DATAPUMP/APEXDB"
DBCHECKLOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/dbcheck.log"

#Case statements: function declaration
case ${SCRIPT_FUNC} in
scp)
	#Utilization check
   echo "The number of command-line arguments in this script is: $#"
   if (( $# != 4 ))
   then
      echo "You did not run this script correctly. Please run like below:"
      echo "UTILITY: <SCRIPT_NAME> <SRC> <DST_USER> <DST SERVER> <DST PATH>"
      echo "e.g script_name file1.txt oracle onprem.stack-clixx.com home/oracle/file1.txt"
      echo

      read -p "Do you need help running this script? :" ANSWER
         if [[ ${ANSWER} == 'y' ]]
         then
            echo "You have opted for help..."
            read -p "Enter the source file/directory: " SRC
				read -p "Enter the destination user name: " DST_USER
            read -p "Enter the destination server name: " DST_SERV
				read -p "Enter the destination path: " DST_PATH

            echo "Calling ${SCRIPT_FUNC} function..."
            SCP
         else
            exit 1
         fi
   else
      SRC=$2
		DST_USER=$3
      DST_SERV=$4
		DST_PATH=$5
      #call function
      echo "Calling ${SCRIPT_FUNC} function..."
      SCP
   fi
   echo
	;;
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
				read -p "Enter the source file: " SRC
				read -p "Enter the runner name: " RUNNER

				echo "Calling ${SCRIPT_FUNC} function..."
				BACKUP_F_D
			else
				exit 1
			fi
	else
		SRC=$2
		RUNNER=$3
	   #call function BACKUP_F_D
   	echo "Calling ${SCRIPT_FUNC} function..."
   	BACKUP_F_D
	fi
	echo
	;;
database_backup)
	#utilization check
   echo "The number of command-line arguments in this script is: $#"
   if (( $# != 3 ))
   then
      echo "You did not run this script correctly. Please run like below:"
      echo "UTILITY: <SCRIPT_NAME> <RUNNER> <SCHEMA>"
      echo "e.g database_backup ENOCH STACK_TEMP"
      echo

      read -p "Do you need help running this script? :" ANSWER
	      if [[ ${ANSWER} == 'y' ]]
         then
            echo "You have opted for help..."
				read -p "Who is running this script?" RUNNER
				read -p "What is the schema name?" SCHEMA

				echo "Calling ${SCRIPT_FUNC} function..."
				DATABASE_BACKUP
			else
				exit 1
			fi
	else
		RUNNER=$2
		SCHEMA=$3
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		DATABASE_BACKUP
   fi
	echo
	;;
database_import)
	;;
data_migration)
	;;
AWS)
	;;	
*)
	echo "Invalid function. Aborting."
	exit 1
	;;
esac
