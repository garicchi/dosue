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

    you can deploy docker-compose service more easily by using dosue
        
EXAMPLE
    cd <path to docker-compose.yml>
    dosue --server ec2-user@<SERVER HOST> deploy

OPTIONS
    -s | --server
        [string] ssh style server host name ex. <username>@<host>
    -c | --compose-file
        [string] docker-compose.yml path. default is current dir
    -e | --env-file
        [string] .env file path for docker-compose. default is current dir
    -p | --port
        [int] ssh port number for accessing remote server
    -r | --repository
        [choice] container regisotry name { ecr }
            now, dosue only support ecr
            gcr support is future task
    -f | --force
        [flag] force deploy
    -w | --web-port
        [int] a port number for web server
            if specify this option, nginx will pass to access
            from <host>/<service name> to <host>:<web port>
            
            so you can access web service by <host>/<service name>
    -v | --version
        [flag] show version
    -h | --help
        show this message

COMMANDS
    deploy
        pull and up conainers in remote server
    cleanup
        down and remove containers in remote server
    status
        show dosue status
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
declare FORCE=false
declare WEB_PORT=

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
            shift 1
            ;;
        -f | --force)
            FORCE=true
            shift 1
            ;;
        -w | --web-port)
            WEB_PORT="$2"
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

readonly DOSUE_STATUS=$(ssh -p ${PORT} ${SERVER} "ls ${CONTAINER_PATH}|grep -x \"${SERVICE_NAME}\"|wc -l")

if [[ ${COMMAND} = "deploy" ]]; then
    
    if [[ ${DOSUE_STATUS} -gt 0 && ${FORCE} = false ]]; then
        printf "container [ ${SERVICE_NAME} ] is already deployed\n"
        read -p "Overwrite? (Y/n) " ANS
        if [[ ! ${ANS} = "Y" ]]; then
            if [[ ${ANS} = "n" || ! ${ANS} = "" ]]; then
                printf "deploy canceled!"
                exit 1
            fi
        fi        
    fi

    ssh -p ${PORT} ${SERVER} "mkdir -p ${CONTAINER_PATH}"
    ssh -p ${PORT} ${SERVER} "rm -rf ${SERVICE_PATH}||true"
    ssh -p ${PORT} ${SERVER} "mkdir -p ${SERVICE_PATH}"
    ssh -p ${PORT} ${SERVER} "echo \"\" > ${SERVICE_PATH}/dosue.info"
    
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
    
    # enable to access http://<server host>/<service name>
    #   nginx reverse proxy passes access from <server host>:${WEB_PORT} to <server host>/<service name>
    if [[ ! -z ${WEB_PORT} ]]; then
        cat << __EOS__ > /tmp/${SERVICE_NAME}.conf
location /${SERVICE_NAME}/ {
    proxy_pass http://127.0.0.1:${WEB_PORT}/;
}

__EOS__
        scp -P ${PORT} /tmp/${SERVICE_NAME}.conf ${SERVER}:/tmp
        ssh -p ${PORT} ${SERVER} "sudo mv /tmp/${SERVICE_NAME}.conf /etc/nginx/default.d/"
        ssh -p ${PORT} ${SERVER} "sudo nginx -s reload"
        rm -f /tmp/${SERVICE_NAME}.conf
    fi

    # write commit hash in remote dosue.info
    if [[ -e ${CURRENT_DIR}/.git ]]; then
        pushd ${CURRENT_DIR}
        COMMIT_HASH=$(git rev-parse HEAD)
        popd
    fi
    # if already wrote, then append hash. if did not already write, then rewrite line
    ssh -p ${PORT} ${SERVER} "FILE=${SERVICE_PATH}/dosue.info;REG=\"^GIT_HASH=\";LINE=\"GIT_HASH=${COMMIT_HASH}\";grep -e \"\$REG\" \$FILE&&(sed -e \"/\$REG/d\" -i \$FILE&&echo \$LINE>>\$FILE)||echo \$LINE>>\$FILE"
    
    ssh -p ${PORT} ${SERVER} "rm -f /tmp/ecr_login"
    rm -f /tmp/ecr_login
    
    ssh -p ${PORT} ${SERVER} "docker logout"

    print_success "🚅 container deployment completed!"
    exit 0
fi

if [[ ${COMMAND} = "cleanup" ]]; then
    if [[ ${DOSUE_STATUS} -eq 0 ]]; then
        print_error "container [ ${SERVICE_NAME} ] not found!"
        exit 1
    fi
    
    if [[ ${FORCE} = false ]]; then
        printf "container [ ${SERVICE_NAME} ] is already deployed\n"
        read -p "Cleanup? (Y/n) " ANS
        if [[ ! ${ANS} = "Y" ]]; then
            if [[ ${ANS} = "n" || ! ${ANS} = "" ]]; then
                printf "cleanup canceled!"
                exit 1
            fi
        fi
    fi

    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose down -v --remove-orphans --rmi local"
    ssh -p ${PORT} ${SERVER} "rm -rf ${SERVICE_PATH}"
    ssh -p ${PORT} ${SERVER} "sudo rm -f /etc/nginx/default.d/${SERVICE_NAME}.conf||true"
    
    print_success "🧹 container cleanup completed!"
    exit 0
fi

if [[ ${COMMAND} = "status" ]]; then
    printf "***** deploy status *****\n\n"
    if [[ ${DOSUE_STATUS} -gt 0 ]]; then
        printf "container [ ${SERVICE_NAME} ] already deployed!\n"
        printf "docker-compose.yml is in [ ${SERVICE_PATH} ]\n"
        printf "\n\n***** dosue info *****\n"
        printf "dosue.info\n"
        ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && cat dosue.info"
        printf "\n\n***** container processes *****\n"
        ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose ps" 2> /dev/null

    else
        printf "container [ ${SERVICE_NAME} ] has not been deployed yet\n"
    fi
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
