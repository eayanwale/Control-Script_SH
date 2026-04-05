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
	echo "Copying ${SRC} to ${DST_USER}@${DST_SERV} at ${DST_PATH}"
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

DISK_UTILIZATION()
{
   #disks mounted on this server
   DSKS="/u01 /u02 /u03 /u04 /u05 /backup"

   for disk in ${DSKS}
   do
      #-check if disk is mounted
      if ! df -h | grep "${disk}"
      then
         echo "Disk(s) are not mounted!"
         exit 1
      fi

      disk_check=$(df -h | grep "${disk}" | awk '{print $4}' | sed 's/%//g')

      echo "Checking ${disk} : ${disk_check}% used"
      echo

      if (( disk_check > THRESHOLD ))
      then
         echo "WARNING: ${disk} utilization is ${disk_check}% (threshold: ${THRESHOLD}%)"
         echo "Sending alert to DevOps distro...\n"
         mail -s "Alert: Disk Utilization Exceeded!" ${ALERT_EMAIL} <<EOF
-------ALERT-------
Disk Utilization on ${disk} is ${disk_check}
${disk} utilization has exceeded threshold: ${THRESHOLD}%
EOF
         if (( $? != 0 ))
         then
            echo "Failed to send email."
            exit 1
         fi
      fi
   done
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

   PARFILE="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/expdp_${SCHEMA}_${RUNNER}_${TS}.par"
	EXPDP_LOG="expdp_${SCHEMA}_${RUNNER}_${TS}.log"
	EXPDP_LOG_PATH=${DATA_DUMP}/${EXPDP_LOG}
	DUMP_FILE="expdp_${SCHEMA}_${RUNNER}_${TS}.dmp"
	DATA_PUMP="/backup/AWSJAN26/DATAPUMP/APEXDB"

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

DATABASE_IMPORT()
{
	#-check if database is present on server
	if ( ! grep ${DB_NAME} /etc/oratab )
	then
   	echo "The ${DB_NAME} database does not exist on this server."
   	exit 1
	fi

	ENV_FILE="/home/oracle/scripts/oracle_env_${DB_NAME}.sh"
	#-check if database environment file exists
	if [[ ! -f ${ENV_FILE} ]]
	then
		echo "Environment not found. Exiting..."		
		exit 1
	fi
	source ${ENV_FILE}

	#-check if instance is running
	if ( ps -ef | grep pmon | grep ${DB_NAME} )	
	then
		echo "The ${DB_NAME} database instance is up and running."
	else
		echo "THE ${DB_NAME^^} IS DOWN!!!"
		exit 1
	fi

	#-check open status
	sqlplus ${DB_USER}/${DB_PASS} <<EOF > ${DBCHECKLOG}
set echo on feedback on term on pagesize 0
select status from v\$instance;
EOF
	#-log open status
	if ( grep "OPEN" ${DBCHECKLOG} )
	then
		echo "The database is open for backup."
	else
		echo "The database is not open. Backup cannot occur."
		exit 1
	fi
	echo

	DATA_PUMP="/backup/AWSJAN26/DATAPUMP/${DB_NAME}"

	#-copy dump file
	echo "Copying dump file to ${DB_NAME} path..."
	cp -rf /backup/AWSJAN26/DATAPUMP/APEXDB/${DUMP_FILE} ${DATA_PUMP}/${DUMP_FILE}
	if (( $? != 0 ))
	then
		echo "Dump file copy failed!"
		exit 1
	fi

	#-schema list option
	if [[ -f ${SCHEMA} ]]
	then
		echo "Schema list detected."
		
		count=1
		#-loop each schema in list
		while read lst_schema
		do 
			echo "Processing for schema: ${lst_schema}"

			PARFILE="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/impdp_${lst_schema}_${RUNNER}.par"
			IMPDP_LOG="impdp_${lst_schema}_${RUNNER}_${TS}.log"
			IMPDP_LOG_PATH=${DATA_PUMP}/${IMPDP_LOG}

			echo "userid=${DB_USER}/${DB_PASS}" > ${PARFILE}
			echo "schemas=${lst_schema}" >> ${PARFILE}
			echo "remap_schema=${lst_schema}:${lst_schema}_${RUNNER}" >> ${PARFILE}
			echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
			echo "logfile=${IMPDP_LOG}" >> ${PARFILE}
			echo "directory=${DIRECTORY}" >> ${PARFILE}

			impdp parfile=${PARFILE}
			if (( $? != 0 ))
			then
			   echo "impdp FAILED!"
			   exit 1
			fi

			#-check log file for success
			if ( grep "successfully completed" ${IMPDP_LOG_PATH} )
			then
			   echo "The import was SUCCESSFUL!"
			elif ( grep "completed with" ${IMPDP_LOG_PATH} )
			then
			   echo "The import completed with errors. See log: ${IMPDP_LOG_PATH}"
			else
			   echo "The import FAILED!"
			   echo "Check logs: ${IMPDP_LOG_PATH}"
			   exit 1
			fi
			echo

			#-confirm database backup
			echo "Confirming import:"
			ls -ltr ${DATA_PUMP}		

			if (( count == 4 ))
			then
				break
			fi

			(( count ++ ))

		done < ${SCHEMA}
	else
		echo "Single schema detected: ${SCHEMA}"
      echo "Processing for schema: ${col_schema}"

		PARFILE="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/impdp_${SCHEMA}_${RUNNER}.par"
		IMPDP_LOG="impdp_${SCHEMA}_${RUNNER}_${TS}.log"
		IMPDP_LOG_PATH=${DATA_PUMP}/${IMPDP_LOG}

      echo "userid=${DB_USER}/${DB_PASS}" > ${PARFILE}
      echo "schemas=${SCHEMA}" >> ${PARFILE}
      echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> ${PARFILE}
      echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
      echo "logfile=${IMPDP_LOG}" >> ${PARFILE}
      echo "directory=${DIRECTORY}" >> ${PARFILE}

      impdp parfile=${PARFILE}
      if (( $? != 0 ))
		then
         echo "impdp FAILED!"
         exit 1
      fi

      #-check log file for success
      if ( grep "successfully completed" ${IMPDP_LOG_PATH} )
      then
         echo "The import was SUCCESSFUL!"
      elif ( grep "completed with" ${IMPDP_LOG_PATH} )
      then
          echo "The import completed with errors. See log: ${IMPDP_LOG_PATH}"
      else
         echo "The import FAILED!"
         echo "Check logs: ${IMPDP_LOG_PATH}"
         exit 1
      fi
      echo

      #-confirm database backup
      echo "Confirming import:"
      ls -ltr ${DATA_PUMP}
	fi

<<comment
	echo "userid=${DB_USER}/${DB_PASS}" > ${PARFILE}
	echo "schemas=${SCHEMA}" >> ${PARFILE}
	echo "remap_schema=${SCHEMA}:${SCHEMA}_${RUNNER}" >> ${PARFILE}
	echo "dumpfile=${DUMP_FILE}" >> ${PARFILE}
	echo "logfile=${IMPDP_LOG}" >> ${PARFILE}
	echo "directory=${DIRECTORY}" >> ${PARFILE}
	
	impdp parfile=${PARFILE}
	if (( $? != 0 ))
	then
		echo "impdp FAILED!"
		exit 1
	fi

	#-check log file for success
	if ( grep "successfully completed" ${IMPDP_LOG_PATH} )
	then
		echo "The import was SUCCESSFUL!"
	elif ( grep "completed with" ${IMPDP_LOG_PATH} )
	then
		echo "The import completed with errors. See log: ${IMPDP_LOG_PATH}"
	else
		echo "The import FAILED!"
		echo "Check logs: ${IMPDP_LOG_PATH}"
		exit 1
	fi

	#-confirm database backup
	echo "Confirming import:"
	ls -ltr ${DATA_PUMP}
comment

}

#variable declarations
SCRIPT_FUNC=$1
TS=$(date "+%m-%d-%Y_%H-%M-%S")

PRACTICE_DIR="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH"

DBCHECKLOG="/home/oracle/scripts/practicedir_eno_jan26/BIN/BASH/dbcheck.log"

#Case statements: function declaration
case ${SCRIPT_FUNC} in
scp)
	#Utilization check
   echo "The number of command-line arguments in this script is: $#"
   if (( $# != 5 ))
   then
      echo "You did not run this script correctly. Please run like below:"
      echo "UTILITY: <SCRIPT_NAME> <SRC> <DST_USER> <DST SERVER> <DST PATH>"
      echo "e.g script_name file1.txt oracle onprem.stack-clixx.com home/oracle/file1.txt"
      echo

      read -p "Do you need help running this script? :" ANSWER
         if [[ ${ANSWER^^} == 'Y' ]]
         then
            echo "You have opted for help..."
            read -p "Enter the source file/directory: " SRC
				read -p "Enter the destination user name: " DST_USER
            read -p "Enter the destination server name: " DST_SERV
				read -p "Enter the destination path: " DST_PATH

            echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
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
      echo "..."
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
			if [[ ${ANSWER^^} == 'Y' ]]
			then
				echo "You have opted for help..."
				read -p "Enter the source file: " SRC
				read -p "Enter the runner name: " RUNNER

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				BACKUP_F_D
			else
				exit 1
			fi
	else
		SRC=$2
		RUNNER=$3
	   #call function BACKUP_F_D
   	echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
   	BACKUP_F_D
	fi
	echo
	;;
disk_util)
   #utilization check
   echo "The number of command-line arguments in this script is: $#"
   if (( $# != 2 ))
   then
      echo "You did not run this script correctly. Please run like below:"
      echo "UTILITY: <SCRIPT_NAME> <THRESHOLD>"
      echo "e.g script_name 70"
      echo

      read -p "Do you need help running this script? :" ANSWER
         if [[ ${ANSWER^^} == 'Y' ]]
         then
            echo "You have opted for help..."
            read -p "Enter threshold value " THRESHOLD

            echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
            DISK_UTILIZATION
         else
            exit 1
         fi
   else
      THRESHOLD=$2
      #call function BACKUP_F_D
      echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
      DISK_UTILIZATION
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
	      if [[ ${ANSWER^^} == 'Y' ]]
         then
            echo "You have opted for help..."
				read -p "Who is running this script?" RUNNER
				read -p "What is the schema name?" SCHEMA

				echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
				DATABASE_BACKUP
			else
				exit 1
			fi
	else
		RUNNER=$2
		SCHEMA=$3
		#Call function
		echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
		DATABASE_BACKUP
   fi
	echo
	;;
database_import)
   #utilization check
   echo "The number of command-line arguments in this script is: $#"
   if (( $# != 6 ))
   then
      echo "You did not run this script correctly. Please run like below:"
      echo "UTILITY: <SCRIPT_NAME> <DB_NAME> <RUNNER> <SCHEMA> <DIRECTORY> <DUMP FILE>"
      echo "e.g database_import APEXDB ENOCH STACK_TEMP DATA_PUMP_DIR enoch_backup.dmp"
      echo

      read -p "Do you need help running this script? :" ANSWER
         if [[ ${ANSWER^^} == 'Y' ]]
         then
            echo "You have opted for help..."
            read -p "What is the database name? " DB_NAME
				read -p "Who is running this script? " RUNNER
            read -p "What is the schema name? " SCHEMA
				read -p "What is the directory name? " DIRECTORY
				read -p "What is the dump file?" DUMP_FILE

            echo "Calling ${SCRIPT_FUNC} function..."
				echo "..."
            DATABASE_IMPORT
         else
            exit 1
         fi
   else
      DB_NAME=$2
		RUNNER=$3
      SCHEMA=$4
		DIRECTORY=$5
		DUMP_FILE=$6
      #Call function
      echo "Calling ${SCRIPT_FUNC} function..."
		echo "..."
      DATABASE_IMPORT
   fi
   echo
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
