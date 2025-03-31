# clewdr-install.sh

- [clewdr地址](https://github.com/Xerxes-2/clewdr)没有它就没有这个脚本存在的必要了

- 如何使用

```
wget https://raw.githubusercontent.com/rzline/clewdr-install.sh/refs/heads/main/install.sh &&chmod +x install.sh &&./install.sh
```

```
#中国大陆特供版
wget https://ghfast.top/https://raw.githubusercontent.com/rzline/clewdr-install.sh/refs/heads/main/install.sh &&chmod +x install.sh &&./install.sh
```

- 把这行命令扔你终端就行，够傻瓜了吧

- 由于还是有点不够傻瓜，特添加启动命令教学

```
#这就是执行命令，上面的命令完成了运行这个就可以启动clewdr了
./clewdr/clewdr
```

- 傻瓜教学再次更新
这次直接在脚本里添加了是否运行的选项，要是还不行我也没辙

### 更新日志

- 25.3.30
1. 修改二进制文件更新方法
2. 添加是否在脚本执行结束后运行clewdr的选项

- 25.3.31
1. 对linux服务器尝试支持自动开放8484端口，不保证可用性，可能会因为云服务器厂商的策略失效
2. 尝试进行版本控制，添加真正的更新逻辑