#!/bin/bash
set -e

export LANG=ja_JP.UTF-8

readonly COLOR_SUCCESS="\e[32;1m"
readonly COLOR_STEP="\e[33;1m"
readonly COLOR_INPUT="\e[35;5m"
readonly COLOR_ERROR="\e[31;1m"
readonly COLOR_END="\e[m"

readonly SCRIPT_NAME="$(basename $0)"
readonly SCRIPT_PATH="$(cd $(dirname $0); pwd)"
readonly CURRENT_DIR=$(pwd)
readonly CONTAINER_PATH="\${HOME}/.containers"
readonly VERSION=1.2

function print_step {
    printf "\n${COLOR_STEP}[STEP] $1${COLOR_END}\n"
}

function print_success {
    printf "\n${COLOR_SUCCESS}[SUCCESS] $1${COLOR_END}\n"
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
        [require] [string] ssh style server host name ex. <username>@<host>
    -r | --repository
        [require] [choice] container regisotry name { ecr, hub }
            now, dosue only support ecr or dockerhub
    -c | --compose-file
        [string] docker-compose.yml path. default is current dir
    -e | --env-file
        [string] .env file path for docker-compose. default is current dir
    -p | --port
        [int] ssh port number for accessing remote server
    -f | --force
        [flag] force deploy
    -n | --no-push
        [flag] deploy without image build & push
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

ENVIRONMENTS
    DOSUE_AWS_PROFILE
        aws profile name by using ecr
__EOS__
}

######
###### analyzing input parameters
######

print_step "analyzing parameters"

declare SERVER
declare COMPOSE_FILE="docker-compose.yml"
declare ENV_FILE=".env"
declare PORT=22
declare REGISTORY=""
declare FORCE=false
declare WEB_PORT=
declare NO_PUSH=false

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
            REGISTORY="$2"
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
        -n | --no-push)
            PORT="$2"
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

if [[ -z "${DOSUE_AWS_PROFILE}" ]]; then
    AWS_PROFILE="default"
fi

readonly SERVICE_NAME=$(echo ${CURRENT_DIR}|awk -F "/" '{ print $NF }')
readonly SERVICE_PATH="${CONTAINER_PATH}/${SERVICE_NAME}"

if [[ "${REGISTORY}" = "hub" || "${REGISTORY}" = "ecr" ]]; then
    printf "use ${REGISTORY} registory\n"
else
    print_error "--registory [ ${REGISTORY} ] is wrong! please choose { hub, ecr }"
    exit 1
fi

if [[ "${REGISTORY}" = "ecr" ]]; then
    if ! type aws > /dev/null 2>&1; then
        print_error "aws command not found! please install"
        exit 1
    fi
fi

readonly DOSUE_STATUS=$(ssh -p ${PORT} ${SERVER} "ls ${CONTAINER_PATH}|grep -x \"${SERVICE_NAME}\"|wc -l")

######
###### process command
######

print_step "execute command [ ${COMMAND} ]"

if [[ ${COMMAND} = "deploy" ]]; then

    ######
    ###### check registry account
    ######
    
    print_step "check registry account"

    # confirm AWS profile
    if [[ ${FORCE} = false ]]; then
        printf "conainer registory info\n"
        if [[ "${REGISTORY}" = "ecr" ]]; then
            printf "aws profile [ ${DOSUE_AWS_PROFILE} ]\n"
            printf "if you want to change profile then you should set environment DOSUE_AWS_PROFILE=<profile>"
            aws sts get-caller-identity --profile ${DOSUE_AWS_PROFILE}
        elif [[ "${REGISTORY}" = "hub" ]]; then
            printf "use DockerHub\n"
        fi
        read -p "OK? (Y/n) " ANS
        if [[ ! ${ANS} = "Y" ]]; then
            if [[ ${ANS} = "n" || ! ${ANS} = "" ]]; then
                printf "deploy canceled!"
                exit 1
            fi
        fi        
    fi

    ######
    ###### check deployment status
    ######
    
    print_step "check deployment status"

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
    
    if [[ ${NO_PUSH} = false ]]; then
        ######
        ###### push images
        ######
        
        print_step "push images"

        pushd ${CURRENT_DIR}
        if [[ "${REGISTORY}" = "ecr" ]]; then
            $(aws ecr get-login --no-include-email --profile ${DOSUE_AWS_PROFILE})
        elif [[ "${REGISTORY}" = "hub" ]]; then
            read -p "DockerHub ID:" HUB_USER
            read -sp "DockerHub Pass:" HUB_PASS
            
            docker login -u ${HUB_USER} -p ${HUB_PASS}
        fi
        
        docker-compose build
        docker-compose push
        popd
    fi

    ######
    ###### copy files to remote server
    ######
    
    print_step "copy files to remote server"

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

    # binフォルダにスクリプトとか入れることを考慮してbinフォルダもコピー
    if [[ -e bin/ ]]; then
        scp -P ${PORT} -r bin/ ${SERVER}:${SERVICE_PATH}/
    fi

    ######
    ###### pull images
    ######
    
    print_step "pull images"
    
    # Dockerfileのあるディレクトリのフォルダがないとdocker-compose pullできない(謎)
    # だからリモートにも同じフォルダを作る
    for d in $(find . -type f -name Dockerfile); do
        DIRECTORY=$(echo $d|sed -e "s/Dockerfile//g")
        ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && mkdir -p ${DIRECTORY}"
    done

    if [[ "${REGISTORY}" = "ecr" ]]; then
        echo $(aws ecr get-login --no-include-email --profile ${DOSUE_AWS_PROFILE}) > /tmp/ecr_login
        scp -P ${PORT} /tmp/ecr_login ${SERVER}:/tmp/
        ssh -p ${PORT} ${SERVER} "chmod u+x /tmp/ecr_login && bash /tmp/ecr_login"
        ssh -p ${PORT} ${SERVER} "rm -f /tmp/ecr_login"
        rm -f /tmp/ecr_login
    elif [[ "${REGISTORY}" = "hub" ]]; then
        ssh -p ${PORT} ${SERVER} "docker login -u ${HUB_USER} -p ${HUB_PASS}"
    fi

    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && [[ \$(docker-compose ps -q|wc -l) -gt 0 ]] && docker-compose down || true"
    
    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose pull"

    ######
    ###### up services
    ######
    
    print_step "up services"

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

    ######
    ###### write deplyment status
    ######
    
    print_step "write deployment status"


    # write commit hash in remote dosue.info
    if [[ -e ${CURRENT_DIR}/.git ]]; then
        pushd ${CURRENT_DIR}
        COMMIT_HASH=$(git rev-parse HEAD)
        popd
    fi
    # if already wrote, then append hash. if did not already write, then rewrite line
    ssh -p ${PORT} ${SERVER} "FILE=${SERVICE_PATH}/dosue.info;REG=\"^GIT_HASH=\";LINE=\"GIT_HASH=${COMMIT_HASH}\";grep -e \"\$REG\" \$FILE&&(sed -e \"/\$REG/d\" -i \$FILE&&echo \$LINE>>\$FILE)||echo \$LINE>>\$FILE"
    
    ######
    ###### docker logout
    ######
    
    print_step "docker logout"

    ssh -p ${PORT} ${SERVER} "docker logout"

    print_success "🚅 container deployment completed!"
    exit 0
fi

if [[ ${COMMAND} = "cleanup" ]]; then
    ######
    ###### check to cleanup
    ######
    
    print_step "check to cleanup"

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

    ######
    ###### down services
    ######
    
    print_step "down services"

    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose down -v --remove-orphans --rmi local"
    ssh -p ${PORT} ${SERVER} "rm -rf ${SERVICE_PATH}"
    ssh -p ${PORT} ${SERVER} "sudo rm -f /etc/nginx/default.d/${SERVICE_NAME}.conf||true"
    
    print_success "🧹 container cleanup completed!"
    exit 0
fi

if [[ ${COMMAND} = "status" ]]; then
    ######
    ###### show statues
    ######
    
    print_step "show statues"

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
    ######
    ###### login to remote server
    ######
    
    print_step "login to remote server"

    ssh -t -p ${PORT} ${SERVER} "cd ${SERVICE_PATH};bash -l"
    exit 0
fi

if [[ ! -z "${COMMAND}" ]]; then    
    ######
    ###### execute docker-compose command in remote
    ######
    
    print_step "execute docker-compose command in remote"

    ssh -p ${PORT} ${SERVER} "cd ${SERVICE_PATH} && docker-compose ${COMMANDS}"
    exit 0
fi


print_help >&2
print_error "unknown command: $COMMAND"
exit 1
