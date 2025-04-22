#! /usr/bin/env bash
# 声明关联数组存储信息

set -e

declare -A no
declare -A pver
declare -A repo

csv_file="target/python.csv"

# 检查CSV文件是否存在
if [[ ! -f "$csv_file" ]]; then
    echo "错误：未找到文件 $csv_file" >&2
    exit 1
fi

# 读取CSV内容到关联数组
while IFS=, read -r current_no pname current_pver; do
    # 去除值中的空格
    pname=$(echo "$pname" | xargs)
    no[$pname]=$(echo "$current_no" | xargs)
    pver[$pname]=$(echo "$current_pver" | xargs)
    repo[$pname]="https://10.3.10.30/project-2193/$pname"
done < "$csv_file"

# die $pname $stage
die() {
    echo $1 stage $2 failed | tee -a $2.failed
    continue
}

# 处理每个项目
for pname in "${!no[@]}"; do
    echo "正在处理项目: $pname"

    # 步骤4：在~/source下创建项目目录
    source_dir="$HOME/source/$pname"
    echo "创建目录: $source_dir"
    mkdir -p "$source_dir"

    # 步骤5：克隆仓库到项目目录
    echo "克隆仓库: ${repo[$pname]}"
    git clone "${repo[$pname]}" "$source_dir" || die $pname git-clone

    # 进入项目目录
    pushd "$source_dir"

    # 步骤6：切换到指定版本
    echo "切换到版本: ${pver[$pname]}"
    git checkout "${pver[$pname]}" || die $pname git-checkout

    # 步骤3：在项目目录中创建虚拟环境
    venv_dir="$source_dir/venv"
    echo "创建虚拟环境: $venv_dir"
    python3 -m venv "$venv_dir"

    # 步骤7：构建项目（在虚拟环境中执行）
    echo "开始构建..."
    source "$venv_dir/bin/activate"
    python3 -m pip config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple
    python3 -m pip install --upgrade pip
    python3 -m pip install build
    python3 -m build || die $pname whl-build
    deactivate

    echo "项目 $pname 处理完成！"
    echo "----------------------------------"
done

echo "所有项目处理完毕！"
