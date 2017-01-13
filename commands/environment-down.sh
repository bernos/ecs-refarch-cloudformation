#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    $(basename $0)

DESCRIPTION:
    Terminates an environment and all services running in it.

SYNOPSIS:
    $(basename $0)
    --force
    [--region <value>]
    <environment>

OPTIONS:
    --force
        Required in order to confirm that the environment should be terminated

    --region (string)
        The AWS region to deploy to. If this value is not provided the
        environment variable AWS_REGION will be used, or the default value of
        ap-southeast-2
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
: ${TEMPLATE_FILE:=".ecso/infrastructure/templates/stack.yaml"}

#-------------------------------------------------------------------------------
# Parse cli options
#-------------------------------------------------------------------------------
while [[ $# > 0 ]]
do
    key="$1"

    case $key in
        --region) OPT_AWS_REGION="$2"; shift;;
        --force) FORCE=1;;
        *) PARAM="$1";;
    esac
    shift
done

[ "$PARAM" == "help" ] && usage

ENVIRONMENT=${PARAM:-${ENVIRONMENT:?"ERROR: Environment name not provided"}}

bannerBlue "Terminating ${ENVIRONMENT} environment"

loadEnvironmentConfiguration ${ENVIRONMENT}

#-------------------------------------------------------------------------------
# Set options, falling back to env vars if option values are not provided on
# the cli
#-------------------------------------------------------------------------------
AWS_REGION=${OPT_AWS_REGION:-$AWS_REGION}
CLUSTER_NAME=$PROJECT-$ENVIRONMENT

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${PROJECT:?"ERROR: Project name not provided"}
: ${AWS_REGION:?"ERROR: Region not provided"}
: ${FORCE:?"ERROR: You must set the --force flag to terminate an environment"}

#-------------------------------------------------------------------------------
# Kill all services in the environment
#-------------------------------------------------------------------------------
info "Teminating services..."

for service in .ecso/services/*
do
    svc=$(basename $service)

    ${ECSO_DIR}/commands/service-down.sh \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION \
        $svc
done

#-------------------------------------------------------------------------------
# Delete the environment cloudformation stack
#-------------------------------------------------------------------------------
info "Deleting cloudformation stack ${CLUSTER_NAME}..."

aws cloudformation delete-stack \
    --stack-name $CLUSTER_NAME \
    --region $AWS_REGION

aws cloudformation wait stack-delete-complete \
    --stack-name $CLUSTER_NAME \
    --region $AWS_REGION

#-------------------------------------------------------------------------------
# Great success!
#-------------------------------------------------------------------------------
bannerGreen "Successfully terminated $ENVIRONMENT environment"
