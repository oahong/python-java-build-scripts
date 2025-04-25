#! /usr/bin/env bash
# 声明关联数组存储信息
# dnf install python3-devel gcc zlib-devel gcc-c++ libjpeg-turbo-devel cmake

declare -A repo
declare -A packages
declare -Ar color=(
    ['reset']='\e[0m'
    ['error']='\e[1m\e[31m'
    ['info']='\e[1m\e[32m'
    ['warn']='\e[1m\e[33m'
)

# shellcheck disable=SC2155
declare -r scriptPath=$(dirname "$(readlink -f "${0}")")

# helper functions
info() {
    echo -e "${color[info]}I:${color[reset]} $*..."
}


# warn $package $stage
warn() {
    echo -e "${color[warn]}W:${color[reset]} ${1}..."
    echo "${1}" | tee -a "${scriptPath}/logs/${package}-${version:-all}.fail"

}

# die $package $stage
die() {
    echo -e "${color[error]}E:=1=${color[reset]} $*" >&2
    exit 1
}

upload() {
    local whl=${1}
    curl -v -u "${NEXUS_USER:-wxiat}:${NEXUS_PASS}"     \
        -X POST -H "Content-Type: multipart/form-data"  \
        -F "pypi.asset=@${whl}"                         \
        "http://10.3.10.189:8081/service/rest/v1/components?repository=project-2193-python"
}

help() {
    cat <<EOF
Usage: ${0} [OPTIONS]
A script to build python packages

Options:
  -n, --name NAME        Specify a package name
  -v, --version VERSION  Specify a package version
  -f, --csvfile FILE     Specify a CSV file
  -u, --upload           Upload artifacts
  -h, --help             Display this help message and exit

Examples:
  ${0} --name 'John' --version '1.0' --csvfile 'data.csv'
  ${0} -n 'Jane' -v '2.1' -f 'input.csv'
EOF
    exit 0
}

options=$(getopt --name "${0}" \
    --options n:v:f:uh \
    --longoptions name:,version:,csvfile:,upload,help \
    -- "$@")
eval set -- "${options}"

while : ; do
    case "${1}" in
        -n|--name)
            packagename="${2}"
            shift 2
            ;;
        -v|--version)
            packageversion="${2}"
            shift 2
            ;;
        -f|--csvfile)
            filename="${2}"
            shift 2
            ;;
        -u|--upload)
            do_upload="YESPLEASE"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            help
            shift
            ;;
    esac
done

# fallback to target/python.csv
csv_file=${filename:-${scriptPath}/target/python.csv}

if [[ ! -f "$csv_file" ]]; then
    die "No such file: ${csv_file}"
fi

if [[ -z "${NEXUS_PASS}" ]] ; then
    die "Set up NEXUS_PASS environment variable firsts"
fi

# Read CSV contents
while IFS=, read -r number name version; do
    # filter numbers
    if [[ $number =~ ^\"[0-9]+\"$ ]] ; then
        # strip double quotes
        pname=$(echo "${name}" | tr -d '"')
        pversion=$(echo "${version}" | tr -d '"')
        packages[$pname]+="${pversion} "
        repo[$pname]="http://10.3.10.30/project-2193/${pname}"
    fi
done < "$csv_file"

if [[ $DEBUG -eq 1 ]] ;then
    #Debug output
    for package in "${!packages[@]}"; do
        info package "${package}"
        info packages "${packages[$package]}"
        info repo "${repo[$package]}"
    done
fi

for package in "${!packages[@]}"; do
    if [[ -n "${packagename}" ]] ; then
        if [[ "${packagename}" != "${package}" ]] ; then
            info "Skipping package ${package}"
            continue
        fi
    fi

    # Remove old package logs
    rm -v "${scriptPath}/logs/${package}"-*.fail

    info "Processing package: ${package}"
    source_dir="${HOME}/source/${package}"
    info "Making directory: ${source_dir}"
    mkdir -p "${source_dir}"

    if [[ -d "${source_dir}/.git" ]] ; then
        info "Source code repository already exists at ${source_dir}, skipping git clone"
    else
        info "Cloning source code from ${repo[$package]} to ${source_dir}"
        git clone "${repo[$package]}" "${source_dir}" || warn "${package} clone failed"
    fi

    pushd "${source_dir}" || die "No such directory: ${source_dir}"
    for version in ${packages[$package]} ; do
        if [[ -n "${packageversion}" ]] ; then
            if [[ "${packageversion}" != "${version}" ]] ; then
                info "Skipping package ${package} version ${version}"
                continue
            fi
        fi
        info "----------------------------------"
        if [[ -f "${scriptPath}/logs/${package}-${version}".success ]] ; then
            info "${package} was successfully built in a previous run"
            continue
        fi
        info "Trying to checkout tag: ${version}"
        if git describe "${version}" >& /dev/null ; then
            git checkout "${version}" || warn "${package} checkout to ${version} failed"
            if [[ -f .gitmodules ]]; then
               info "Updating git submodules"
               git submodule update || warn "${package} failed to update submodules"
            fi
        else
            warn "${package} tag ${version} not exists"
            continue
        fi

        venv_dir="${source_dir}/venv"
        info "Creating python venv: $venv_dir"
        python3 -m venv "${venv_dir}"

        # shellcheck disable=SC1091
        source "$venv_dir/bin/activate"
        info "Setting pypi global index url"
        python3 -m pip config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple
        python3 -m pip install --upgrade pip setuptools wheel build

        info "Building python wheel package"
        if [[ -f pyproject.toml ]] ; then
            python3 -m build || warn "${package} build failed via build"
        else
            python3 setup.py bdist_wheel || warn "${package} build failed via setuptools"
            #python3 setup.py sdist
        fi
        deactivate

        if [[ -f "${scriptPath}/logs/${package}-${version}".fail ]] ; then
            info "Process ${package} ${version} failed!"
        else
            info "Process ${package} ${version} finished！"
            touch "${scriptPath}/logs/${package}-${version}".success
        fi
        info "----------------------------------"
    done
    popd || die "No able to pop out ${PWD}"
done

if [[ "${do_upload}" == "YESPLEASE" ]] ; then
    while IFS= read -r artifact; do
        info "Uploading artifact ${artifact}"
        upload "${artifact}"
    done < <(find "${HOME}/source" -type f -name '*.whl')
fi

info "Everything is done！"
