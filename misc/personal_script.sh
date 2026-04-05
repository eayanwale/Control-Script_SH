#!/bin/bash
WILDCARD=$1
FOLDER=$2

PROMPT()
{
	local answer=$2
	eval "${answer}=Y"	
}

if [ $# -ne 2 ]; then
	echo "----------------------------------------------------"
	echo "How do you not know how to run your own script lol"
	echo "USAGE: ./script_namesh [wildcard] [folder name]"
	echo "E.G. ./personal_script.sh CONTROL CONTROL_SCRIPT_SHELL"
	
	read -p "Press 'Y' for prompt assist..." ASSIST
	if (( ${ASSIST^^} == 'Y' )); then
		echo "Here's your help ya dweeb!"
		read -p "Enter Wildcard / file name: " WILDCARD
		read -p "Enter folder name: " FOLDER
	else
		echo "Aborting..."
		exit 1
	fi
fi

echo
echo
echo "This script is to copy folders from Stack Server to your Ubuntu Server"
read -p "Would you like to copy to ${REMOTE}? " ANSWER
if [[ ${ANSWER^^} == 'Y' ]]; then
	echo "Continuing..."
	echo
else
	exit 1
fi

file_find=$(find . -name "*${WILDCARD}*" -exec ls -t {} \;)
echo "${file_find}" > scripts.lst

sed -i 's|./||g' "scripts.lst"
sort -V -o scripts.lst scripts.lst
scripts=$(cat scripts.lst)

file_count=$(wc -l < scripts.lst)
#echo ${file_count}


REMOTE="${REMOTE_HOST:?'Error: REMOTE_HOST environment variable not set (e.g. user@hostname)'}"
DEST="${REMOTE_DEST:-/home/enoch/StackPLY/scripts/BIN/BASH}"

# Open a master connection (asks password once)
ssh -o ControlMaster=yes -o ControlPath=/tmp/sshsock -o ControlPersist=yes -fN ${REMOTE}

count=1
for script in ${scripts}
do
	echo "Copying ${script}"
	scp -o ControlPath=/tmp/sshsock ${script} ${REMOTE}:"${DEST}/${FOLDER}"

	SCP_RC=$?
	if [ ${SCP_RC} -eq 0 ]; then
		echo "Copied ${script} successfully."
	else
		echo "${script} not copied."
		exit 1
	fi
	echo

	(( count ++ ))
	
done
ssh -o ControlPath=/tmp/sshsock -O exit ${REMOTE}

