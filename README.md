# 仓库查询脚本
## 功能说明
通过curl查询 project-2193 python及java制品仓库中存储的软件。
## 使用方法
```shell
# 列出python whl包
./repolist.sh python
# 列出java jar包
./repolist.sh java
```

# 构建脚本
## 功能说明
读取 target/python.csv 或 target/java.csv 中记录的软件包名和版本，完成python wheel包或者Java jar包的构建，脚本也可通过参数传递指定需构建的软件包名、版本信息,
控制是否进行制品的upload操作。

## 脚本质量要求
通过shellcheck检查，无warning，无error

## 脚本逻辑
1. 解析命令行参数，指定csv、软件包名、版本，确定是否上传构建产物，支持wheel或者jar包
2. 从csv中读取软件包名，版本，存取至数组
3. 执行构建循环
   1. 与命令行参数匹配软件包名、版本，确定构建范围
   2. 创建数组拼接源码仓库
   3. clone源码
   4. checkout 至指定tag
   5. 依据软件包类型，创建python构建环境或者java构建环境，python使用venv，java使用jenv
   6. 安装构建依赖 (python)
   7. 构建wheel包或者jar包
   8. 根据命令行参数判断是否上传wheel包

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

## 日志输出
脚本运行输出两类日志，存放在 logs/package 目录：
1. 失败日志
  - package.fail: 标记软件包代码签出出现问题
  - package-version.fail: 记录软件包tag签出、构建等各阶段失败的记录，脚本运行前会清理
2. 成功日志
  - package-version.success: 标记软件包的某个版本构建成功，脚本下次执行会跳过该版本避免重复构建
构建日志建议使用 [使用方法](#使用方法) 中的示例通过管道执行 tee 命令重定向输出至自定义的日志文件中。

## TODO
- [-] 增加hooks功能
  - [x] 增加构建阶段hook功能
  - [ ] 增加构建前软件包系统依赖检测功能
  - [x] 增加构建前python依赖处理功能
- [x] 增加参数处理，支持
  - [x] 指定软件包名
  - [x] 指定软件版本
  - [x] ~~指定CVS文件~~
  - [x] 指定软件包类别
    - [x] python 软件包
    - [x] java 软件包
  - [x] 添加制品向指定的nexus仓库Upload的操作
