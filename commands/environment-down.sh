#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    $(basename $0)

DESCRIPTION:
    Terminates an environment and all services running in it.

SYNOPSIS:
    $(basename $0)
    --project <value>
    --environment <value>
    --account <value>
    --vpc <value>
    --instance-subnets <value>
    --alb-subnets <value>
    [--template <value>]
    [--region <value>]

OPTIONS:
    --project (string)
        The name of the project. The cloudformation stack that is created by
        $(basename $0) will be <project>-<environment>. If this value is not
        provided the environment variable PROJECT will be used.

    --environment (string)
        The name of the environment. The cloudformation stack that is created by
        $(basename $0) will be <project>-<environment>. If this value is not
        provided the environment variable ENVIRONMENT will be used.

    --template (string)
        Path to the cloudformation template to deploy. If no value is provided
        the environment variable TEMPLATE_FILE will be used, otherwise the
        default ./infrastructure/stack.yaml will be used

    --region (string)
        The AWS region to deploy to. If this value is not provided the
        environment variable AWS_REGION will be used, or the default value of
        ap-southeast-2
EOF
    exit
}

set -e -o pipefail
trap 'errorTrap ${LINENO}' ERR

#-------------------------------------------------------------------------------
# Defaults
#
# These defaults can be overriden for each environment in
# ./<environment>.env
#-------------------------------------------------------------------------------
: ${AWS_REGION:="ap-southeast-2"}
: ${TEMPLATE_FILE:=".ecso/infrastructure/templates/stack.yaml"}
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
        --project)
            OPT_PROJECT="$2"
            shift
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift
            ;;
        --region)
            OPT_AWS_REGION="$2"
            shift
            ;;
        --force)
            FORCE=1
            ;;
        *)
            # unknown option
            ;;
    esac
    shift # past argument or value
done

: ${FORCE:?"ERROR: You must set the --force flag to terminate an environment"}
: ${ENVIRONMENT:?"ERROR: Environment name not provided"}

bannerBlue "Terminating ${ENVIRONMENT} environment"

. "./.ecso/project.conf"

conf="./.ecso/infrastructure/$ENVIRONMENT.env"

if [ -f "$conf" ]; then
    info "Loading environment configuration from ${conf}"
    . "$conf"
else
    warn "No environment configuration found at ${conf}"
fi

#-------------------------------------------------------------------------------
# Set options, falling back to env vars if option values are not provided on
# the cli
#-------------------------------------------------------------------------------
PROJECT=${OPT_PROJECT:-$PROJECT}
AWS_REGION=${OPT_AWS_REGION:-$AWS_REGION}

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${PROJECT:?"ERROR: Project name not provided"}
: ${AWS_REGION:?"ERROR: Region not provided"}

CLUSTER_NAME=$PROJECT-$ENVIRONMENT

services=$(find .ecso/services -maxdepth 1 -mindepth 1 -type d)

info "Teminating services..."

for service in .ecso/services/*
do
    svc=$(basename $service)

    ./service-down.sh \
        --service $svc \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION
done

info "Deleting cloudformation stack ${CLUSTER_NAME}..."

aws cloudformation delete-stack \
    --stack-name $CLUSTER_NAME \
    --region $AWS_REGION

aws cloudformation wait stack-delete-complete \
    --stack-name $CLUSTER_NAME \
    --region $AWS_REGION

bannerGreen "Successfully terminated $ENVIRONMENT environment"
