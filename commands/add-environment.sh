#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    add-environment

DESCRIPTION:
    Adds a new ecso managed environment to the project

SYNOPSIS:
    ecso.sh add-environment
    --project <value>
    --environment <value>
    --account <value>
    --vpc <value>
    --instance-subnets <value>
    --alb-subnets <value>
    [--region <value>]

OPTIONS:
    --environment (string)
        The name of the environment to add.

    --account (integer)
        The id of the AWS account to add the environment to.

    --vpc (string)
        The id of the VPC to add the environment to. If this value is not
        provided the environment variable VPC_ID will be used.

    --instance-subnets (string)
        The ids of subnets to deploy the cluster instances and to.
        If this value is not provided the environment variable SUBNETS will be
        used.

    --alb-subnets (string)
        The ids of subnets to deploy the application load balancer to.
        If this value is not provided the environment variable SUBNETS will be
        used.

    --region (string)
        The AWS region to add the environment to. If this value is not provided
        the environment variable AWS_REGION will be used, or the default value
        of ap-southeast-2
EOF
    exit
}

set -e -o pipefail
trap 'errorTrap ${LINENO}' ERR

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
: ${AWS_REGION:="ap-southeast-2"}
: ${ECSO_DIR:="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"}
: ${CURRENT_AWS_ACCOUNT:="$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null)"}

#-------------------------------------------------------------------------------
# Includes
#-------------------------------------------------------------------------------
. "${ECSO_DIR}/common.sh"

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
        --environment)
            OPT_ENVIRONMENT="$2"
            shift
            ;;
        --account)
            OPT_AWS_ACCOUNT_ID="$2"
            shift
            ;;
        --vpc)
            OPT_VPC_ID="$2"
            shift
            ;;
        --instance-subnets)
            OPT_INSTANCE_SUBNETS="$2"
            shift
            ;;
        --alb-subnets)
            OPT_ALB_SUBNETS="$2"
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
# Source the ecso project configuration
#-------------------------------------------------------------------------------
if ! [ -f "./.ecso/project.conf" ]; then
    error "The current directory does not appear to contain an ecso project. Run ecso init first."
else
    . "./.ecso/project.conf"
fi

#-------------------------------------------------------------------------------
# Prompt for any missing options
#-------------------------------------------------------------------------------
if [ -z "$OPT_ENVIRONMENT" ]; then
    prompt "Enter a name for the environment (dev)"
    read OPT_ENVIRONMENT
    : ${OPT_ENVIRONMENT:="dev"}
fi

# Ensure that there is not already an environment with the same name defined
# before wasting time asking for more options
ENV_CONFIG="./.ecso/environments/${OPT_ENVIRONMENT}/config.env"
ENV_ACTIVATE="./.ecso/environments/${OPT_ENVIRONMENT}/activate"

if [ -f "${ENV_CONFIG}" ]; then
    error "This project already contains and environment named ${OPT_ENVIRONMENT}"
fi

if [ -z "$OPT_AWS_ACCOUNT_ID" ]; then
    if [ -z "$CURRENT_AWS_ACCOUNT" ]; then
        prompt "Enter the ID of the AWS account to create the environment in"
    else
        prompt "Enter the ID of the AWS account to create the environment in ($CURRENT_AWS_ACCOUNT)"
    fi

    read OPT_AWS_ACCOUNT_ID

    : ${OPT_AWS_ACCOUNT_ID:=$CURRENT_AWS_ACCOUNT}
fi

if [ -z "$OPT_AWS_REGION" ]; then
    prompt "Enter the AWS region to create the environment in (ap-southeast-2)"
    read OPT_AWS_REGION
    : ${OPT_AWS_REGION:="ap-southeast-2"}
fi

if [ -f "${ECSO_DIR}/accounts/${OPT_AWS_ACCOUNT_ID}.env" ]; then
    printf "${_bold}Would you like to use the default VPC and subnets for AWS account ${OPT_AWS_ACCOUNT_ID}?${_nc}\n"

    select use_defaults in "Yes" "No"; do
        if [ "$use_defaults" = "Yes" ]; then
           . "${ECSO_DIR}/accounts/${OPT_AWS_ACCOUNT_ID}.env"

           echo ""

           info "Using vpc ${OPT_VPC_ID}"
           info "Using instance subnets ${OPT_INSTANCE_SUBNETS}"
           info "Using load balancer subnets ${OPT_ALB_SUBNETS}"
        fi
        break
    done

fi

if [ -z "$OPT_VPC_ID" ]; then
    prompt "Enter the ID of the VPC to create the environment in"
    read OPT_VPC_ID
fi

if [ -z "$OPT_INSTANCE_SUBNETS" ]; then
    prompt "Enter the subnets to add your ecs container instances to (subnet-abc,subnet-def)"
    read OPT_INSTANCE_SUBNETS
fi

if [ -z "$OPT_ALB_SUBNETS" ]; then
    prompt "Enter the subnets to add your cluster loadbalancer to (subnet-abc,subnet-def)"
    read OPT_ALB_SUBNETS
fi

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${OPT_ENVIRONMENT:?"ERROR: Environment name not provided"}
: ${OPT_AWS_ACCOUNT_ID:?"ERROR: AWS Account ID not provided."}
: ${OPT_VPC_ID:?"ERROR: VPC ID not provided."}
: ${OPT_INSTANCE_SUBNETS:?"ERROR: Instance subnets not provided."}
: ${OPT_ALB_SUBNETS:?"ERROR: ALB subnets not provided."}
: ${OPT_AWS_REGION:?"ERROR: Region not provided"}

bannerBlue "Adding environment ${OPT_ENVIRONMENT} to ${PROJECT}"

mkdir -p $(dirname "${ENV_CONFIG}")

info "Creating environment config at ${ENV_CONFIG}"

cat << EOF > "${ENV_CONFIG}"
export AWS_ACCOUNT_ID=${OPT_AWS_ACCOUNT_ID}
export VPC_ID=${OPT_VPC_ID}
export INSTANCE_SUBNETS=${OPT_INSTANCE_SUBNETS}
export ALB_SUBNETS=${OPT_ALB_SUBNETS}
export AWS_REGION=${OPT_AWS_REGION}
EOF

info "Creating environment activation script at ${ENV_ACTIVATE}"

cat <<EOF > "${ENV_ACTIVATE}"
if ! [ -f "${ENV_CONFIG}" ]; then
    echo "Error: no environment configuration found at ${ENV_CONFIG}"
else
    export PROJECT=${PROJECT}
    export ENVIRONMENT=${OPT_ENVIRONMENT}
    export CLUSTER_NAME=${PROJECT}-${OPT_ENVIRONMENT}

    . "${ENV_CONFIG}"

    # configure so that ecs-cli commands will work
    # against our cluster. Set all compose prefixes to empty
    # strings to give us full control over naming of our ecs
    # compose services
    export COMPOSE_PROJECT_NAME=$PROJECT

    rm ~/.ecs/config

    ecs-cli configure \\
        --region \$AWS_REGION \\
        --compose-project-name-prefix "" \\
        --compose-service-name-prefix "" \\
        --cluster $CLUSTER_NAME

    printf "\33[0;32mCurrent ecso environment set to \33[1;32m${OPT_ENVIRONMENT}\33[0m\n\n"
fi
EOF

bannerGreen "Successfully added environment ${OPT_ENVIRONMENT}."

printf "  Run ${_bold}'source ${ENV_ACTIVATE}'${_nc} to switch ecso to the new environment.\n"
printf "  Run ${_bold}'ecso environment-up'${_nc} to deploy the environment infrastructure.\n\n"
