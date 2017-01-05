#!/usr/bin/env bash
if [ -z "$1" ]; then
    echo "Error: No environment specified. Usage: use-environment.sh <environment-name>"
else

    conf="./$1.env"

    if [ ! -f "$conf" ]; then
        echo "Error: No environment configuration found at $conf"
    else
        . "$conf"

        export ENVIRONMENT=$1
        export CLUSTER_NAME=$PROJECT-$ENVIRONMENT

        # configure so that ecs-cli commands will work
        # against our cluster. Set all compose prefixes to empty
        # strings to give us full control over naming of our ecs
        # compose services
        export COMPOSE_PROJECT_NAME=$PROJECT

        ecs-cli configure \
                --region $AWS_REGION \
                --compose-project-name-prefix "" \
                --compose-service-name-prefix "" \
                --cluster $CLUSTER_NAME
    fi
fi

