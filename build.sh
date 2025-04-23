#! /usr/bin/env bash
# 声明关联数组存储信息
# dnf install python3-devel gcc zlib-devel

declare -A repo
declare -A packages
declare -Ar color=(
    ['reset']='\e[0m'
    ['error']='\e[1m\e[31m'
    ['info']='\e[1m\e[32m'
    ['warn']='\e[1m\e[33m'
)

# shellcheck disable=SC2155
declare -r scriptPath=$(dirname $(readlink -f "${0}"))

# helper functions
info() {
    echo -e "${color[info]}I:${color[reset]} $*..."
}


# warn $package $stage
warn() {
    echo -e "${color[warn]}W:${color[reset]} ${1}..."
    echo "${1}" | tee -a "${scriptPath}/logs/${package}-${version}.fail"

}

# die $package $stage
die() {
    echo -e "${color[error]}E:=1=${color[reset]} $*" >&2
    exit 1
}

# Read $CSV_FILE, fallback to target/python.csv
csv_file=${CSV_FILE:-${scriptPath}/target/python.csv}

if [[ ! -f "$csv_file" ]]; then
    die "No such file: $csv_file"
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

# Remove old logs
rm -v ${scriptPath}/logs/*.fail

for package in "${!packages[@]}"; do
    info "Processing package: ${package}"
    source_dir="${HOME}/source/${package}"
    info "Making directory: ${source_dir}"
    mkdir -p "${source_dir}"

    info "Cloning source code: ${repo[$package]}"
    git clone "${repo[$package]}" "${source_dir}" || warn "${package} clone failed"

    pushd "${source_dir}" || die "No such directory: ${source_dir}"
    for version in ${packages[$package]} ; do
        info "----------------------------------"
        if [[ -f "${scriptPath}/logs/${package}.${version}".success ]] ; then
            info "${package} was successfully built in a previous run"
            continue
        fi
        info "Trying to checkout tag: ${version}"
        if git describe "${version}" >& /dev/null ; then
            git checkout "${version}" || warn "${package} checkout to ${version} failed"
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
        python3 -m pip install --upgrade pip
        python3 -m pip install build

        info "Building python wheel package"
        python3 -m build || warn "${package} build failed"
        deactivate

        if [[ ! -f "${scriptPath}/logs/${package}.${version}.fail" ]] ; then
            info "Process ${package} finished！"
            touch "${scriptPath}/logs/${package}.${version}".success
        else
            info "Process ${package} failed!"
        fi
        info "----------------------------------"
    done
    popd || die "No able to pop out ${PWD}"
done

info "Everything is done！"
