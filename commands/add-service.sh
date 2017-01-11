#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    add-service

DESCRIPTION:
    Adds a new service to the project

SYNOPSIS:
    ecso.sh add-service
    [--route <value>]
    [--route-to-container <value>]
    [--route-to-container-port <value>]
    [--desired-count <value>]
    <name>

OPTIONS:
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

#-------------------------------------------------------------------------------
# Options
#-------------------------------------------------------------------------------
set -e -o pipefail
trap 'errorTrap ${LINENO}' ERR
export PS3=" > "

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
: ${ECSO_DIR:="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" && pwd )"}
: ${DESIRED_COUNT:=2}

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
        --route)                   OPT_ROUTE="$2";                   shift;;
        --route-to-container)      OPT_ROUTE_TO_CONTAINER="$2";      shift;;
        --route-to-container-port) OPT_ROUTE_TO_CONTAINER_PORT="$2"; shift;;
        --desired-count)           OPT_DESIRED_COUNT="$2";           shift;;
        *);; # unknown option
    esac
    shift # past argument or value
done

[ "$1" == "help" ] && usage

OPT_NAME=$1

: ${OPT_NAME:?"ERROR: Name is required"}

bannerBlue "Adding ${OPT_NAME} service"

#-------------------------------------------------------------------------------
# Prompt for any missing options
#-------------------------------------------------------------------------------
if [ -d "./ecso/services/${OPT_NAME}" ]; then
    error "This project already contains a service named ${OPT_NAME}"
fi

if [ -z "$OPT_DESIRED_COUNT" ]; then
    prompt "How many instances of the service would you like to run (2)"
    read OPT_DESIRED_COUNT
    : ${OPT_DESIRED_COUNT:=2}
fi

# If this is a web service, then we need to request a path, container and port
# to register with the loadbalancer
if [ -z "$OPT_ROUTE" ]; then
    printf "${_bold}Is this a web service?${_nc}\n"

    select is_web_service in "Yes" "No"; do
        if [ "$is_web_service" = "Yes" ]; then
            prompt "Enter the route to this service (/${OPT_NAME})"
            read OPT_ROUTE
            : ${OPT_ROUTE:="/${OPT_NAME}"}
        fi
        break
    done
fi

if [ -n "$OPT_ROUTE" ]; then

    if [ -z "$OPT_ROUTE_TO_CONTAINER" ]; then
        prompt "Enter the name of the container to route to (${OPT_NAME})"
        read OPT_ROUTE_TO_CONTAINER
        : ${OPT_ROUTE_TO_CONTAINER:=$OPT_NAME}
    fi

    if [ -z "$OPT_ROUTE_TO_CONTAINER_PORT" ]; then
        default_port=80
        prompt "Enter the container port to route to (${default_port})"
        read OPT_ROUTE_TO_CONTAINER_PORT
        : ${OPT_ROUTE_TO_CONTAINER_PORT:=$default_port}
    fi

fi


#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${OPT_DESIRED_COUNT:?"ERROR: Desired count is required"}

if [ -n "$OPT_ROUTE" ]; then
    : ${OPT_ROUTE_TO_CONTAINER:?"ERROR: No container to route to"}
    : ${OPT_ROUTE_TO_CONTAINER_PORT:?"ERROR: No container port to route to"}
fi

#-------------------------------------------------------------------------------

TEMPLATE_FILE="./.ecso/services/${OPT_NAME}/resources.yaml"
CONFIG_FILE="./services/${OPT_NAME}/config.env"
COMPOSE_FILE="./services/${OPT_NAME}/docker-compose.yaml"


mkdir -p \
    "$(dirname $TEMPLATE_FILE)" \
    "$(dirname $CONFIG_FILE)" \
    "$(dirname $COMPOSE_FILE)"

#-------------------------------------------------------------------------------
# Generate cloudformation template
#-------------------------------------------------------------------------------
info "Generating cloud formation template at ${TEMPLATE_FILE}"

cat << EOF > "${TEMPLATE_FILE}"
Parameters:

    VPC:
        Description: The VPC that the ECS cluster is deployed to
        Type: AWS::EC2::VPC::Id

    Listener:
        Description: The Application Load Balancer listener to register with
        Type: String

    Path:
        Description: The path to register with the Application Load Balancer
        Type: String
        Default: /products

Resources:

    CloudWatchLogsGroup:
        Type: AWS::Logs::LogGroup
        Properties:
            LogGroupName: !Ref AWS::StackName
            RetentionInDays: 365

    TargetGroup:
        Type: AWS::ElasticLoadBalancingV2::TargetGroup
        Properties:
            VpcId: !Ref VPC
            Port: 80
            Protocol: HTTP
            Matcher:
                HttpCode: 200-299
            HealthCheckIntervalSeconds: 10
            HealthCheckPath: !Ref Path
            HealthCheckProtocol: HTTP
            HealthCheckTimeoutSeconds: 5
            HealthyThresholdCount: 2

    ListenerRule:
        Type: AWS::ElasticLoadBalancingV2::ListenerRule
        Properties:
            ListenerArn: !Ref Listener
            Priority: 2
            Conditions:
                - Field: path-pattern
                  Values:
                    - !Ref Path
            Actions:
                - TargetGroupArn: !Ref TargetGroup
                  Type: forward

    CloudWatchLogsGroup:
        Type: AWS::Logs::LogGroup
        Properties:
            LogGroupName: !Ref AWS::StackName
            RetentionInDays: 365

    # This IAM Role grants the service access to register/unregister with the
    # Application Load Balancer (ALB). It is based on the default documented here:
    # http://docs.aws.amazon.com/AmazonECS/latest/developerguide/service_IAM_role.html
    ServiceRole:
        Type: AWS::IAM::Role
        Properties:
            RoleName: !Sub ecs-service-${AWS::StackName}
            Path: /
            AssumeRolePolicyDocument: |
                {
                    "Statement": [{
                        "Effect": "Allow",
                        "Principal": { "Service": [ "ecs.amazonaws.com" ]},
                        "Action": [ "sts:AssumeRole" ]
                    }]
                }
            Policies:
                - PolicyName: !Sub ecs-service-${AWS::StackName}
                  PolicyDocument:
                    {
                        "Version": "2012-10-17",
                        "Statement": [{
                                "Effect": "Allow",
                                "Action": [
                                    "ec2:AuthorizeSecurityGroupIngress",
                                    "ec2:Describe*",
                                    "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
                                    "elasticloadbalancing:Describe*",
                                    "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
                                    "elasticloadbalancing:DeregisterTargets",
                                    "elasticloadbalancing:DescribeTargetGroups",
                                    "elasticloadbalancing:DescribeTargetHealth",
                                    "elasticloadbalancing:RegisterTargets"
                                ],
                                "Resource": "*"
                        }]
                    }

Outputs:

    TargetGroup:
        Description: Reference to the load balancer target group
        Value: !Ref TargetGroup

    ServiceRole:
        Description: The IAM role for the service
        Value: !Ref ServiceRole

    CloudWatchLogsGroup:
        Description: Reference to the cloudwatch logs group
        Value: !Ref CloudWatchLogsGroup
EOF

#-------------------------------------------------------------------------------
# Generate env config files
#-------------------------------------------------------------------------------
info "Generating config file at ${CONFIG_FILE}"

cat << EOF > "${CONFIG_FILE}"
export DESIRED_COUNT=$OPT_DESIRED_COUNT
EOF

if [ -n "$OPT_ROUTE" ]; then
cat << EOF >> "${CONFIG_FILE}"
export ROUTE_PATH=$OPT_ROUTE
export ROUTE_TO_CONTAINER=$OPT_ROUTE_TO_CONTAINER
export ROUTE_TO_CONTAINER_PORT=$OPT_ROUTE_TO_CONTAINER_PORT
EOF
fi

#-------------------------------------------------------------------------------
# Generate docker-compose file
#-------------------------------------------------------------------------------
info "Generating docker compose file at ${COMPOSE_FILE}"

if [ -n "$OPT_ROUTE" ]; then
cat << EOF > "${COMPOSE_FILE}"
version: '2'

volumes:
  nginxdata: {}

services:
  nginx:
    image: nginx:latest
    mem_limit: 20000000
    ports:
      - "0:$OPT_ROUTE_TO_CONTAINER_PORT"
    volumes:
      - nginxdata:/usr/share/nginx/html/:ro
  instance-id-getter:
    image: busybox:latest
    mem_limit: 10000000
    volumes:
      - nginxdata:/nginx
    command: sh -c "while true; do echo \"Hello world <p><pre> \`env\` </pre></p> \" > /nginx/index.html; sleep 3; done"
EOF
else
cat << EOF > "${COMPOSE_FILE}"
version: '2'

volumes:
  nginxdata: {}

services:
  instance-id-getter:
    image: busybox:latest
    mem_limit: 10000000
    volumes:
      - nginxdata:/nginx
    command: sh -c "while true; do echo \"Hello world <p><pre> \`env\` </pre></p> \" > /nginx/index.html; sleep 3; done"
EOF
fi

bannerGreen "Successfully created ${OPT_NAME} service. The following resources have been added to the project:"

dt "Cloudformation template" "$TEMPLATE_FILE"
dt "Configuration file" "$CONFIG_FILE"
dt "Docker compose file" "$COMPOSE_FILE"

printf "You can add environment specific settings by creating configuration files at ./services/${OPT_NAME}/config.<environment>.env\n\n"
