#!/bin/bash

# Help function, declare usage
function usage() {
    cat <<-EOF
        Usage: ./$(basename "$0") [OPTIONS] PACKAGE
        Manage AUR packages as git subtree

        OPTIONS
            -p, --pull                   Pull changes from the AUR or import a new package
            -g, --git "<git options>"    Pass additional options to git (in brackets)
            -s, --check-https            Check http links which could be https
            -h, --help                   Show this help message"
EOF
}

# Check for links in all packages which are using http but could be using https
function check_https() {
    [[ -n "$*" ]] && path=($@) || path=(.)
    for link in $( (find ${path[@]} -type f -iname pkgbuild -exec pcregrep -iH "http[^s]" {} \;) | sed 's/.*http:\/\/\([^\/]*\).*/\1/g' | sort | uniq); do
        echo -n "${link}: "
        if ! curl -s "https://${link}" >/dev/null; then
            echo -e "\e[31mFALSE\e[39m"
        else
            echo -e "\e[32mTRUE\e[39m"
            find ${path[@]} -type f -iname pkgbuild -exec pcregrep -H "http://${link}" {} \;
        fi
    done
}

# Push package to the AUR
function push_packages() {
    for package in $@; do
        git subtree push -P "${package}" aur@aur.archlinux.org:${package}.git master $GIT_OPTS
    done
}

# Pull package into its own subtree
function pull_packages() {
    for package in $@; do
        # Test if prefix already exists respectively whether a package is already committed in git
        if (git ls-tree -d --name-only HEAD | grep -E "^${package}$" >/dev/null 2>&1); then
            # Pull package, one at a time
            git subtree pull -P "${package}" aur@aur.archlinux.org:${package}.git master -m "Merge subtree '${package}'" $GIT_OPTS
        else
            git subtree add --squash -P "${package}" aur@aur.archlinux.org:${package}.git master $GIT_OPTS
        fi
    done
}

# Do the great option check
if ! PARAMS=$(getopt -o pshg: -l help,pull,check-https,git: -n "aurpublish" -- "$@"); then
    >&2 echo "error: No arguments passed."
    usage
    exit 2
fi
eval set -- "$PARAMS"
while true; do
    case "$1" in
        -h|--help)
        usage
        exit
        ;;

        -p|--pull)
        PULL_SUBTREE=true
        ;;

        -g|--git)
        if [[ "$2" ]]; then
            GIT_OPTS="$2"
        else
            >&2 echo "No additional arguments given for git." && usage && exit 2
        fi
        shift
        ;;

        -s|--check-https)
        CHECK_HTTPS=true
        ;;

        --)
        shift
        break
        ;;

        *)
        usage
        exit 1
        ;;
    esac
    shift
done
PACKAGE_ARRAY=($@)

# Remove trailing slashes from each package (if they even have one)
[[ -n "${PACKAGE_ARRAY[*]}" ]] && PACKAGE_ARRAY=("${PACKAGE_ARRAY[@]%/}")
# Strip directory information
[[ -n "${PACKAGE_ARRAY[*]}" ]] && PACKAGE_ARRAY=("$(basename -a "${PACKAGE_ARRAY[@]}")")

# Save current path to get back later
previous_pwd="$(pwd)"
cd "$(git rev-parse --show-toplevel)" || exit 1

# Invoke the appropiate function to run the specified options
if [[ "${CHECK_HTTPS,,}" == "true" ]]; then
    check_https ${PACKAGE_ARRAY[@]}
elif [[ -n "${PACKAGE_ARRAY[*]}" ]]; then
    # Running pull or push commands makes sense only if a packages was specified
    if [[ "${PULL_SUBTREE,,}" == "true" ]]; then
        pull_packages ${PACKAGE_ARRAY[@]}
    else
        push_packages ${PACKAGE_ARRAY[@]}
    fi
else
    usage
    exit 2
fi

# Restore previous path
cd "${previous_pwd}" || exit 1
