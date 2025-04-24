# 构建脚本
## 功能说明
读取 target/python.csv中记录的软件包名和版本，完成python wheel包的构建

## 脚本质量要求
通过shellcheck检查，无warning，无error

## 脚本逻辑
1. 从csv中读取软件包名，版本，存取至数组
2. 开始循环
   1. 创建数组拼接源码仓库
   2. clone源码
   3. checkout 至指定tag
   4. 创建python venv虚拟环境
   5. 安装构建依赖
   6. 构建wheel包
3. 上传wheel包

## 使用方法
1. 从源码仓库clone脚本
2. 执行脚本，建议脚本输出重定向到日志中
``` shell
git clone http://10.3.10.30/project-2193/scripts
# password 替换为 nexus 指定账号密码
NEXUS_PASS=password scripts/build.sh | tee scripts/build-$(date +%F)-$$.log
# password 替换为 nexus 指定账号密码
NEXUS_PASS=password scripts/build.sh -p arrow -v apache-arrow-4.0.2 | tee scripts/build-arrow-$(date +%F)-$$.log
```

## TODO
- [ ] 增加hooks功能，针对软件包增加独立处理功能
- [x] 脚本跟参数，指定软件包名和/或版本
