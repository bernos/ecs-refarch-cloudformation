#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    $(basename $0)

DESCRIPTION:
    Terminates a running ecs service

SYNOPSIS:
    $(basename $0)
    --cluster <value>
    [--region <value>]
    service

OPTIONS:
    --cluster (string)
        The cluster to deploy to. There must also be a cloudformation stack
        whose name matches the cluster name. This stack must also have an output
        VPC, which contains the ID of the VPC containing the cluster. If no
        value is provided, the CLUSTER_NAME environment variable will be used.

    --region (string)
        The AWS region to deploy to. Defaults to ap-southeast-2. If no value is
        provided, the AWS_REGION environment variable will be used.

EOF
    exit
}

set -e -o pipefail
trap 'errorTrap ${LINENO}' ERR

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
: ${AWS_REGION:="ap-southeast-2"}
: ${ECSO_DIR:="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" && pwd )"}

#-------------------------------------------------------------------------------
# Includes
#-------------------------------------------------------------------------------
. "${ECSO_DIR}/lib/common.sh"

#-------------------------------------------------------------------------------
# Source the ecso project configuration
#-------------------------------------------------------------------------------
if ! [ -f "./.ecso/project.conf" ]; then
    error "The current directory does not appear to contain an ecso project. Run ecso init first."
else
    . "./.ecso/project.conf"
fi

#-------------------------------------------------------------------------------
# Parse cli options
#-------------------------------------------------------------------------------
while [[ $# > 1 ]]
do
    key="$1"

    case $key in
        --environment) ENVIRONMENT="$2"; shift;;
        --cluster) OPT_CLUSTER_NAME="$2"; shift;;
        --region) OPT_AWS_REGION="$2"; shift;;
        *);;
    esac
    shift
done

[ "$1" == "help" ] && usage

SERVICE_NAME=$1
CLUSTER_NAME=${OPT_CLUSTER_NAME:-$CLUSTER_NAME}
AWS_REGION=${OPT_AWS_REGION:-$AWS_REGION}
SERVICE_STACK_NAME=$CLUSTER_NAME-$SERVICE_NAME
COMPOSE_FILE=${COMPOSE_FILE:-./services/$SERVICE_NAME/docker-compose.yaml}

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${SERVICE_NAME:?"ERROR: Service name not provided."}
: ${ENVIRONMENT:?"ERROR: Environment name not provided."}
: ${AWS_REGION:?"ERROR: No region provided."}
: ${CLUSTER_NAME:?"ERROR: No cluster name provided."}

#-------------------------------------------------------------------------------

bannerBlue "Terminating service ${SERVICE_NAME} in the ${ENVIRONMENT} environment"

#-------------------------------------------------------------------------------
# Export outputs from the cluster cfn stack as env vars
#-------------------------------------------------------------------------------
exportStackOutputs $CLUSTER_NAME
exportStackOutputs $SERVICE_STACK_NAME

#-------------------------------------------------------------------------------
# Bring the ecs service down
#-------------------------------------------------------------------------------
servicecount=$(getServiceCount $SERVICE_NAME $CLUSTER_NAME $AWS_REGION)

if [ "$servicecount" != "0" ]; then
    if [ -f "$COMPOSE_FILE" ]; then
        info "Removing service with ecs-cli compose..." && echo ""

        ecs-cli configure \
                --region $AWS_REGION \
                --compose-project-name-prefix "" \
                --compose-service-name-prefix "" \
                --cluster $CLUSTER_NAME

        ecs-cli compose \
            --file "$COMPOSE_FILE" \
            --project-name $SERVICE_NAME \
            service rm

        echo ""
    fi
fi

#-------------------------------------------------------------------------------
# Delete the service cfn stack
#-------------------------------------------------------------------------------
deleteStack $SERVICE_STACK_NAME $AWS_REGION

bannerGreen "Service $SERVICE_NAME was successfully terminated."
