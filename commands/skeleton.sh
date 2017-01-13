#!/usr/bin/env bash
usage() {
    cat <<EOF
NAME:
    TODO: command-name-here

DESCRIPTION:
    TODO:

SYNOPSIS:
    ecso.sh command-name-here
    --required <value>
    [--opt <value>]
    <param>

OPTIONS:
    --required (string)
        A required option

    --opt (string)
        An optional option
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
: ${CURRENT_AWS_ACCOUNT:="$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null)"}
: ${MYVAR:=2}

#-------------------------------------------------------------------------------
# Parse cli options
#-------------------------------------------------------------------------------
while [[ $# > 1 ]]
do
    key="$1"

    case $key in
        --myopt)      OPT_MYOPT="$2";      shift;;
        --myotheropt) OPT_MYOTHEROPT="$2"; shift;;
        *);;
    esac
    shift
done

[ "$1" == "help" ] && usage

MYPARAM=$1

#-------------------------------------------------------------------------------
# Prompt for any missing options
#-------------------------------------------------------------------------------
if [ -z "$OPT_NAME" ]; then
    prompt "Enter an option name"
    read OPT_NAME
fi

printf "${_bold}Which one?${_nc}\n"
select some_var in "Yes" "No"; do
    if [ "$some_var" = "Yes" ]; then
        # Do stuff
    fi
    break
done

#-------------------------------------------------------------------------------
# Validate options
#-------------------------------------------------------------------------------
: ${OPT_MYOPT:?"ERROR: Myopt is required"}
