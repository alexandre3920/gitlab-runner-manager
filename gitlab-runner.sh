#!/bin/bash


# Debug = print informations
# during script running
DEBUG="false"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
WHITE='\033[0;37m'
RESET='\033[0m'

# Emojies
GREEN_CHECK_EMOJI='✅'
RED_CROSS_EMOJI='❌'
YELLOW_DOT_EMOJI='🟡'
TOOLS_EMOJI='🛠'


# Set both actions to false
register_runner="false"
unregister_runner="false"
list_registered_runners="false"
use_ca_cert_file="false"

# Save the config file name
config_file_name=""

# Save the CA certificate file name
ca_cert_file_name=""
ca_cert_file_full_path=""

# Be sure docker is available
is_docker_available="$(which docker | awk '/not found/ {print;}')"
if [[ "${is_docker_available}" != "" ]]; then
    echo -e "> It seems docker is not install or not available ${RED_CROSS_EMOJI}"
    exit 1
fi


# Use sed -e $'s/\x1b\[[0-9;]*m//g' to remove 
# ANSI color in text stream
# See : https://superuser.com/questions/380772/removing-ansi-color-codes-from-text-stream
function remove_ansi_color_codes() {
    if (( $# == 0 )) ; then
        sed -e $'s/\x1b\[[0-9;]*m//g' < /dev/stdin
        echo
    else
        sed -e $'s/\x1b\[[0-9;]*m//g' <<< "$1"
        echo
    fi
}

# https://gist.github.com/masukomi/e587aa6fd4f042496871
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

# Function to display the usage
function _display_usage() {
    echo ""
    echo "Usage : ./$(basename "$0") [OPTIONS] -c CONFIG_FILE COMMAND"
    echo ""
    echo "Options"
    echo "  -h                  display the help"
    echo "  -a CA_CERT_FILE    path to the CA certificate file"
    echo ""
    echo "Configurations"
    echo "  -c CONFIG_FILE      path to the config file"
    echo ""
    echo "Commands"
    echo "  register            register a new runner"
    echo "  unregister          unregister a runner"
    echo "  list                list registered runners"
    echo "  start               start the runner"
    echo "  stop                stop a runner"
    echo ""
    echo "Run './$(basename "$0") COMMAND HELP' for more information about a command"
    exit 1
}

# Function to display the usage
function _display_unregister_runner_usage() {
    echo ""
    echo "Usage : ./$(basename "$0") [OPTIONS] -c CONFIG_FILE unregister [PARAMETER]"
    echo ""
    echo "Unregister a Gitlab-runner"
    echo ""
    echo "Options"
    echo "  -a CA_CERT_FILE    path to the CA certificate file"
    echo ""
    echo "Configurations"
    echo "  -c CONFIG_FILE      path to the config file"
    echo ""
    echo "Parameter"
    echo "  -t TOKEN            unregister the runner with token TOKEN"
    echo "  -a                  unregister all runners"
    echo ""
    echo "Run './$(basename "$0") COMMAND HELP' for more information about a command"
    exit 1
}

# Function to load the variables
# from the config file
function _load_config_file() {
    # Set a flag to display a hint for
    # the configuration file
    display_configuration_hint="false"
    # Check if the file exists
    if [[ ! -e ${config_file_name} ]]; then
        echo -e "[${RED_CROSS_EMOJI}] The configuration file '${config_file_name}' doesn't exist"
        exit 2
    fi

    if [[ ${DEBUG} = "true" ]]; then
        echo -e "> Load configuration file : ${config_file_name} ..."
    fi

    # Load variables to environment
    eval "$(parse_yaml "${config_file_name}")"

    # Check if all required variables are
    # define in the configuration
    if [[ -z "${gitlab_conf_url}" ]]; then
        echo -e "${RED_CROSS_EMOJI} > There is no 'url' defined in your configuration"
        display_configuration_hint="true"
    fi
    if [[ -z "${gitlab_conf_token}" ]]; then
        echo -e "${RED_CROSS_EMOJI} > There is no 'token' defined in your configuration"
        display_configuration_hint="true"
    fi
    if [[ -z "${gitlab_conf_repository_name}" ]]; then
        echo -e "${RED_CROSS_EMOJI} > There is no 'repository_name' defined in your configuration"
        display_configuration_hint="true"
    fi
    
    # Display hint and exit
    if [[ ${display_configuration_hint} = "true" ]]; then
        echo ""
        echo -e "Your configuration file should at least look like this :"
        echo -e "> cat ${config_file_name}"
        echo -e "---"
        echo -e "gitlab_conf:"
        echo -e "  url:\"gitlab url\""
        echo -e "  token:\"gitlab runner registration token\""
        echo -e "  repository_name:\"repository name\""
        echo -e ""
        echo -e "You can also specify :"
        echo -e "  description: \"Runner for django-doctor-dashboard\""
        echo -e "  runner_version: \"latest\""
        echo -e "  tags: \"docker,python\""
        exit 1
    fi

    # Set the docker volume name
    docker_volume_name="gitlab-runner-${gitlab_conf_repository_name}-volume"

    # Set the docker runner name
    host_name=$(hostname | tr '[:upper:]' '[:lower:]')
    runner_name="gitlab-runner-${host_name}-${gitlab_conf_repository_name}"

    # Check if aditional settings are set
    # otherwise set default value
    if [[ -z "${gitlab_conf_runner_version}" ]]; then
        gitlab_conf_runner_version="laster"
    fi
    if [[ -z "${gitlab_conf_tags}" ]]; then
        gitlab_conf_tags="docker"
    fi
    if [[ -z "${gitlab_conf_description}" ]]; then
        # Set the gitlab runner description
        gitlab_conf_description="Runner for ${gitlab_conf_repository_name} on ${host_name}"
    fi

    if [[ ${DEBUG} = "true" ]]; then
        echo -e "> Configuration file loaded"
    fi
}


# Function to load the CA
# certificate file
function _load_ca_cert_file() {
    # Check if the file exists
    if [[ ! -e ${ca_cert_file_name} ]]; then
        echo -e "[${RED_CROSS_EMOJI}] The ca certificate file '${ca_cert_file_name}' doesn't exist"
        exit 2
    fi
    # Add pwd to file name to has full path
    ca_cert_file_full_path="$(pwd)/${ca_cert_file_name}"
}

# Function to parse and check arguments
function _parse_and_check_arguments() {
    # Display the usage is there is no argument
    if [[ ${#} -eq 0 ]]; then
        _display_usage
    fi

    # Else parse the arguments with getopts
    # notes :
    #   1. the first colon in the options string is used to suppress
    #      shell error messages; it has nothing to do with argument processing.
    #   2. To tell getopts that an option will be followed by an argument,
    #      put a colon : immediately behind the option letter in the options string
    while getopts ":hc:a:" OPTION; do
        case "$OPTION" in
            h)
                # Display usage text
                _display_usage
                exit 1
                ;;
            c)
                # Set the config file name
                config_file_name=$OPTARG
                ;;
            a)
                # Set flag to true
                use_ca_cert_file="true"
                # Set the ca cert file name
                ca_cert_file_name=$OPTARG
                ;;
            ?)
                # Catch invalid option
                echo -e "[${RED}!${RESET}] Invalid option: -${OPTARG}"
                _display_usage
                exit 2
                ;;
        esac
    done

    # shift so that $@, $1, etc. refer to the
    # non-option arguments handle by getopts
    shift "$((OPTIND-1))"

    # If there is no configuration file
    if [[ $config_file_name = "" ]]; then
        echo -e "[${RED_CROSS_EMOJI}] No config file configuration submited"
        # display the main usage
        _display_usage
        exit 2
    fi

    # Check the COMMAND
    if [[ $1 = "list" ]]; then
        # List the registered runners
        _list_registered_runners
    elif [[ $1 = "register" ]]; then
        # Register new runner
        _register_new_runner
    elif [[ $1 = "unregister" ]]; then
        # Unegister runner
        # shift 1 to remove the command
        shift 1
        # and set OPTIND to 1
        OPTIND=1
        _unregister_runner "$@"
    elif [[ $1 = "start" ]]; then
        # Start runner
        _start_runner
    elif [[ $1 = "stop" ]]; then
        # Stop runner
        _stop_runner
    else
        # display the main usage
        _display_usage
    fi
}

# Register a new runner to the Gitlab instance
function _register_new_runner() {

    # If I need to use ca cert file
    if [[ $use_ca_cert_file = "true" ]]; then
        # Load the ca cert file
        _load_ca_cert_file
    fi

    # Load the config file
    _load_config_file

    # Test if the docker daemon is running
    is_docker_daemon_running="$(docker ps 2>&1 | awk '/Cannot connect to the Docker daemon/ {print;}')"
    if [[ $is_docker_daemon_running != "" ]]; then
        echo -e "> It seems the docker daemon is not running, cannot register new runner ${RED_CROSS_EMOJI}"
        exit 1
    fi

     # First I need to check if there is already
    # a container with the $runner_name existing
    # which mean the runner has already been registered
    # and started once. Moreover, I can't create
    # two containers with the same name
    check_if_container_exists_and_is_running="$(docker ps | awk '/'"$runner_name"'/ {print $0}' | wc -l | awk '{print $1}')"
    check_if_container_exists_and_is_stopped="$(docker ps -a | awk '/'"$runner_name"'/ {print $0}' | wc -l | awk '{print $1}')"
    
    if [[ $check_if_container_exists_and_is_running != "0" ]]; then
        echo -e "> There is already a running runner named '${runner_name}'. Cannot register a second one ${YELLOW_DOT_EMOJI}"
        exit 1
    elif [[ $check_if_container_exists_and_is_stopped != "0" ]]; then
        echo -e "> There is already a runner named '${runner_name}' but is currently stopped ${YELLOW_DOT_EMOJI}"
        exit 1
    fi

    # Check if there is already a docker
    # volume with that name
    is_docker_volume_exists="$(docker volume inspect "${docker_volume_name}" 2>&1 | awk '/Error/ {print;}')"
    if [[ "${is_docker_volume_exists}" != "" ]] ; then
        printf "> There is no existing docker volume named '%s', creating one ..." "${docker_volume_name}"
        # Create a new volume
        docker volume create "${docker_volume_name}" 1>/dev/null
        echo -e "${GREEN_CHECK_EMOJI}"
    else
        echo -e "> There is already a docker volume named '${docker_volume_name}'"
    fi

    echo "> Configuration summary :"
    echo "       url : ${gitlab_conf_url}"
    echo "       gitlab-runner version : ${gitlab_conf_runner_version}"
    echo "       description : ${gitlab_conf_description}"
    echo "       tags : ${gitlab_conf_tags}"
    if [[ $use_ca_cert_file = "true" ]]; then
    echo "       tls-ca-file : ${ca_cert_file_name}"
    fi
    echo ""

    printf "> Registering new runner ..."

    # Store output messages
    output=""
    output_error=""
    output_fatal=""

    # If I need to use ca cert file
    if [[ $use_ca_cert_file = "true" ]]; then
        output="$(docker run --rm -v "${docker_volume_name}":/etc/gitlab-runner \
            -v "${ca_cert_file_full_path}":/etc/gitlab-runner/certs/ca.crt \
            gitlab/gitlab-runner:"${gitlab_conf_runner_version}" register \
            --non-interactive \
            --url "${gitlab_conf_url}" \
            --tls-ca-file=/etc/gitlab-runner/certs/ca.crt \
            --registration-token "${gitlab_conf_token}" \
            --executor "docker" \
            --docker-image alpine:latest \
            --description "${gitlab_conf_description}" \
            --tag-list "${gitlab_conf_tags}" \
            --run-untagged="true" \
            --locked="false" \
            --access-level="not_protected" 2>&1 | remove_ansi_color_codes)"
    else
        output="$(docker run --rm -v "${docker_volume_name}":/etc/gitlab-runner \
            gitlab/gitlab-runner:"${gitlab_conf_runner_version}" register \
            --non-interactive \
            --url "${gitlab_conf_url}" \
            --registration-token "${gitlab_conf_token}" \
            --executor "docker" \
            --docker-image alpine:latest \
            --description "${gitlab_conf_description}" \
            --tag-list "${gitlab_conf_tags}" \
            --run-untagged="true" \
            --locked="false" \
            --access-level="not_protected" 2>&1 | remove_ansi_color_codes)"
    fi

    # Check for error or fatal
    # in output
    # Set custom IFS
    oldif="${IFS}"; IFS=$'\n';
    output_errors="$(echo "${output}" | awk '/ERROR:/ {print;}')"
    output_fatals="$(echo "${output}" | awk '/FATAL:/ {print;}')"
    # Print if there is error or fatal
    if [[ "${output_errors}" != "" || "${output_fatals}" != "" ]]; then
        echo -e " ${RED_CROSS_EMOJI}"
    fi

    # Display errors
    if [[ "${output_errors}" != "" ]]; then
        # For each error
        for output_error in $output_errors; do
            # Get error details
            output_error_text="$(echo "${output_error}" | sed 's/^ERROR: \(.*\)runner=.*$/\1/' \
                | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print}')"
            output_error_status="$(echo "${output_error}" | awk '/status=/ {print $0}' | sed 's/^.*\(status=.*\)$/\1/' | awk -F'=' '{print $2}')"
            if [[ "${output_error_status}" != "" ]]; then
                echo -e "  - ${output_error_text} : ${output_error_status}"
            else
                echo -e "  - ${output_error_text}"
            fi
        done
    fi

    # Reset IFS
    IFS=$oldif

    # Display fatals
    if [[ "${output_fatals}" != "" ]]; then
        # For each fatal
        for output_fatal in $output_fatals; do
            # Get fatal details
            output_fatal_text="$(echo "${output_fatal}" | sed 's/^FATAL: \(.*\)$/\1/' \
                | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print}')"
            echo -e "  - ${output_fatal_text}"
        done
    fi

    # Exit 1 if there is error or fatal
    if [[ "${output_errors}" != "" || "${output_fatals}" != "" ]]; then
        exit 1
    fi

    echo -e " ${GREEN_CHECK_EMOJI}"
}

# Unregister a runner from the Gitlab instance
function _unregister_runner() {

    # If I need to use ca cert file
    if [[ $use_ca_cert_file = "true" ]]; then
        # Load the ca cert file
        _load_ca_cert_file
    fi

    unregister_all_runners="false"
    # Display the usage is there is no argument
    if [[ ${#} -eq 0 ]]; then
        _display_unregister_runner_usage
    fi

    # Parse the arguments
    while getopts ":t:a" unregister_param; do
    case ${unregister_param} in
        t)
            # Save the token
            unregister_runner_token=${OPTARG}
            ;;
        a)
            # Set true the unregister all runners flag
            unregister_all_runners="true"
            ;;
        ?)
            # Catch invalid option
            echo -e "[${RED}!${RESET}] Invalid option: -${OPTARG}"
            _display_unregister_runner_usage
            exit 2
            ;;
    esac
    done

    # If there is no token and not the all_runner flag
    if [[ "${unregister_runner_token}" = "" && ${unregister_all_runners} = "false" ]]; then
        _display_unregister_runner_usage
        exit 2
    fi

    # Load the config file
    _load_config_file

    # Test if the docker daemon is running
    is_docker_daemon_running="$(docker ps 2>&1 | awk '/Cannot connect to the Docker daemon/ {print;}')"
    if [[ $is_docker_daemon_running != "" ]]; then
        echo -e "> It seems the docker daemon is not running, cannot unregister runner ${RED_CROSS_EMOJI}"
        exit 1
    fi

    # Store output messages
    output=""
    output_error=""
    output_fatal=""

    if [[ $unregister_all_runners = "true" ]]; then
        printf "> Unregister all tokens ..."
        # If I need to use ca cert file
        if [[ $use_ca_cert_file = "true" ]]; then
            output="$(docker run --rm -v "${docker_volume_name}":/etc/gitlab-runner \
                -v "${ca_cert_file_full_path}":/etc/gitlab-runner/certs/ca.crt \
                gitlab/gitlab-runner:"${gitlab_conf_runner_version}" unregister \
                --tls-ca-file=/etc/gitlab-runner/certs/ca.crt \
                --url "${gitlab_conf_url}" \
                --all-runners 2>&1  | remove_ansi_color_codes)"
        else
            output="$(docker run --rm -v "${docker_volume_name}":/etc/gitlab-runner \
                gitlab/gitlab-runner:"${gitlab_conf_runner_version}" unregister \
                --url "${gitlab_conf_url}" \
                --all-runners 2>&1 | remove_ansi_color_codes)"
        fi
    else
        # Unregistered the runner with specific token
        printf "> Unregister the runner with token '%s' ..." "${unregister_runner_token}"
        # If I need to use ca cert file
        if [[ $use_ca_cert_file = "true" ]]; then
            output="$(docker run --rm -v "${docker_volume_name}":/etc/gitlab-runner \
                -v "${ca_cert_file_full_path}":/etc/gitlab-runner/certs/ca.crt \
                gitlab/gitlab-runner:"${gitlab_conf_runner_version}" unregister \
                --tls-ca-file=/etc/gitlab-runner/certs/ca.crt \
                --url "${gitlab_conf_url}" \
                --token="${unregister_runner_token}" 2>&1 | remove_ansi_color_codes)"
            #echo -e "output = \n${output}"
        else
            output="$(docker run --rm -v "${docker_volume_name}":/etc/gitlab-runner \
                gitlab/gitlab-runner:"${gitlab_conf_runner_version}" unregister \
                --url "${gitlab_conf_url}" \
                --token="${unregister_runner_token}" 2>&1 | remove_ansi_color_codes)"
        fi
    fi

    # Check for error or fatal
    # in output
    # Set custom IFS
    oldif="${IFS}"; IFS=$'\n';
    output_errors="$(echo "${output}" | awk '/ERROR:/ {print;}')"
    output_fatals="$(echo "${output}" | awk '/FATAL:/ {print;}')"
    # Print \n if there is error or fatal
    if [[ "${output_errors}" != "" || "${output_fatals}" != "" ]]; then
        echo -e " ${RED_CROSS_EMOJI}"
    fi

    # Display errors
    if [[ "${output_errors}" != "" ]]; then
        # For each error
        for output_error in $output_errors; do
            # Get error details
            output_error_text="$(echo "${output_error}" | sed 's/^ERROR: \(.*\)runner=.*$/\1/' \
                | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print}')"
            output_error_status="$(echo "${output_error}" | awk '/status=/ {print $0}' | sed 's/^.*\(status=.*\)$/\1/' | awk -F'=' '{print $2}')"
            if [[ "${output_error_status}" != "" ]]; then
                echo -e "  - ${output_error_text} : ${output_error_status}"
            else
                echo -e "  - ${output_error_text}"
            fi
        done
    fi

    # Reset IFS
    IFS=$oldif

    # Display fatals
    if [[ "${output_fatals}" != "" ]]; then
        # For each fatal
        for output_fatal in $output_fatals; do
            # Get fatal details
            output_fatal_text="$(echo "${output_fatal}" | sed 's/^FATAL: \(.*\)$/\1/' \
                | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print}')"
            echo -e "  - ${output_fatal_text}"
        done
    fi

    # Exit 1 if there is error or fatal
    if [[ "${output_errors}" != "" || "${output_fatals}" != "" ]]; then
        exit 1
    fi

    # Else display green check
    echo -e " ${GREEN_CHECK_EMOJI}"

    # Next step is to remove the container
    printf "> Deleting the docker container '%s' ..." "${runner_name}"
    output="$(docker rm "${runner_name}" 2>&1)"
    oldif="${IFS}"; IFS=$'\n';
    output_errors="$(echo "${output}" | awk '/Error/ {print;}')"
    # Print \n if there is error 
    if [[ "${output_errors}" != "" ]]; then
        echo -e " ${RED_CROSS_EMOJI}"
    fi

    # Display errors
    if [[ "${output_errors}" != "" ]]; then
        # For each error
        for output_error in $output_errors; do
            echo -e "  - ${output_error}"
        done
    fi

    # Reset IFS
    IFS=$oldif

    # Exit 1 if there is error or fatal
    if [[ "${output_errors}" != "" ]]; then
        exit 1
    fi

    echo -e "${GREEN_CHECK_EMOJI}"

    # Last step is to deleting the associated docker volume
    printf "> Deleting the associated docker volume '%s' ..." "${docker_volume_name}"
    # Delete the volume
    output="$(docker volume rm "${docker_volume_name}" 2>&1)"
    oldif="${IFS}"; IFS=$'\n';
    output_errors="$(echo "${output}" | awk '/Error/ {print;}')"
    # Print \n if there is error 
    if [[ "${output_errors}" != "" ]]; then
        echo -e " ${RED_CROSS_EMOJI}"
    fi

    # Display errors
    if [[ "${output_errors}" != "" ]]; then
        # For each error
        for output_error in $output_errors; do
            echo -e "  - ${output_error}"
        done
    fi

    # Reset IFS
    IFS=$oldif

    # Exit 1 if there is error or fatal
    if [[ "${output_errors}" != "" ]]; then
        exit 1
    fi

    echo -e "${GREEN_CHECK_EMOJI}"
}

# List gitlab runners
function _list_registered_runners() {
    echo -e "> Listing existing runners ..."

    # Load the config file
    _load_config_file
    
    # Use sed -e $'s/\x1b\[[0-9;]*m//g' to remove 
    # ANSI color in text stream
    # See : https://superuser.com/questions/380772/removing-ansi-color-codes-from-text-stream
    list_full_output="$(docker run --rm -v "${docker_volume_name}":/etc/gitlab-runner \
        gitlab/gitlab-runner:"${gitlab_conf_runner_version}" list 2>&1 | remove_ansi_color_codes )"

    #echo -e $list_full_output

    # Test if the docker daemon is running
    is_docker_daemon_running="$(echo "${list_full_output}" | awk '/Cannot connect to the Docker daemon/ {print;}')"
    if [[ $is_docker_daemon_running != "" ]]; then
        echo -e "> It seems the docker daemon is not running, cannot list runners ${RED_CROSS_EMOJI}"
        exit 1
    fi

    if [[ $list_full_output = "" ]]; then
        echo -e "> There is no runner running yet ${YELLOW_DOT_EMOJI}"
        exit 0
    else
        # Get runtime platform informations
        runtime_plateform=$(echo "${list_full_output}" | awk '/Runtime platform/ {print $0}')

        if [[ "${runtime_plateform}" = "" ]]; then
            echo -e "> Unable to get runtime platform informations ${YELLOW_DOT_EMOJI}"
        else
            # Runtime information table configuration
            FIRST_COLUMN_WIDTH=10
            SECOND_COLUMN_WIDTH=15
            THIRD_COLUMN_WIDTH=10
            FOURTH_COLUMN_WIDTH=20
            FIFTH_COLUMN_WIDTH=20
            TABLE_WIDTH=$((FIRST_COLUMN_WIDTH + SECOND_COLUMN_WIDTH + THIRD_COLUMN_WIDTH \
                + FOURTH_COLUMN_WIDTH + FIFTH_COLUMN_WIDTH))
            ROW_SEPARATOR="+-$(printf '%0.s-' $(seq 1 $FIRST_COLUMN_WIDTH))-+-$(printf '%0.s-' $(seq 1 $SECOND_COLUMN_WIDTH))-+-$(printf '%0.s-' $(seq 1 $THIRD_COLUMN_WIDTH))-+-$(printf '%0.s-' $(seq 1 $FOURTH_COLUMN_WIDTH))-+-$(printf '%0.s-' $(seq 1 $FIFTH_COLUMN_WIDTH))-+"
            ROW="| %-${FIRST_COLUMN_WIDTH}s | %-${SECOND_COLUMN_WIDTH}s | %-${THIRD_COLUMN_WIDTH}s | %-${FOURTH_COLUMN_WIDTH}s | %-${FIFTH_COLUMN_WIDTH}s |\n"

            # Get runtime platform details
            runtime_plateform_arch=$(echo "${runtime_plateform}" | awk '{print $3}' \
                | awk -F "=" '{print $2}')
            runtime_plateform_os=$(echo "${runtime_plateform}" | awk '{print $4}' \
                | awk -F "=" '{print $2}')
            runtime_plateform_pid=$(echo "${runtime_plateform}" | awk '{print $5}' \
                | awk -F "=" '{print $2}')
            runtime_plateform_revision=$(echo "${runtime_plateform}" | awk '{print $6}' \
                | awk -F "=" '{print $2}')
            runtime_plateform_version=$(echo "${runtime_plateform}" | awk '{print $7}' \
                | awk -F "=" '{print $2}')
            
            # Display runtime platform table
            echo -e "> Runtime plateform :"
            echo "${ROW_SEPARATOR}"
            printf  "${ROW}" Arch OS PID Revision Version
            echo "${ROW_SEPARATOR}"
            printf  "${ROW}" "${runtime_plateform_arch:0:${FIRST_COLUMN_WIDTH}}" \
                "${runtime_plateform_os:0:${SECOND_COLUMN_WIDTH}}" \
                "${runtime_plateform_pid:0:${THIRD_COLUMN_WIDTH}}" \
                "${runtime_plateform_revision:0:${FOURTH_COLUMN_WIDTH}}" \
                "${runtime_plateform_version:0:${FIFTH_COLUMN_WIDTH}}"
            echo "${ROW_SEPARATOR}"
            echo ""
        fi

        # List of runners table configuration
        FIRST_COLUMN_WIDTH=50
        SECOND_COLUMN_WIDTH=20
        THIRD_COLUMN_WIDTH=25
        FOURTH_COLUMN_WIDTH=30
        TABLE_WIDTH=$((FIRST_COLUMN_WIDTH + SECOND_COLUMN_WIDTH + THIRD_COLUMN_WIDTH + FOURTH_COLUMN_WIDTH))
        ROW_SEPARATOR="+-$(printf '%0.s-' $(seq 1 $FIRST_COLUMN_WIDTH))-+-$(printf '%0.s-' $(seq 1 $SECOND_COLUMN_WIDTH))-+-$(printf '%0.s-' $(seq 1 $THIRD_COLUMN_WIDTH))-+-$(printf '%0.s-' $(seq 1 $FOURTH_COLUMN_WIDTH))-+"
        ROW="| %-${FIRST_COLUMN_WIDTH}s | %-${SECOND_COLUMN_WIDTH}s | %-${THIRD_COLUMN_WIDTH}s | %-${FOURTH_COLUMN_WIDTH}s |\n"

        # Get list of runners
        # Set custom IFS
        oldif="${IFS}"; IFS=$'\n';
        runners=$(echo -e "${list_full_output}" | awk '/Executor=/ {print;}')

        #exit 0

        if [[ "${runners}" = "" || "${#runners}" = 0  ]]; then
            echo -e "> There is no resgistered runners ${YELLOW_DOT_EMOJI}"
        else
            echo -e "> List of runners :"
            echo "${ROW_SEPARATOR}"
            printf  "${ROW}" "Name" "Executor" "Token" "URL"
            echo "${ROW_SEPARATOR}"

            # For each runner in the list
            for runner in $runners; do

                #echo -e "'$runner'"

                # Get runner details
                runner_name="$(echo "${runner}" | sed 's/^\(.*\)Executor.*$/\1/' \
                    | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print}')"
                runner_executor="$(echo "${runner}" | sed 's/^.*\(Executor.*\) Token.*$/\1/' \
                    | awk -F'=' '{print $2}')"
                runner_token="$(echo "${runner}" | sed 's/^.*\(Token.*\) URL.*$/\1/' \
                    | awk -F'=' '{print $2}')"
                runner_url="$(echo "${runner}" | sed 's/^.*\(URL.*\)$/\1/' | awk -F'=' '{print $2}')"

                # And print a new row                
                printf  "${ROW}" "${runner_name:0:${FIRST_COLUMN_WIDTH}}" \
                    "${runner_executor:0:${SECOND_COLUMN_WIDTH}}" \
                    "${runner_token:0:${THIRD_COLUMN_WIDTH}}" \
                    "${runner_url:0:${FOURTH_COLUMN_WIDTH}}"
            done

            # Print a row separator to close the table
            echo "${ROW_SEPARATOR}"
        fi
        # Reset IFS
        IFS=$oldif
    fi
}

# Start a runner
function _start_runner() {
    
    # If I need to use ca cert file
    if [[ $use_ca_cert_file = "true" ]]; then
        # Load the ca cert file
        _load_ca_cert_file
    fi

    # Load the config file
    _load_config_file

    # Test if the docker daemon is running
    is_docker_daemon_running="$(docker ps 2>&1 | awk '/Cannot connect to the Docker daemon/ {print;}')"
    if [[ $is_docker_daemon_running != "" ]]; then
        echo -e "> It seems the docker daemon is not running, cannot start runner '${runner_name}' ${RED_CROSS_EMOJI}"
        exit 1
    fi

    # Check if there is already a docker
    # volume with that name
    is_docker_volume_exists="$(docker volume inspect "${docker_volume_name}" 2>&1 | awk '/Error/ {print;}')"
    if [[ "${is_docker_volume_exists}" != "" ]] ; then
        # Exit if there is no volume
        echo -e "> There is no existing docker volume named '${docker_volume_name}', cannot start the runner ${RED_CROSS_EMOJI}"
        exit 1
    fi
   
    # Second I need to check if there is already
    # a container with the $runner_name existing
    # which mean the runner has already been registered
    # and started once. Moreover, I can't create
    # two containers with the same name
    check_if_container_exists_and_is_running="$(docker ps | awk '/'"$runner_name"'/ {print $0}' | wc -l | awk '{print $1}')"
    check_if_container_exists_and_is_stopped="$(docker ps -a | awk '/'"$runner_name"'/ {print $0}' | wc -l | awk '{print $1}')"
    
    if [[ $check_if_container_exists_and_is_running != "0" ]]; then
        echo -e "> Your runner '${runner_name}' is already running ${GREEN_CHECK_EMOJI}"
        exit 1
    elif [[ $check_if_container_exists_and_is_stopped != "0" ]]; then
        printf "> Your runner '%s' already exists, restarting it ..." "$runner_name"
        docker container restart "${runner_name}" > /dev/null
        echo -e " ${GREEN_CHECK_EMOJI}"
        exit 1
    fi
    
    # Start runner
    printf "> Starting the runner '%s' ..." "$runner_name"

    # If I need to use ca cert file
    if [[ $use_ca_cert_file = "true" ]]; then
        output="$(docker run -d --name "${runner_name}" --restart always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "${docker_volume_name}":/etc/gitlab-runner \
            -v "${ca_cert_file_full_path}":/etc/gitlab-runner/certs/ca.crt \
            gitlab/gitlab-runner:"${gitlab_conf_runner_version}" 2>&1)"
    else
        output="$(docker run -d --name "${runner_name}" --restart always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "${docker_volume_name}":/etc/gitlab-runner \
            gitlab/gitlab-runner:"${gitlab_conf_runner_version}" 2>&1)"
    fi

    echo -e " ${GREEN_CHECK_EMOJI}"
}

# Stop a runner
function _stop_runner() {

    # Load the config file
    _load_config_file

    # Test if the docker daemon is running
    is_docker_daemon_running="$(docker ps 2>&1 | awk '/Cannot connect to the Docker daemon/ {print;}')"
    if [[ $is_docker_daemon_running != "" ]]; then
        echo -e "> It seems the docker daemon is not running, cannot stop runner '${runner_name}' ${RED_CROSS_EMOJI}"
        exit 1
    fi

    # First I need to check if there is already
    # a running container with the $runner_name
    check_if_container_exists_and_is_running="$(docker ps | awk '/'"$runner_name"'/ {print $0}' | wc -l | awk '{print $1}')"
    if [[ $check_if_container_exists_and_is_running = "0" ]]; then
        echo -e "> There is no runner named '${runner_name}' currently running ${YELLOW_DOT_EMOJI}"
        exit 1
    fi

    printf "> Stoping the runner '%s' ..." "$runner_name"

    # Stop the runner container
    docker stop "${runner_name}" > /dev/null

    echo -e " ${GREEN_CHECK_EMOJI}"
}

function _main() {
    # First I need to parse and check arguments
    _parse_and_check_arguments "$@"

    # Exit script
    exit 0
}

# Call the main function with all arguments
_main "$@"

