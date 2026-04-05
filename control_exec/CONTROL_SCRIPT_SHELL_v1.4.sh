#!/bin/bash

#variable declarations
SRC=$1
DST=$2
RUNNER=$3

#declare the backup path
BACKUP=$DST/$RUNNER

#main body

#utilization check
echo "The number of command-line arguments in this script is: $#"

if [[ $# != 3 ]]
then
	echo "You did not run this script correctly. Please run like below:"
	echo "UTILITY: <SRC> <DST> <RUNNER>"
	echo "e.g home/oracle/file.txt home/oracle backup"
fi

#creating backup directory
echo "creating backup directory ${BACKUP}..."
mkdir -p ${BACKUP}
echo "Exit status: " $?

#object type validation
if [[ -d ${SRC} ]]
then
	echo "${SRC} is a directory."
	echo "Copying the DIRECTORY to a specified backup location ${BACKUP}"
	cp -r ${SRC} ${BACKUP}
	echo "Exit status: " $?
elif [[ -f ${SRC} ]]
then
	echo "${SRC} is a file."
	echo "Copying the FILE to a specified backup location ${BACKUP}"
	cp ${SRC} ${BACKUP}
	echo "Exit status: " $?
else
	echo "Please re-run the script using a real object."
	exit 1
fi

#validate
echo "Listing files in backup directory ${BACKUP}..."
ls -ltr ${BACKUP}

