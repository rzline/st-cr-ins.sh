# 酒馆+ClewdR一键脚本

- [ClewdR](https://github.com/Xerxes-2/clewdr)
- [SillyTavern](https://github.com/SillyTavern/SillyTavern)

- 如何使用

依赖安装
```
apt update &&apt install curl unzip git nodejs -y
```

运行命令
```
curl -O -C - https://raw.githubusercontent.com/rzline/st-cr-ins.sh/main/install.sh &&chmod +x install.sh &&./install.sh
```
```
#中国大陆特供版
curl -O -C - https://ghfast.top/https://raw.githubusercontent.com/rzline/st-cr-ins.sh/main/install.sh &&chmod +x install.sh &&./install.sh &&rm install.sh
```

- 把这行命令扔你终端就行，够傻瓜了吧

## 更新日志

### 25.4.8
1. 重构脚本，精简大量重复逻辑，显著减小体积
2. 优化cookie添加方式，兼容更多版本的配置文件

### 25.4.4
1. 重大更新，正式成为功能性一键脚本，目前支持一键启动，一键更新，cookie添加，端口修改四个功能
2. 添加酒馆安装功能

### 25.4.2
1. glibc用户现在可以下载musl二进制文件，解决debian系无法运行clewdr的问题
2. 删除action版本下载

### 25.4.1
1. 愚人节快乐
2. 更换版本控制逻辑，~~修复测试版安装~~失败力

### 25.3.31
1. ~~对linux服务器尝试支持自动开放8484端口，不保证可用性，可能会因为云服务器厂商的策略失效~~（放弃实现）
2. 尝试进行版本控制，添加真正的更新逻辑

### 25.3.30
1. 修改二进制文件更新方法
2. 添加是否在脚本执行结束后运行clewdr的选项