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

#-exit status
if (( $? != 0))
then
	echo "Could not create backup directory."
fi

#copying source value to backup destination
echo "copying ${SRC} to specified  backup location ${BACKUP}..."
cp -rf ${SRC} ${BACKUP}
echo "Exit status: " $?

#-exit status with success check
if (( $? != 0 ))
then
    echo "The copy command failed."
fi

#validate
echo "Listing files in backup directory ${BACKUP}..."
ls -ltr ${BACKUP}

