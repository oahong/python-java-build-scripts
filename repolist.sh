#!/usr/bin/env bash
# 脚本使用kimi生成，再次基础上进行健壮性调整
# 系统需安装 curl 及 jq
# REF: https://help.sonatype.com/en/search-api.html
nexus_url_prefix="http://10.3.10.189:8081/service/rest/v1/search/assets?repository=project-2193"

username=wxiat
password="${NEXUS_PASS}"

if [[ "$#" -ne 1 ]] ; then
    echo "Usage: $0 [python|java]"
    exit 0
else
    type="${1}"
fi
# 初始化 continuationToken 为空
continuationToken=""

while true; do
    # token 为 null 时停止后续请求
    if [[ "${continuationToken}" == "null" ]] ; then
        break
    fi

    # 如果 continuationToken 不为空，添加到查询参数中
    if [ -n "$continuationToken" ]; then
        query_url="${nexus_url_prefix}-${type}&continuationToken=${continuationToken}"
    else
        query_url="${nexus_url_prefix}-${type}"
    fi

    # Java查询时过滤出 jar 包
    if [[ "${type}" == "java" ]] ; then
       query_url+="&maven.extension=jar"
    fi

    # 发送请求并解析 JSON 响应
    response=$(curl -s -u "$username":"$password" -X GET "$query_url" -H "Accept: application/json")

    # 提取 continuationToken 和 items
    continuationToken=$(echo "$response" | jq -r '.continuationToken')
    items=$(echo "$response" | jq '.items')

    # 输出当前页的 whl 包信息
    echo "$items" | jq -c '.[]' | while read -r item; do
        echo "$item" | jq -r '.path'
    done

    # 如果 continuationToken 为空，说明已经是最后一页，退出循环
    if [ -z "$continuationToken" ]; then
        break
    fi
done
