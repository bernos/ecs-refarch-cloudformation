#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    rm-service

DESCRIPTION:
    Removes and ecso service

SYNOPSIS:
    ecso.sh rm-service
    --force
    <service>

OPTIONS:
    --force
        Required to actually delete the service
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
        --force) FORCE=1;;
        *);;
    esac
    shift
done

[ "$1" == "help" ] && usage

OPT_NAME=$1

: ${OPT_NAME:?"ERROR: Service is a required param"}

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${FORCE:?"ERROR: You must set the --force flag to terminate an environment"}

ECSO_SERVICE_DIR="./.ecso/services/${OPT_NAME}"
ECSO_SERVICE_SRC_DIR="./services/${OPT_NAME}"

bannerBlue "Removing ${OPT_NAME} service."

info "Removing ${ECSO_SERVICE_DIR}"
rm -rf "$ECSO_SERVICE_DIR"

info "Removing ${ECSO_SERVICE_SRC_DIR}"
rm -rf "$ECSO_SERVICE_SRC_DIR"

bannerGreen "Removed ${OPT_NAME} service"
