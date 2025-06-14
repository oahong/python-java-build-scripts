#! /usr/bin/env bash
#
# Prebuilt dependencies
# dnf install python3-devel gcc zlib-devel gcc-c++ libjpeg-turbo-devel cmake \
# ninja-build python3-meson-python
# lxml: libxml2-devel and libxslt-devel

declare -A repo
declare -A packages
# A list of available stages in the build workflow
declare -r stages=(
    'clone'
    'checkout'
    'submodules'
    'env-setup'
    'build'
    'upload'
)
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
    # Remove trailing dash from varable ${package_log_prefix}
    # in case ${version} is unset during clone phase
    echo "${1}" | tee -a "${package_log_prefix%-}".fail
}

# die $package $stage
die() {
    echo -e "${color[error]}E:=1=${color[reset]} $*" >&2
    echo "${1}" | tee -a "${package_log_prefix%-}".err
    exit 1
}

invoke_hook_command() {
    local stage="${1}"
    local dir="${2:-${source_dir}}"

    local stageHook="${scriptPath}/hooks/post-${stage}"

    for s in "${stages[@]}"; do
        if [[ "${s}" == "${stage}" ]]; then
            if [[ -f "${stageHook}" ]]; then
                info "Inovke hook script in stage ${stage}"
                eval "${stageHook}" "${dir}" || true
            fi

            if [[ -f "${stageHook}.d/${package}" ]]; then
                info "Inovke hook.d script in stage ${stage}"
                eval "${stageHook}.d/${package}" "${dir}" || true
            fi
        fi
    done
}

help() {
    cat <<EOF
Usage: ${0} [OPTIONS]
A script to build python packages

Options:
  -n, --name NAME        Specify a package name
  -v, --version VERSION  Specify a package version, should match a valid git tag
  -u, --upload           Upload artifacts to sonatye nexus repository
  -t, --type             Package type, either be python or java (default is python)
  -h, --help             Display this help message and exit

Examples:
  # build a python package
  ${0} --name gevent --version 21.1.2 --type python
  # build a series of java packages
  ${0} -n netty-tcnative -t java
  # Build a series of java packages, upload artifacts to nexus
  ${0} -n netty-tcnative -t java -u
EOF
    exit 0
}

setup_python_build_env() {
    local venv_dir="${source_dir}/venv"

    info "Creating python venv: ${venv_dir}"
    python3 -m venv "${venv_dir}"

    # shellcheck disable=SC1091
    source "${venv_dir}/bin/activate"
    #FIXME: The local repository should have higher priority: dependencies should be
    #FIXME  downloaded from the local repository first, with the public repository as a fallback.
    info "Setting pypi global index url and extra-index-url"
    python3 -m pip config set global.index-url http://nexus.wxiat.com:8081/repository/project-2193-python-group/simple
    python3 -m pip install --upgrade pip setuptools wheel build cython
    python3 -m pip config set global.trusted-host nexus.wxiat.com
    python3 -m pip config set global.extra-index-url http://nexus.wxiat.com:8081/repository/project-2193-python/simple

    invoke_hook_command env-setup "${venv_dir}"
}

setup_java_build_env() {
    local jenv_dir="${HOME}"/.jenv

    if [[ -d "${jenv_dir}" ]]; then
        info "Skip creating jenv environment"
    else
        info "Creating jenv environment: ${jenv_dir}"

        git clone http://10.3.10.30/project-2193/jenv "${jenv_dir}"
        if ! grep -wq jenv "${HOME}"/.bashrc; then
            cat <<EOF
echo 'export PATH="$HOME/.jenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(jenv init -)"' >> ~/.bashrc
source ~/.bashrc
EOF
            die "Please set up jenv in your bashrc as mentioned above!"
        fi
        jenv add /usr/lib/jvm/java-1.8.0-openjdk
        jenv add /usr/lib/jvm/java-11-openjdk
        jenv enable-plugin maven
        jenv enable-plugin gradle
    fi

    invoke_hook_command env-setup "${jenv_dir}"
}

build_python_package() {
    local distdir="dist/${version}"

    info "Building python wheel package"
    if [[ -f pyproject.toml ]]; then
        python3 -m build -o "${distdir}" || warn "${package} build failed via build"
    else
        python3 setup.py bdist_wheel -d "${distdir}" || warn "${package} build failed via setuptools"
        #python3 setup.py sdist
    fi
    invoke_hook_command build
    deactivate
}

build_java_package() {
    info "Building java package"
    if [[ -f build.gradle ]]; then
        gradle -x test clean build jar || warn "${package} build failed via gradle"
    elif [[ -f pom.xml ]]; then
        mvn clean package -X -e -DskipTests=true || warn "${package} build failed via maven"
    fi
    invoke_hook_command build
}

upload_python_artifacts() {
    if [[ "${do_upload}" != "YESPLEASE" ]]; then
        return 0
    fi
    while IFS= read -r artifact; do
        if [[ -z "${artifact}" ]]; then
            warn "No artifcat found for ${PN}-${PV}, skip artifact uploading"
            return 0
        fi

        info "Uploading python artifact ${artifact}"
        curl -v -u "${NEXUS_USER:-wxiat}:${NEXUS_PASS}" \
            -X POST -H "Content-Type: multipart/form-data" \
            -F "pypi.asset=@${artifact}" \
            "http://nexus.wxiat.com:8081/service/rest/v1/components?repository=project-2193-python" ||
            die "Failed to upload artifacts"
        invoke_hook_command upload
    done < <(find "${source_dir}/dist/${version}" -type f -name "*.whl")
}

upload_java_artifacts() {
    if [[ "${do_upload}" != "YESPLEASE" ]]; then
        return 0
    fi
    if [[ -f build.gradle ]]; then
        ./gradlew publish \
            -PnexusUrl=http://nexus.wxiat.com:8081/repository/project-2193-java \
            -PnexusUsername="${NEXUS_USER:-wxiat}" \
            -PnexusPassword="${NEXUS_PASS}" \
            die "Failed to publish artifacts"
    elif [[ -f pom.xml ]]; then
        mvn deploy \
            -DaltDeploymentRepository=nexus-repo::default::http://nexus.wxiat.com:8081/repository/project-2193-java \
            -Dusername="${NEXUS_USER:-wxiat}" \
            -Dpassword="${NEXUS_PASS}" \
            -DskipTests=true ||
            die "Failed to deploy artifacts"
    fi
    invoke_hook_command upload
}

options=$(getopt --name "${0}" \
    --options n:v:ut:h \
    --longoptions name:,version:,upload,type:,help \
    -- "$@")
eval set -- "${options}"

while :; do
    case "${1}" in
    -n | --name)
        packagename="${2}"
        shift 2
        ;;
    -v | --version)
        packageversion="${2}"
        shift 2
        ;;
    -u | --upload)
        do_upload="YESPLEASE"
        shift 1
        ;;
    -t | --type)
        package_type="${2}"
        shift 2
        ;;
    --)
        shift 1
        break
        ;;
    *)
        help
        ;;
    esac
done

if [[ -z "${NEXUS_PASS}" ]]; then
    die "Set up NEXUS_PASS environment variable firsts"
fi

# Package type will fallback to python if not specified in the command line
if [[ -z "${package_type}" ]]; then
    package_type=python
fi

# fallback to target/${package_type}.csv
csv_file=${scriptPath}/target/${package_type}.csv

if [[ ! -f "$csv_file" ]]; then
    die "No such file: ${csv_file}"
fi

# Read CSV
while IFS=, read -r number name version; do
    # filter numbers
    if [[ $number =~ ^\"[0-9]+\"$ ]]; then
        # strip double quotes
        pname=$(echo "${name}" | tr -d '"')
        pversion=$(echo "${version}" | tr -d '"')
        packages[$pname]+="${pversion} "
        repo[$pname]="http://10.3.10.30/project-2193/${pname}"
    fi
done <"$csv_file"

if [[ $DEBUG -eq 1 ]]; then
    #Debug output
    for package in "${!packages[@]}"; do
        info package "${package}"
        info packages "${packages[$package]}"
        info repo "${repo[$package]}"
    done
fi

for package in "${!packages[@]}"; do
    if [[ -n "${packagename}" ]]; then
        if [[ "${packagename}" != "${package}" ]]; then
            info "Skipping package ${package}"
            continue
        fi
    fi

    info "Processing package: ${package}"
    source_dir="${HOME}/source/${package}"
    info "Making directory: ${source_dir}"
    mkdir -p "${source_dir}"

    if [[ -d "${source_dir}/.git" ]]; then
        info "Source code repository already exists at ${source_dir}, skipping git clone"
    else
        info "Cloning source code from ${repo[$package]} to ${source_dir}"
        git clone "${repo[$package]}" "${source_dir}" || die "${package} clone failed"
    fi
    invoke_hook_command clone

    pushd "${source_dir}" || die "No such directory: ${source_dir}"
    for version in ${packages[$package]}; do
        if [[ -n "${packageversion}" ]]; then
            if [[ "${packageversion}" != "${version}" ]]; then
                info "Skipping package ${package} version ${version}"
                continue
            fi
        fi

        package_log_prefix=${scriptPath}/logs/${package}/${version/\//_}
        mkdir -pv "$(dirname "${package_log_prefix}")"

        # Remove old fail log
        rm -fv "${package_log_prefix}".{fail,err}

        info "----------------------------------"
        if [[ -f "${package_log_prefix}".success ]]; then
            info "${package} was successfully built in a previous run"
            continue
        fi
        info "Trying to checkout tag: ${version}"
        git fetch --all || die "${package} git fetch failed"
        if git describe --all "${version}" >&/dev/null; then
            git checkout --force "${version}" || die "${package} checkout to ${version} failed"
            if [[ -f .gitmodules ]]; then
                info "Updating git submodules"
                git submodule update --init --recursive --force || die "${package} failed to update submodules"
            fi
        else
            warn "${package} tag ${version} not exists"
            continue
        fi
        invoke_hook_command checkout

        case "${package_type}" in
        python)
            setup_python_build_env
            build_python_package
            upload_python_artifacts
            ;;
        java)
            setup_java_build_env
            build_java_package
            upload_java_artifacts
            ;;
        esac

        if [[ -f "${package_log_prefix}".fail ]]; then
            info "Process ${package} ${version} failed!"
        else
            info "Process ${package} ${version} finished!"
            touch "${package_log_prefix}".success
        fi
        info "----------------------------------"
    done
    popd || die "No able to pop out ${PWD}"
done

info "Everything is done!"
