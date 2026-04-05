#!/bin/bash


branch=$(git branch --show-current)
target=$1

if [ -z ${target} ]; then
        echo "Usage: ./git_push.sh <environment>"
        echo "Environments: dev, qa, uat, main"
        exit 1
fi

if [[ ${target} == "main" ]]; then
        echo "You are about to push to prod/main..."
        read -sp "Please enter G/admin password: " PASS
        if [[ ${PASS} != "imaG" && ${PASS} != "admin" ]]; then
                echo "Wrong password. You are not a G or admin."
                echo "You cannot push to prod/main. Exiting..."
                exit 1
        fi
fi

read -p "Commit message: " MSG

echo "--- Pushing to origin ${branch} ---"
git add .
git commit -m "${MSG}"
git push -u origin ${branch}

echo "--- Merging ${branch} into ${target} ---"
git checkout ${target}
git merge ${branch}
git push

git checkout ${branch}
echo "${branch} pushed and merged into ${target}."

