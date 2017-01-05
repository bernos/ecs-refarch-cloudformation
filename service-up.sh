#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    $(basename $0)

DESCRIPTION:
    Deploys a service to an ecs cluster from a Docker Compose file. There must
    be a folder located at ./services/<service-name> containing a
    docker-compose.yaml file, and an optional resources.yaml cloudformation
    template. If resources.yaml is found, it will be deployed before the service
    is deployed to the cluster, and all cloudformation stack outputs will be
    available as environment variables in the docker-compose.yaml file

    $(basename $0) also expects that the cluster to which it is deploy to was
    created with cloudformation, and that there exists a cloudformation stack
    whose name matches the cluster name. It also expects that this
    cloudformation stack outputs the VPC id of the cluster, as an output named
    VPC

SYNOPSIS:
    $(basename $0)
    --service <value>
    --cluster <value>
    --environment <value>
    [--count <value>]
    [--route <value>]
    [--container <value>]
    [--port <value>]
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

    --environment (string)
        The name of the environment to deploy to. If a file exists at
        ./services/<service>/<environment>.env it will be sourced. If no value
        is provided, the ENVIRONMENT environment variable will be used.

    --count (integer)
        The desired count for the service. If no value is provided the
        DESIRED_COUNT environment variable is used. Defaults to 1.

    --route (string)
        If provided, the service will be registered with the cluster load
        balancer at this route. If route is set, --port and --container must
        also be set. If no value is provided, the ROUTE_PATH environment
        variable will be used.

    --container (string)
        The name of the container in the docker-compose.yaml file to register
        with the load balancer. If this option is set, --route and --port must
        also be set. If no value is provided, the CONTAINER_NAME environment
        variable will be used.

    --port (integer)
        The container port to register with the load balancer. If this option is
        set, --route and --container must also be set. If no value is provided
        the CONTAINER_PORT environment variable will be used.

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
: ${DESIRED_COUNT:=1}
: ${AWS_REGION:="ap-southeast-2"}

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
        --environment)
            ENVIRONMENT="$2"
            shift
            ;;
        --cluster)
            OPT_CLUSTER_NAME="$2"
            shift
            ;;
        --count)
            OPT_DESIRED_COUNT="$2"
            shift
            ;;
        --route)
            OPT_ROUTE_PATH="$2"
            shift
            ;;
        --container)
            OPT_CONTAINER_NAME="$2"
            shift
            ;;
        --port)
            OPT_CONTAINER_PORT="$2"
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

: ${ENVIRONMENT:?"ERROR: Environment name not provided."}
: ${SERVICE_NAME:?"ERROR: Service name not provided."}

conf="./services/$SERVICE_NAME/$ENVIRONMENT.env"

if [ -f "$conf" ]; then
    . "$conf"
fi

#-------------------------------------------------------------------------------
# Set options, falling back to env vars if option values are not provided on
# the cli
#-------------------------------------------------------------------------------
CLUSTER_NAME=${OPT_CLUSTER_NAME:-$CLUSTER_NAME}
DESIRED_COUNT=${OPT_DESIRED_COUNT:-$DESIRED_COUNT}
ROUTE_PATH=${OPT_ROUTE_PATH:-$ROUTE_PATH}
CONTAINER_NAME=${OPT_CONTAINER_NAME:-$CONTAINER_NAME}
CONTAINER_PORT=${OPT_CONTAINER_PORT:-$CONTAINER_PORT}
AWS_REGION=${OPT_AWS_REGION:-$AWS_REGION}

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${AWS_REGION:?"ERROR: No region provided."}
: ${CLUSTER_NAME:?"ERROR: No cluster name provided."}
: ${DESIRED_COUNT:?"ERROR: No desired count provided."}

# Validate options that are only required if we are registering the service
# with a load balancer
if [ -n "$ROUTE_PATH" ]; then
    : ${CONTAINER_NAME:?"ERROR: No container name provided."}
    : ${CONTAINER_PORT:?"ERROR: No container port provided."}
fi

TASK_NAME="$CLUSTER_NAME-$SERVICE_NAME"
SERVICE_STACK_NAME=$CLUSTER_NAME-$SERVICE_NAME

#-------------------------------------------------------------------------------
# Exports all the outputs of a cloudformation stack as environment variables
#-------------------------------------------------------------------------------
exportStackOutputs() {
    local OUTPUTS=$(aws cloudformation describe-stacks \
                  --stack-name $1 \
                  --region $AWS_REGION \
                  --query "Stacks[].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}" \
                  --output text)

    while read line
    do
        name=`echo $line | cut -d' ' -f1`
        value=`echo $line | cut -d' ' -f2`

        export $name=$value
    done <<< "$(echo -e "$OUTPUTS")"
}

#-------------------------------------------------------------------------------

set -e

#-------------------------------------------------------------------------------
# Export outputs from the cluster cfn stack as env vars
#-------------------------------------------------------------------------------
exportStackOutputs $CLUSTER_NAME

#-------------------------------------------------------------------------------
# Deploy the service resources cfn stack
#-------------------------------------------------------------------------------
if [ -n "$ROUTE_PATH" ]; then
    aws cloudformation deploy \
        --stack-name $SERVICE_STACK_NAME \
        --parameter-overrides VPC=$VPC Listener=$Listener Path=$ROUTE_PATH \
        --template-file services/$SERVICE_NAME/resources.yaml \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM \
        --region $AWS_REGION
else
    aws cloudformation deploy \
        --stack-name $SERVICE_STACK_NAME \
        --template-file services/$SERVICE_NAME/resources.yaml \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM \
        --region $AWS_REGION
fi

exportStackOutputs $SERVICE_STACK_NAME

#-------------------------------------------------------------------------------
# Create the task definition using ecs-cli compose
#-------------------------------------------------------------------------------
ecs-cli compose \
    --file services/$SERVICE_NAME/docker-compose.yaml \
    --project-name $TASK_NAME \
    create

servicecount=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --query "length(services[?status == 'ACTIVE'])" \
    --region $AWS_REGION)

#-------------------------------------------------------------------------------
# Create/Update the service
#-------------------------------------------------------------------------------
if [ "$servicecount" = "0" ]; then
    echo "Creating service $SERVICE_NAME"

    if [ -n "$ROUTE_PATH" ]; then
        aws ecs create-service \
            --cluster $CLUSTER_NAME \
            --service-name $SERVICE_NAME \
            --role $ServiceRole \
            --task-definition $TASK_NAME \
            --desired-count $DESIRED_COUNT \
            --load-balancers targetGroupArn=$TargetGroup,containerName=$CONTAINER_NAME,containerPort=$CONTAINER_PORT \
            --region $AWS_REGION
    else
        aws ecs create-service \
            --cluster $CLUSTER_NAME \
            --service-name $SERVICE_NAME \
            --role $ServiceRole \
            --task-definition $TASK_NAME \
            --desired-count $DESIRED_COUNT \
            --region $AWS_REGION
    fi
else
    echo "Updating service $SERVICE_NAME"

    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --task-definition $TASK_NAME \
        --desired-count $DESIRED_COUNT \
        --region $AWS_REGION
fi

#-------------------------------------------------------------------------------
# Wait for deployment to complete
#-------------------------------------------------------------------------------
echo "Waiting for service to be stable..."

aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION
