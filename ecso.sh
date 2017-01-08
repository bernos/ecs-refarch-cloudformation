#! /usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    ecso.sh

DESCRIPTION:
    A tool for managing AWS ECS projects

SYNOPSIS:
    ecso.sh <command> [parameters]

    Use ecso.sh command help for information on a specific command.

COMMANDS:
    - init
    - environment-up
    - environment-down
    - service-up
    - service-down

EOF
    exit
}

ECSO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

CMD=$1

shift

if [ "$CMD" = "help" ]; then
    usage
elif [ -f "${ECSO_DIR}/${CMD}.sh" ]; then
    . "${ECSO_DIR}/${CMD}.sh"
else
    echo "Unknown command ${CMD}"
fi
