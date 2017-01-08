
errorTrap() {
    error "Unknown error on line ${1}"
}

getStackCount() {
    local stackname=$1
    local region=${2:-$AWS_REGION}

    aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE \
        --region $region \
        --query "length(StackSummaries[?StackName == '$stackname'])"
}

getStackId() {
    local stackname=$1
    local region=${2:-$AWS_REGION}

    aws cloudformation describe-stacks \
        --stack-name $stackname \
        --region $region \
        --query "Stacks[0].StackId" \
        --output text
}

getServiceCount() {
    local servicename=$1
    local cluster=$2
    local region=${3:-$AWS_REGION}

    aws ecs describe-services \
        --cluster $cluster \
        --services $servicename \
        --query "length(services[?status == 'ACTIVE'])" \
        --region $region
}

getStackConsoleUrl() {
    local stackname=$1
    local region=${2:-$AWS_REGION}
    local base="https://${region}.console.aws.amazon.com"

    echo "${base}/cloudformation/home?region=${region}#/stack/detail?stackId=$(getStackId $stackname $region)"
}

getECSClusterConsoleUrl() {
    local cluster=$1
    local region=${2:-$AWS_REGION}
    local base="https://${region}.console.aws.amazon.com"

    echo "${base}/ecs/home?region=${region}#/clusters/${cluster}/services"
}

getECSServiceConsoleUrl() {
    local service=$1
    local cluster=$2
    local region=${3:-$AWS_REGION}
    local base="https://${region}.console.aws.amazon.com"

    echo "${base}/ecs/home?region=${region}#/clusters/${cluster}/services/${service}/tasks"
}

exportStackOutputs() {
    local stackname=$1
    local region=${2:-$AWS_REGION}
    local count=$(getStackCount $stackname $region)

    info "Adding outputs from the ${stackname} cloudformation stack to the current shell."

    if [ "$count" != "0" ]; then
        local OUTPUTS=$(aws cloudformation describe-stacks \
                            --stack-name $stackname \
                            --region $region \
                            --query "Stacks[].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" \
                            --output text &2>1)

        echo ""

        while read line
        do
            if [ -n "$line" ]; then
                name=`echo $line | cut -d' ' -f1`
                value=`echo $line | cut -d' ' -f2`

                printf "Setting ${name}=${value}\n"

                export $name=$value
            fi
        done <<< "$(echo -e "$OUTPUTS")"
    else
        warn "Stack ${stackname} was not found."
    fi

    echo ""
}

deleteStack() {
    local stackname=$1
    local region=${2:-$AWS_REGION}
    local count=$(getStackCount $stackname $region)

    if [ "$count" != "0" ]; then
        info "Deleting cloudformation stack ${stackname}..."

        aws cloudformation delete-stack \
            --stack-name $stackname \
            --region $region

        aws cloudformation wait stack-delete-complete \
            --stack-name $stackname \
            --region $region
    fi
}

_red='\33[0;31m'
_redl='\33[1;31m'
_green='\33[0;32m'
_greenl='\33[1;32m'
_orange='\33[0;33m'
_orangel='\33[1;33m'
_blue='\33[0;34m'
_bluel='\33[1;34m'
_bold='\33[1m'
_nc='\33[0m'

bannerBlue() {
    printf "\n${_bluel}%s${_nc}\n\n" "${1}"
}

bannerGreen() {
    printf "\n${_greenl}%s${_nc}\n\n" "${1}"
}

info() {
    printf "${_bold}info:${_nc}  %s\n" "${1}"
}

warn() {
    printf "${_orangel}warn:${_orange}  %s${_nc}\n" "${1}"
}

error() {
    printf "\n${_redl}error:${_red} %s${_nc}\n\n" "${1}"
    exit 1
}

dt() {
    printf "  ${_bold}%s:${_nc}\n" "${1}"
    printf "    %s\n\n" "${2}"
}

blue() {
    printc $_blue "$@"

    # Black        0;30     Dark Gray     1;30
    # Red          0;31     Light Red     1;31
    # Green        0;32     Light Green   1;32
    # Brown/Orange 0;33     Yellow        1;33
    # Blue         0;34     Light Blue    1;34
    # Purple       0;35     Light Purple  1;35
    # Cyan         0;36     Light Cyan    1;36
    # Light Gray   0;37     White         1;37


    # RED='\033[0;31m'
    # NC='\033[0m' # No Color
    # printf "I ${RED}love${NC} Stack Overflow\n"
}

orange() { printc $_orange "$@"; }
green()  { printc $_green "$@"; }
red()    { printc $_red "$@"; }

printc() {
    local color=$1
    local fmt=$2

    shift
    shift

    printf "${color}$fmt${_nc}" $@
}
