#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    add-environment

DESCRIPTION:
    Adds a new ecso managed environment to the project

SYNOPSIS:
    ecso.sh add-environment
    --account <value>
    --vpc <value>
    --instance-subnets <value>
    --alb-subnets <value>
    [--region <value>]
    <name>

OPTIONS:
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

#-------------------------------------------------------------------------------
# Includes
#-------------------------------------------------------------------------------
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)/lib/common.sh" && assertProject

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
: ${CURRENT_AWS_ACCOUNT:="$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null)"}

#-------------------------------------------------------------------------------
# Parse cli options
#-------------------------------------------------------------------------------
while [[ $# > 1 ]]
do
    key="$1"

    case $key in
        --environment)      OPT_ENVIRONMENT="$2";      shift;;
        --account)          OPT_AWS_ACCOUNT_ID="$2";   shift;;
        --vpc)              OPT_VPC_ID="$2";           shift;;
        --instance-subnets) OPT_INSTANCE_SUBNETS="$2"; shift;;
        --alb-subnets)      OPT_ALB_SUBNETS="$2";      shift;;
        --region)           OPT_AWS_REGION="$2";       shift;;
        *);;
    esac
    shift
done

[ "$1" == "help" ] && usage

OPT_ENVIRONMENT=$1

: ${OPT_ENVIRONMENT:?"ERROR: Environment name not provided"}

# Ensure that there is not already an environment with the same name defined
# before wasting time asking for more options
ENV_CONFIG="./.ecso/environments/${OPT_ENVIRONMENT}/config.env"
ENV_ACTIVATE="./.ecso/environments/${OPT_ENVIRONMENT}/activate"

if [ -f "${ENV_CONFIG}" ]; then
    error "This project already contains and environment named ${OPT_ENVIRONMENT}"
fi

bannerBlue "Adding environment ${OPT_ENVIRONMENT} to ${PROJECT}"

#-------------------------------------------------------------------------------
# Prompt for any missing options
#-------------------------------------------------------------------------------
# AWS Account ID
if [ -z "$OPT_AWS_ACCOUNT_ID" ]; then
    if [ -z "$CURRENT_AWS_ACCOUNT" ]; then
        prompt "Enter the ID of the AWS account to create the environment in"
    else
        prompt "Enter the ID of the AWS account to create the environment in ($CURRENT_AWS_ACCOUNT)"
    fi

    read OPT_AWS_ACCOUNT_ID

    : ${OPT_AWS_ACCOUNT_ID:=$CURRENT_AWS_ACCOUNT}
fi

# AWS Region
if [ -z "$OPT_AWS_REGION" ]; then
    prompt "Enter the AWS region to create the environment in (ap-southeast-2)"
    read OPT_AWS_REGION
    : ${OPT_AWS_REGION:="ap-southeast-2"}
fi

# If we have default settings for the selected AWS account ID, offer to use
# them, rather than prompting for everything
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

# VPC ID
if [ -z "$OPT_VPC_ID" ]; then
    prompt "Enter the ID of the VPC to create the environment in"
    read OPT_VPC_ID
fi

# Cluster ec2 instance subnets
if [ -z "$OPT_INSTANCE_SUBNETS" ]; then
    prompt "Enter the subnets to add your ecs container instances to (subnet-abc,subnet-def)"
    read OPT_INSTANCE_SUBNETS
fi

# Load balancer subnets
if [ -z "$OPT_ALB_SUBNETS" ]; then
    prompt "Enter the subnets to add your cluster loadbalancer to (subnet-abc,subnet-def)"
    read OPT_ALB_SUBNETS
fi

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${OPT_AWS_ACCOUNT_ID:?"ERROR: AWS Account ID not provided."}
: ${OPT_VPC_ID:?"ERROR: VPC ID not provided."}
: ${OPT_INSTANCE_SUBNETS:?"ERROR: Instance subnets not provided."}
: ${OPT_ALB_SUBNETS:?"ERROR: ALB subnets not provided."}
: ${OPT_AWS_REGION:?"ERROR: Region not provided"}


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

    function deactivate() {
        if [ -n "\$ECSO_OLD_PS1" ]; then
            export PS1="\$ECSO_OLD_PS1"
        fi

        unset AWS_ACCOUNT_ID
        unset VPC_ID
        unset INSTANCE_SUBNETS
        unset ALB_SUBNETS
        unset AWS_REGION
    }

    # configure so that ecs-cli commands will work
    # against our cluster. Set all compose prefixes to empty
    # strings to give us full control over naming of our ecs
    # compose services
    export COMPOSE_PROJECT_NAME=$PROJECT

    if [ -f "~/.ecs/config" ]; then
        rm ~/.ecs/config
    fi

    ecs-cli configure \\
        --region $AWS_REGION \\
        --compose-project-name-prefix "" \\
        --compose-service-name-prefix "" \\
        --cluster $CLUSTER_NAME

    printf "\33[0;32mCurrent ecso environment set to \33[1;32m${OPT_ENVIRONMENT}\33[0m\n\n"
    printf "\33[0;32mRun \33[1;32mdeactivate\33[0;32m to leave this ecso environment\33[0m\n\n"

    if [ -z "\$ECSO_OLD_PS1" ]; then
        export ECSO_OLD_PS1="\$PS1"
    fi

    export PS1="\${PS1}\\[\$(tput setaf 2)\\][ecso:\$ENVIRONMENT]\\[\$(tput sgr0)\\]: "
fi
EOF

bannerGreen "Successfully added environment ${OPT_ENVIRONMENT}."

printf "  Run ${_bold}'source ${ENV_ACTIVATE}'${_nc} to switch ecso to the new environment.\n"
printf "  Run ${_bold}'ecso environment-up'${_nc} to deploy the environment infrastructure.\n\n"
