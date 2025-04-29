# 构建脚本
## 功能说明
读取 target/python.csv中记录的软件包名和版本，完成python wheel包的构建，脚本也可通过参数传递
指定需构建的软件包名、版本信息。

## 脚本质量要求
通过shellcheck检查，无warning，无error

## 脚本逻辑
1. 解析命令行参数，指定csv、软件包名、版本，确定是否上传wheel包
2. 从csv中读取软件包名，版本，存取至数组
3. 开始循环
   1. 与命令行参数匹配软件包名、版本，确定构建范围
   2. 创建数组拼接源码仓库
   3. clone源码
   4. checkout 至指定tag
   5. 创建python venv虚拟环境
   6. 安装构建依赖
   7. 构建wheel包
4. 根据命令行参数判断是否上传wheel包

## 使用方法
1. 从源码仓库clone脚本
2. 执行脚本，建议脚本输出重定向到日志中
``` shell
git clone http://10.3.10.30/project-2193/scripts
# 构建并输出日志
scripts/build.sh | tee scripts/build-$(date +%F)-$$.log
# password 替换为仓库密码
# 指定软件包、版本构建并上传whl
NEXUS_PASS=password scripts/build.sh -u -p arrow -v apache-arrow-4.0.2 | tee scripts/build-arrow-$(date +%F)-$$.log
```

## TODO
- [ ] 增加hooks功能
  - [ ] 增加构建前软件包系统依赖检测功能
  - [ ] 增加构建前python依赖处理功能
- [x] 增加参数处理，支持
  - [x] 指定软件包名
  - [x] 指定软件版本
  - [x] 指定CVS文件
  - [x] 指定是否执行Upload操作
