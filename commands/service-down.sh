#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    $(basename $0)

DESCRIPTION:
    Terminates a running ecs service

SYNOPSIS:
    $(basename $0)
    --service <value>
    --cluster <value>
    [--region <value>]

OPTIONS:
    --service (string)
        The service to deploy. There must be a folder at ./services/<service>
        which contains a docker-compose.yaml file. and optional resources.yaml
        file. If no value is provided, the SERVICE_NAME environment variable
        will be used.

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

#-------------------------------------------------------------------------------
# Defaults
#
# These defaults can be overriden for each environment in
# ./services/<service>/<environment>.env
#-------------------------------------------------------------------------------
: ${AWS_REGION:="ap-southeast-2"}
: ${ECSO_DIR:="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}

#-------------------------------------------------------------------------------
# Includes
#-------------------------------------------------------------------------------
. "${ECSO_DIR}/lib/common.sh"

#-------------------------------------------------------------------------------
# Parse cli options
#-------------------------------------------------------------------------------
while [[ $# > 0 ]]
do
    key="$1"

    case $key in
        help)
            usage
            ;;
        --service)
            SERVICE_NAME="$2"
            shift
            ;;
        --cluster)
            OPT_CLUSTER_NAME="$2"
            shift
            ;;
        --region)
            OPT_AWS_REGION="$2"
            shift
            ;;
        *)
            # unknown option
            ;;
    esac
    shift # past argument or value
done

#-------------------------------------------------------------------------------
# Set options, falling back to env vars if option values are not provided on
# the cli
#-------------------------------------------------------------------------------
CLUSTER_NAME=${OPT_CLUSTER_NAME:-$CLUSTER_NAME}
AWS_REGION=${OPT_AWS_REGION:-$AWS_REGION}

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${SERVICE_NAME:?"ERROR: Service name not provided."}
: ${AWS_REGION:?"ERROR: No region provided."}
: ${CLUSTER_NAME:?"ERROR: No cluster name provided."}

SERVICE_STACK_NAME=$CLUSTER_NAME-$SERVICE_NAME
COMPOSE_FILE=${COMPOSE_FILE:-./services/$SERVICE_NAME/docker-compose.yaml}

#-------------------------------------------------------------------------------

set -e -o pipefail
trap 'errorTrap ${LINENO}' ERR

info "Terminating service $SERVICE_NAME..."

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

info "Service $SERVICE_NAME was successfully terminated."
