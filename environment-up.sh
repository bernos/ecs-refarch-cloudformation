#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    $(basename $0)

DESCRIPTION:
    Creates an environment containing an ecs cluster and related resources using
    cloudformation.

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

    --account (integer)
        The id of the AWS account to deploy to. If this value is not provided
        the environment variable AWS_ACCOUNT_ID will be used.

    --vpc (string)
        The id of the VPC to deploy to. If this value is not provided the
        environment variable VPC_ID will be used.

    --instance-subnets (string)
        The ids of subnets to deploy the cluster instances and to.
        If this value is not provided the environment variable SUBNETS will be
        used.

    --alb-subnets (string)
        The ids of subnets to deploy the application load balancer to.
        If this value is not provided the environment variable SUBNETS will be
        used.

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

#-------------------------------------------------------------------------------
# Defaults
#
# These defaults can be overriden for each environment in
# ./<environment>.env
#-------------------------------------------------------------------------------
: ${AWS_REGION:="ap-southeast-2"}
: ${TEMPLATE_FILE:="infrastructure/stack.yaml"}

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

: ${ENVIRONMENT:?"ERROR: Environment name not provided"}

conf="./$ENVIRONMENT.env"

if [ -f "$conf" ]; then
    . "$conf"
fi

#-------------------------------------------------------------------------------
# Set options, falling back to env vars if option values are not provided on
# the cli
#-------------------------------------------------------------------------------
PROJECT=${OPT_PROJECT:-$PROJECT}
AWS_ACCOUNT_ID=${OPT_AWS_ACCOUNT_ID:-$AWS_ACCOUNT_ID}
VPC_ID=${OPT_VPC_ID:-$VPC_ID}
ALB_SUBNETS=${OPT_ALB_SUBNETS:-$ALB_SUBNETS}
INSTANCE_SUBNETS=${OPT_INSTANCE_SUBNETS:-$INSTANCE_SUBNETS}
AWS_REGION=${OPT_AWS_REGION:-$AWS_REGION}

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${PROJECT:?"ERROR: Project name not provided"}
: ${AWS_ACCOUNT_ID:?"ERROR: AWS Account ID not provided."}
: ${VPC_ID:?"ERROR: VPC ID not provided."}
: ${INSTANCE_SUBNETS:?"ERROR: Instance subnets not provided."}
: ${ALB_SUBNETS:?"ERROR: ALB subnets not provided."}
: ${AWS_REGION:?"ERROR: Region not provided"}

BUCKET=seek-ca-$AWS_REGION-$AWS_ACCOUNT_ID
CLUSTER_NAME=$PROJECT-$ENVIRONMENT

set -e

# Package up the main stack. We need to do the extra sed step to work
# around https://github.com/aws/aws-cli/issues/2314
aws cloudformation package \
    --template-file $TEMPLATE_FILE \
    --s3-bucket $BUCKET \
    --s3-prefix $CLUSTER_NAME/infrastructure | \
    sed 's/s3:\/\//https:\/\/s3.amazonaws.com\//g' > \
        /tmp/$CLUSTER_NAME-infrastructure.yaml

# Now deploy the main stack template
aws cloudformation deploy \
    --stack-name $CLUSTER_NAME \
    --parameter-overrides VPC=$VPC_ID InstanceSubnets=$INSTANCE_SUBNETS ALBSubnets=$ALB_SUBNETS \
    --template-file /tmp/$CLUSTER_NAME-infrastructure.yaml \
    --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM \
    --region $AWS_REGION
