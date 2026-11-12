# 订阅 → 节点 → 代理 → TUN 验收记录

本轮对比 `fed3329`（重构前）与 `ebe50ff`（1.0.4），修复功能流程回归。**本轮不发布新正式版本：新提供的订阅已通过 Linux VM 真实出站，macOS 系统集成验收尚未通过。**

## 目标行为与实现

1. 导入订阅后展示节点；停止状态可选择手动分组和 GLOBAL 节点，按订阅 ID 保存，重启应用仍保留。自动 URLTest 分组说明由内核选优。
2. Rule/Global/Direct 控件改变真实模式：停止时保存，运行时 PATCH 后 GET 验证。
3. 开启系统代理：启动配置对应的内核 → API 就绪 → 恢复已保存节点 → 读回节点、TUN 状态 → 写系统代理并读回。旧订阅运行态不能冒充新订阅已应用。
4. 开启 TUN：停止状态也真正启动；运行状态执行普通 → TUN 事务；恢复节点选择；读回 TUN；迁移系统代理；失败回退或明确提示恢复不确定。
5. 关闭 TUN：重启普通内核并恢复节点选择；关闭系统代理仍使用已有的基线恢复事务；退出仍先恢复系统代理再停止内核。
6. 提供 Start Core 操作以便只启动内核进行测速；不隐式打开系统代理。启动错误显示给用户。

## 本轮发现与修复

- 离线节点整卡禁用：改为选择与测速分别控制。
- 离线选择缺少持久化：新增 `NodeSelectionPlan`，普通/TUN 启动共同恢复并确认。
- 节点 PUT 成功被当作完成：增加 GET 读回以及运行世代检查。
- TUN 停止状态只改开关：增加冷启动及失败清理/回退。
- 原生菜单栏启动代理重复启动内核：入口统一到 AppState；已经运行时 start 幂等。
- 节点页模式控件仅切换本地视图：接入真实模式设置和读回。
- 内核失败后继续恢复系统代理：增加就绪与订阅版本匹配检查。
- 订阅更换后显示旧核节点：运行配置关联订阅版本，页面区分已保存与已应用。
- 停止的 TUN 在 Dashboard/MenuBar 显示 active：运行状态参与文案判断。

## 已执行验证

| 范围 | 结果 |
| --- | --- |
| 实际 ProxiesView + 惰性 mock 服务 | 停止状态，手动分组 Sample 32 可点击且显示选中；GLOBAL 同样通过；测速禁用 |
| 纯生产选择策略 | 持久化、订阅隔离、普通/TUN 重启恢复、节点删除、选择失败阻止成功状态 |
| 生产冷启动/重启策略 | 启动失败先清理再回退；清理失败不谎报回退；已有重启失败恢复测试 |
| 独立 Linux ARM64 VM，mihomo v1.19.34 | 使用生产 ClashConfig 生成配置。普通 HTTP/SOCKS → TUN HTTP/SOCKS/无代理参数的直接请求 → 普通 HTTP/SOCKS 全部通过，返回选定 Node B 的响应 |
| 本地真实订阅（不提交凭据） | 普通与 TUN 合并配置均通过 mihomo -t；API 中32个VLESS节点；节点选择读回通过；TUN读回通过 |
| 第一份订阅外网 HTTPS | **未通过**，TLS连接关闭；多个节点相同。原始订阅（仅修改测试监听地址/模式）对照也失败，尚不能确定订阅服务或虚拟机网络原因 |
| 新提供的订阅（不提交地址/凭据） | 51个节点，首轮30个可测速；选择可用节点，普通HTTP/SOCKS → TUN HTTP/SOCKS/直接路由 → 普通HTTP/SOCKS均返回HTTPS 204。两节点切换并读回、各自HTTPS出站通过；使用与应用相同的flag=clashmeta参数复核通过（该轮36个节点可测速）；实际规则模式下的普通HTTP/SOCKS、TUN HTTP/SOCKS/直接路由、再切回普通模式也全部返回204。 |
| macOS networksetup / sudo / utun | **未实测**。已有事务注入测试不能替代真实 macOS 验收 |

VM 名称 `ares-flow-test`，不复用已有 `e11-secure`。仅测试 VM 内运行核心、修改路由。没有在宿主启动生产 Ares、修改代理/DNS或终止既有代理进程。私有订阅及日志只在临时目录和 VM 内处理，未提交仓库。

## 可复现的合成内核验证

在独立、可丢弃 Linux ARM64 VM 内准备 `/tmp/ares-flow/mihomo`（v1.19.34）。使用以下纯生成器输出 `normal.yaml`/`tun.yaml`，复制至 VM 的 `/tmp/ares-flow/`：

```sh
xcrun swiftc Ares/Models/ClashConfig.swift Ares/Utilities/ClashPorts.swift \
  Ares/Utilities/DefaultsKeys.swift scripts/fixtures/GenerateFlowConfig.swift -o /tmp/generate-flow
/tmp/generate-flow /tmp/output-directory
```

仅在 VM 内以 root 执行 `scripts/fixtures/core-flow-vm.py`。脚本启动两个合成 HTTP CONNECT 节点，校验选择与转发，逐个停止自身创建的核心。无真实订阅、无外部节点依赖。

## 正式发布前仍需通过

- 第一份订阅出站失败仍待定位；新提供的订阅已通过真实 HTTPS、测速、两节点切换。
- macOS 独立环境完整操作：导入 → 选节点 → 系统代理开/关 → TUN开/关 → 退出，核验原系统代理恢复。
- macOS 权限取消、端口占用、配置失败、内核意外退出，验证开关与真实状态一致。
- 核心退出恢复时的外部连接中断、provider订阅及跨订阅失败回退仍需验收。

## 本轮本地构建与回归

66项独立XCTest、6项可移植订阅解析测试（另1项本地fixture按需运行）、6项appcast测试及arm64 Release构建通过。未提升版本号、未创建发布标签。
