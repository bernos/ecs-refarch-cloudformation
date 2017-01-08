#!/usr/bin/env bash
if [ -z "$1" ]; then
    echo "ERROR: No service specified. Usage: use-service.sh <service-name>"
elif [ -z "$ENVIRONMENT" ]; then
    echo "ERROR: \$ENVIRONMENT must be set. Have you run use-environment?"
else

    . "./.ecso/project.conf"

    conf="./services/$1/$ENVIRONMENT.env"

    if [ ! -f "$conf" ]; then
        echo "ERROR: No service configuration found at $conf"
    else
        export SERVICE_NAME=$1

        # This will make ecs-cli compose commands default to using our
        # the service
        export COMPOSE_PROJECT_NAME=$SERVICE_NAME
        export COMPOSE_FILE=./services/$SERVICE_NAME/docker-compose.yaml

        . "$conf"
    fi
fi




