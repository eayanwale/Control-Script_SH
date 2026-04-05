#!/bin/bash

COMMIT()
{
        echo "--- Pushing to origin ${branch} ---"
        git add .
        git commit -m "${MSG}"
        git push -u origin ${branch}
}

MERGE()
{
        echo "--- Merging ${branch} into ${target} ---"
        git checkout ${target}
    	if ! git merge ${branch}; then
        	echo "ERROR: Merge conflict merging ${branch} into ${target}."
        	echo "Resolve conflicts manually, then re-run."
        	exit 1
    	fi
        git push
}


branch=$(git branch --show-current)
target=$1

if [ -z ${target} ]; then
        echo "Usage: ./git_push.sh <environment>"
        echo "Environments: dev, qa, uat, main, skip"
        exit 1
fi
echo

if [[ ${target} == "skip" ]]; then
	echo "You have opted to skip and go straight to prod."
	read -sp "Please enter G/admin password: " PASS
	if [[ ${PASS} != "imaG" && ${PASS} != "admin" ]]; then
        	echo "Wrong password. You are not a G or admin."
                echo "You cannot push to prod/main. Exiting..."
                exit 1
        fi
	echo

	read -p "Commit message: " MSG
	COMMIT
	
	echo "--- Merging ${branch} and skipping through environments ---"
	prev=${branch}
	for env in dev qa uat main
	do
		echo "--- Merging ${prev} into ${env} ---"
		git checkout ${env}
		if ! git merge ${prev}; then
			echo "ERROR: Conflict merging into ${env}. Resolve and Re-run."
			exit 1
		fi
		git push
		prev=${env}
	done
	git checkout ${branch}
	echo "${branch} pushed and merged into ${target}."
	exit 0
fi
echo

if [[ ${target} == "main" ]]; then
        echo "You are about to push to prod/main..."
        read -sp "Please enter G/admin password: " PASS
        if [[ ${PASS} != "imaG" && ${PASS} != "admin" ]]; then
                echo "Wrong password. You are not a G or admin."
                echo "You cannot push to prod/main. Exiting..."
                exit 1
        fi
fi
echo

read -p "Commit message: " MSG

COMMIT
MERGE

git checkout ${branch}
echo "${branch} pushed and merged into ${target}."

