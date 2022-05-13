#!/bin/bash

####################################################################
## Author: Itiel Luque Díaz - 2022.                               ##
##                                                                ##
## Description: Script to deal with PRs of Bitbucket interacting  ##
##              with its public REST API.                         ##
##                                                                ##
## License: You are allowed to modify and distribute this         ## 
##          source code.                                          ##
##          You must quote author in your copy and add            ##
##          this license.                                         ##
####################################################################

####################################################################
#                      GLOBAL CONFIGURATION                        #
####################################################################
CONFIG_FILE="pullrequest.config.json"

# PATHS
BASE_URL=""
PROJECT_DIR=""

# CREDENTIALS
CREDENTIAL_NAME=""
CREDENTIAL_AUTHKEY=""

# PROJECT
PROJECT_KEY=""
PROJECT_SLUG=""
PROJECT_NAME=""

# ENDPOINT
PR_ENDPOINT=""
FULL_URL=""

CURRENT_BRANCH=""

declare -a REVIEWERS=()

####################################################################
#                           PARAMS PARSER                          #
####################################################################
helpFunction()
{
   echo ""
   echo "Usage: $0 -d destination"
   echo -e "\t-d Destination branch where you want merge your current branch"
   exit 1 # Exit script after printing help
}

while getopts "d:" opt
do
   case "$opt" in
      d ) DESTINATION_BRANCH="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print help function in case paramter is empty
if [ -z "$DESTINATION_BRANCH" ]
then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

####################################################################
#                            FUNCTIONS                             #
####################################################################

function configureGlobals() {
    local fileBuffer=$(cat ${CONFIG_FILE})

    # PATH
    BASE_URL=$(eval echo $(echo ${fileBuffer} | jq .path.baseUrl))
    PROJECT_DIR=$(eval echo $(echo ${fileBuffer} | jq .path.projectDir))
    
    # PROJECT SETTINGS
    PROJECT_KEY=$(eval echo $(echo ${fileBuffer} | jq .project.key))
    PROJECT_SLUG=$(eval echo $(echo ${fileBuffer} | jq .project.slug))
    PROJECT_NAME=$(eval echo $(echo ${fileBuffer} | jq .project.name))

    # CREDENTIALS
    CREDENTIAL_NAME=$(echo ${fileBuffer} | jq .bitbucket.username | tr -d '"')
    CREDENTIAL_AUTHKEY=$(echo ${fileBuffer} | jq .bitbucket.authkey | tr -d '"')

    # REVIEWERS
    for reviewer in $(echo ${fileBuffer} | jq '.reviewers[] .name' | tr -d '"') ; do REVIEWERS+=(${reviewer}); done

    PR_ENDPOINT="/projects/${PROJECT_KEY}/repos/${PROJECT_SLUG}/pull-requests"

    FULL_URL="${BASE_URL}${PR_ENDPOINT}"

    CURRENT_BRANCH=$(git -C ${PROJECT_DIR} branch --show-current)
}

function checkForCommand() {
    local command=$1
    local install=$2
    
    if ! command -v $command &> /dev/null
    then
        while true; do
            read -p "No se encuentra instalado el comando ${command}. ¿Quieres intalarlo? (s/n) " yn
            case $yn in
                [Ss]* ) eval $install;
                        if [[ "$command" == "brew" ]]; then
                            arch_name="$(uname -m)"
                            if [ "${arch_name}" = "x86_64" ]; then
                                echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
                                eval "$(/usr/local/bin/brew shellenv)"
                            elif [ "${arch_name}" = "arm64" ]; then
                                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                                eval "$(/opt/homebrew/bin/brew shellenv)"
                            else
                                echo "Unknown architecture: ${arch_name}"
                            fi
                            source ~/.zshrc
                        fi

                        break;;
                [Nn]* ) exit;;
                * ) echo "Porfavor, introduce si o no (s/n).";;
            esac
        done
    fi
}

function installDependencies() {
    checkForCommand "brew" "/bin/bash -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)'"
    checkForCommand "jq" "brew install jq"
}

####################################################################
#                           MAIN PROGRAM                           #
####################################################################

cd $(dirname $0)
installDependencies
configureGlobals

DESTINATION_BRANCH_EXISTS=$(git -C ${PROJECT_DIR} ls-remote --heads origin ${DESTINATION_BRANCH})

if [[ -z ${DESTINATION_BRANCH_EXISTS} ]]; then
    echo "Check origin's destination branch, does not exists... May you made a typo."
else
    COMMITS=$(git -C ${PROJECT_DIR} cherry -v ${DESTINATION_BRANCH} ${CURRENT_BRANCH} | cut -d" " -f3-)

    REVIEWERS_JSON=""
    REVIEWERS_COUNT=${#REVIEWERS[@]}

    for (( i=0; i<$REVIEWERS_COUNT; i++ ));
    do
        REVIEWERS_JSON="${REVIEWERS_JSON}
            {
                \"user\": {
                    \"name\": \"${REVIEWERS[$i]}\"
                }
            }"

        if [ "$REVIEWERS_COUNT" -gt "1" ] && [ "$i" -lt "$(($REVIEWERS_COUNT - 1))" ]; then
            REVIEWERS_JSON="${REVIEWERS_JSON},"
        fi
    done

    OUTPUT="{
        \"title\": \"${CURRENT_BRANCH}\",
        \"description\": \"${COMMITS}\",
        \"state\": \"OPEN\",
        \"open\": true,
        \"closed\": false,
        \"fromRef\": {
            \"id\": \"${CURRENT_BRANCH}\",
            \"repository\": {
                \"slug\": \"${PROJECT_SLUG}\",
                \"name\": \"${PROJECT_NAME}\",
                \"project\": {
                    \"key\": \"${PROJECT_KEY}\"
                }
            }
        },
        \"toRef\": {
            \"id\": \"${DESTINATION_BRANCH}\",
            \"repository\": {
                \"slug\": \"${PROJECT_SLUG}\",
                \"name\": \"${PROJECT_NAME}\",
                \"project\": {
                    \"key\": \"${PROJECT_KEY}\"
                }
            }
        },
        \"locked\": false,
        \"reviewers\": [
            ${REVIEWERS_JSON}
        ]
    }"

    COMPACTEDJSON=$(jq -n "$OUTPUT" | jq -c)

    curl -X POST -H "Content-Type: application/json" -u "$CREDENTIAL_NAME:$CREDENTIAL_AUTHKEY" -d "$COMPACTEDJSON" $FULL_URL
fi