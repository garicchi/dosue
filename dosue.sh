#!/bin/bash
set -e

export LANG=ja_JP.UTF-8

readonly COLOR_SUCCESS="\e[32;1m"
readonly COLOR_INPUT="\e[35;5m"
readonly COLOR_ERROR="\e[31;1m"
readonly COLOR_END="\e[m"

readonly SCRIPT_NAME="$(basename $0)"
readonly SCRIPT_PATH="$(cd $(dirname $0); pwd)"
readonly CURRENT_DIR=$(pwd)
readonly CONTAINER_PATH="\${HOME}/.containers"
readonly VERSION=1.1

function print_success {
    printf "\n${COLOR_SUCCESS}[SUCCESS] $1${COLOR_END}\n" >&2
}

function print_error {
    printf "\n${COLOR_ERROR}[ERROR] $1${COLOR_END}\n" >&2
}

function print_help {
    cat << __EOS__
${SCRIPT_NAME}

DESCRIPTION
    A docker compose super express deployment tool
    [ex]
        cd <path to docker-compose.yml>
        dosue -s ec2-user@dosue.com deploy
OPTIONS
    -s | --server
        [string] ssh style server host name ex. <username>@<host>
    -c | --compose-file
        [string] docker-compose.yml path. default is current dir
    -e | --env-file
        [string] .env file path for docker-compose. default is current dir
    -p | --port
        [int] ssh port number
    -r | --repository
        [repository] container regisotry name { ecr, gcr }
    -v | --version
       show version
    -h | --help
       show this message
COMMANDS
    deploy
        pull and up conainers in remote server
    cleanup
        down and remove containers in remote server
    login
        login docker-compose.yml directory in remote server
    <any command>
        any command passes to remote docker compose
__EOS__
}

declare SERVER
declare COMPOSE_FILE="docker-compose.yml"
declare ENV_FILE=".env"
declare PORT=22
declare REGISTRY=""

for OPT in "$@"; do
    case "$OPT" in
        -s | --server)
            SERVER="$2"
            shift 2
            ;;
        -c | --compose-file)
            COMPOSE_FILE="$2"
            shift 2
            ;;
        -e | --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -p | --port)
            PORT="$2"
            shift 2
            ;;
        -r | --registory)
            REGISTRY="$2"
            shift 2
            ;;
        -v | --version)
            echo "${VERSION}"
            shift 2
            ;;
        -h | --help)
            print_help
            exit 0
            ;;
    esac
done

COMMANDS="$@"
COMMAND="${COMMANDS[0]}"

if [[ -z "${AWS_PROFILE}" ]]; then
    AWS_PROFILE="default"
fi

readonly SERVICE_NAME=$(echo ${CURRENT_DIR}|awk -F "/" '{ print $NF }')
readonly SERVICE_PATH="${CONTAINER_PATH}/${SERVICE_NAME}"

if ! type aws > /dev/null 2>&1; then
    print_error "aws command not found! please install"
    exit 1
fi

if [[ ${COMMAND} = "deploy" ]]; then
    ssh -p ${PORT} ${SERVER} "mkdir -p ${CONTAINER_PATH}"
    ssh -p ${PORT} ${SERVER} "rm -rf ${SERVICE_PATH}||true"
    ssh -p ${PORT} ${SERVER} "mkdir -p ${SERVICE_PATH}"
    
    scp -P ${PORT} ${COMPOSE_FILE} ${SERVER}:${SERVICE_PATH}/

    if [[ -e ${ENV_FILE} ]]; then
        scp -P ${PORT} ${ENV_FILE} ${SERVER}:${SERVICE_PATH}/
    else
        echo "[WARNING] ${ENV_FILE} not found. skip to deploy env file"
    fi
    
    echo $(aws ecr get-login --no-include-email --profile ${AWS_PROFILE}) > /tmp/ecr_login
    
    scp -P ${PORT} /tmp/ecr_login ${SERVER}:/tmp/
    
    ssh -p ${PORT} ${SERVER} "chmod u+x /tmp/ecr_login && bash /tmp/ecr_login"
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && [[ \$(docker-compose ps -q|wc -l) -gt 0 ]] && docker-compose down || true"
    
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose pull"
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose up -d"
    
    ssh -p ${PORT} ${SERVER} "rm -f /tmp/ecr_login"
    rm -f /tmp/ecr_login
    
    ssh -p ${PORT} ${SERVER} "docker logout"

    print_success "🚅 container deployment completed!"
    exit 0
fi

if [[ ${COMMAND} = "cleanup" ]]; then
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && [[ \$(docker-compose ps -q|wc -l) -gt 0 ]] && docker-compose down"
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose rm -f -s"
    ssh -p ${PORT} ${SERVER} "rm -rf ${SERVICE_PATH}"
    
    print_success "🧹 container cleanup completed!"
    exit 0
fi

if [[ ${COMMAND} = "login" ]]; then
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH};bash -i"
    exit 0
fi

if [[ ! -z "${COMMAND}" ]]; then    
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose ${COMMANDS}"
    exit 0
fi


print_help >&2
print_error "unknown command: $COMMAND"
exit 1
