#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    init

DESCRIPTION:
    Initialises a new ecso project

SYNOPSIS:
    ecso.sh init
    --project <value>

OPTIONS:
    --project (string)
        The name of the project. If this value is not provided the environment
        variable PROJECT will be used.

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
        --project)
            OPT_PROJECT="$2"
            shift
            ;;
        *)
            # unknown option
            ;;
    esac
    shift # past argument or value
done

#-------------------------------------------------------------------------------
# Set options, falling back to env vars if option values are not provided on
# the cli
#-------------------------------------------------------------------------------
PROJECT=${OPT_PROJECT:-$PROJECT}

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${PROJECT:?"ERROR: Project name not provided"}

bannerBlue "Creating a new ecso project"

if [ -d .ecso ]; then
    error ".ecso dir already exists. This directory appears to already have an ecso project."
fi

info "Creating infrastructure templates"

mkdir .ecso \
    && cp -a "${ECSO_DIR}/.ecso/infrastructure" ./.ecso \
    && echo "export PROJECT=${PROJECT}" > ./.ecso/project.conf

bannerGreen "Done. Now run 'ecso add-environment to create your first environment"
