#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    add-environment 

DESCRIPTION:
    Adds a new ecso managed environment

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
    --project (string)
        The name of the project. If this value is not provided the environment
        variable PROJECT will be used.

    --environment (string)
        The name of the environment to add. If this value is not provided the
        environment variable ENVIRONMENT will be used.

    --account (integer)
        The id of the AWS account to add the environment to. If this value is
        not provided the environment variable AWS_ACCOUNT_ID will be used.

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
# Validate options
#-------------------------------------------------------------------------------
: ${OPT_ENVIRONMENT:?"ERROR: Environment name not provided"}
: ${OPT_AWS_ACCOUNT_ID:?"ERROR: AWS Account ID not provided."}
: ${OPT_VPC_ID:?"ERROR: VPC ID not provided."}
: ${OPT_INSTANCE_SUBNETS:?"ERROR: Instance subnets not provided."}
: ${OPT_ALB_SUBNETS:?"ERROR: ALB subnets not provided."}
: ${OPT_AWS_REGION:?"ERROR: Region not provided"}

#-------------------------------------------------------------------------------
# Ensure we are in an ecso project, and that there is not already an
# environment with the same name defined
#-------------------------------------------------------------------------------
ENV_CONFIG="./.ecs/environments/${OPT_ENVIRONMENT}/config.env"

if ! [ -f "./.ecso/project.conf" ]; then
    error "This dir does not appear to be in an ecso project. Run ecso init first."
elif [ -f "${ENV_CONFIG}" ]; then
    error "This project already contains and environment named ${OPT_ENVIRONMENT}"
fi

. "./.ecso/project.conf"

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

bannerGreen "Successfully added environment ${OPT_ENVIRONMENT}. Run 'ecso environment-up' to deploy the environment infrastructure."
