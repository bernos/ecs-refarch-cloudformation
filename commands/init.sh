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
        The name of the project. Defaults to the name of the current directory.

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
: ${ECSO_DIR:="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" && pwd )"}

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
        *)
            # unknown option
            ;;
    esac
    shift # past argument or value
done

#-------------------------------------------------------------------------------

if [ -d .ecso ]; then
    error ".ecso dir already exists. This directory appears to already have an ecso project."
fi

bannerBlue "Creating a new ecso project"

if [ -z "$OPT_PROJECT" ]; then
    default_project_name=$(basename $PWD)
    prompt "What is the name of the project? (${default_project_name})"
    read PROJECT
    echo ""
    : ${PROJECT:=$default_project_name}
fi

info "Creating infrastructure templates"

mkdir .ecso \
    && cp -a "${ECSO_DIR}/.ecso/infrastructure" ./.ecso \
    && echo "export PROJECT=${PROJECT}" > ./.ecso/project.conf

bannerGreen "Done. Now run 'ecso add-environment to create your first environment"
