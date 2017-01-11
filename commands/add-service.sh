#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    add-service

DESCRIPTION:
    Adds a new service to the project

SYNOPSIS:
    ecso.sh add-service
    --name <value>
    [--route <value>]
    [--route-to-container <value>]
    [--route-to-container-port <value>]
    [--desired-count <value>]

OPTIONS:
    --name (string)
        The name of the service to add

    --route (string)
        The url path to expose the service at.

    --route-to-container (string)
        The name of the container to register with the loadbalancer.

    --route-to-container-port (string)
        The container port to route to

    --desired-count (string)
        The number of instances of the service to run

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
: ${CURRENT_AWS_ACCOUNT:="$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null)"}
: ${DESIRED_COUNT:=2}

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
        --name)
            OPT_NAME="$2"
            shift
            ;;
        --route)
            OPT_ROUTE="$2"
            shift
            ;;
        --route-to-container)
            OPT_ROUTE_TO_CONTAINER="$2"
            shift
            ;;
        --route-to-container-port)
            OPT_ROUTE_TO_CONTAINER_PORT="$2"
            shift
            ;;
        --desired-count)
            OPT_DESIRED_COUNT="$2"
            shift
            ;;
        *)
            # unknown option
            ;;
    esac
    shift # past argument or value
done

#-------------------------------------------------------------------------------
# Source the ecso project configuration
#-------------------------------------------------------------------------------
if ! [ -f "./.ecso/project.conf" ]; then
    error "The current directory does not appear to contain an ecso project. Run ecso init first."
else
    . "./.ecso/project.conf"
fi

# TODO: Ensure that there is at least one environment defined for the project

#-------------------------------------------------------------------------------
# Prompt for any missing options
#-------------------------------------------------------------------------------
if [ -z "$OPT_NAME" ]; then
    prompt "Enter a name for the service"
    read OPT_NAME
fi

if [ -z "$OPT_ROUTE" ]; then
    printf "Is this a web service?\n"

    select is_web_service in "Yes" "No"; do
        if [ "$is_web_service" = "Yes" ]; then
            prompt "Enter the route to this service"
            read OPT_ROUTE

            prompt "Enter the name of the container to route to (${OPT_NAME})"
            read OPT_ROUTE_TO_CONTAINER

            : ${OPT_ROUTE_TO_CONTAINER:=$OPT_NAME}

            default_port=80

            prompt "Enter the container port to route to (${default_port})"
            read OPT_ROUTE_TO_CONTAINER_PORT

            : ${OPT_ROUTE_TO_CONTAINER_PORT:=$default_port}
        fi
        break
    done
fi

if [ -z "$OPT_DESIRED_COUNT" ]; then
    prompt "How many instances of the service would you like to run (2)"
    read OPT_DESIRED_COUNT
    : ${OPT_DESIRED_COUNT:=2}
fi

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${OPT_NAME:?"ERROR: Name is required"}
: ${OPT_DESIRED_COUNT:?"ERROR: Desired count is required"}

if [ -n "$OPT_ROUTE" ]; then
    : ${OPT_ROUTE_TO_CONTAINER:?"ERROR: No container to route to"}
    : ${OPT_ROUTE_TO_CONTAINER_PORT:?"ERROR: No container port to route to"}
fi

#-------------------------------------------------------------------------------
# Generate cloudformation template
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Generate env config files
#-------------------------------------------------------------------------------
# export ROUTE_PATH=/
# export ROUTE_TO_CONTAINER=nginx
# export ROUTE_TO_CONTAINER_PORT=80
# export DESIRED_COUNT=2
# export CLUSTER_NAME=ecs-refarch-sandbox

#-------------------------------------------------------------------------------
# Generate docker-compose file
#-------------------------------------------------------------------------------

