# Ares：完整发挥 mihomo 的阶段路线

核查日期：2026-11-13。基线：发布流程固定的 mihomo v1.19.34。

保持 SwiftUI + 独立内核进程。当前不引入内核 fork，不新增 MITM 功能。目标是将已支持的配置能力变成可保留、可编辑、可验证的产品能力，而不是堆满设置开关。

## 已确认的限制与本轮修复

- 已修复：原有整段删除 dns、tun、sniffer、profile 的逻辑改为 YAML 结构合并，不再因 Ares 未提供编辑器而删除订阅字段。
- 已修复：不再将 url-test interval 统一覆盖为 300 秒；保留策略组与 provider 的测速、更新参数。
- 现有候选配置已经通过内核严格校验后写入；后续应沿用该保护，不以“没有校验”作为重构前提。
- mihomo v1.19.34 的策略组解析器支持 select、url-test、fallback、load-balance；relay 已移除并提示使用 dialer-proxy。不能将其宣称为 Surge Smart Group。
- 内核提供 /providers/proxies、/providers/rules、/dns、/cache 等接口。DNS query 返回解析结果，不提供完整 DNS 决策 trace。
- 配置结构包含跨平台字段；存在字段不等于在 macOS 可用，须逐项核验平台实现。

## 交付顺序

|阶段|内容|验收|
|---|---|---|
|P0 配置保真|按字段定义应用强制管理、用户显式覆盖、订阅继承；原始文档与生效文档分离；保留未知字段；覆盖来源可追踪|复杂 DNS/TUN/sniffer/provider 配置不被静默删除；订阅更新不覆盖本地意图；候选校验与失败恢复|
|P1 规则与资源|图形化规则及顺序、规则集/provider 状态与更新、来源映射|编辑后真实命中符合预期；来源可定位；资源失败可见|
|P1 DNS|nameserver-policy、proxy-server-nameserver、direct-nameserver、hosts、Fake IP 例外与内核查询|分别验证业务域名、节点域名、直连解析；展示查询结果且不伪造完整解析链|
|P1 策略与节点资源|四类策略组、嵌套依赖、provider 更新/健康检查、过滤配置、测速参数|按组类型显示正确操作；不擅自覆盖参数；变更在内核生效|
|P2 出口与转发|dialer-proxy 代理链、出站接口、tunnels、macOS 支持的 listeners、局域网代理访问控制|依赖循环检查、端口冲突检查、实际 TCP/UDP 流量验证；不称为完整网关|
|P2 活动与诊断|真实连接策略链、规则、进程、目标、流量、资源错误关联|来自内核或明确标注的应用侧数据；策略链不冒充物理逐跳路由|
|P3 场景|公司/家庭/热点等配置覆盖组合、手动场景再到环境触发|冲突可解释、变更可恢复；明确属于 Ares 编排而非内核原生场景能力|

## 边界

Ponte、完整 DHCP/网关设备平台、Surge Smart Group 等价算法、HTTPS 改写/Mock/脚本体系不在本轮承诺。WireGuard 等协议的实际可用性与参数应按固定版本、macOS 构建逐项检查，不用最新版文档替代。

每项功能完成必须同时满足：保留配置 → 编辑配置 → 校验 → 应用 → 读取/验证结果 → 失败恢复。运行态接口不能暴露的信息应说明未知，不使用前端推测替代。

## P0 首批实现（2026-11-13，未发布）

字段优先级：运行必需字段 > 已保存的本地设置 > 订阅字段 > Ares 缺省值。原始订阅文件不改写；仅生成独立的生效文档。注释、排版和锚点写法不在生成文档中保留，锚点展开后的值、未知字段与标量类型保留。

- 运行必需字段：监听端口、控制接口/secret、模式、日志级别、LAN/IPv6 开关、进程识别、TUN enable、选择/Fake IP 持久化。TUN 模式强制 DNS enable，但保留解析策略。
- 已保存的本地设置按叶子字段覆盖：DNS nameserver/IPv6、TUN stack/MTU/device/auto-route/auto-detect-interface、keep-alive-interval、udp-timeout。普通模式明确写入 tun.enable=false，保留其他 TUN 字段但不启用。
- DNS 和 sniffer 段存在时不灌入缺省策略；段缺失时才提供 Ares 默认段。TUN/profile 补充缺少的运行默认字段。列表整体保留或替换，不拼接可能相互冲突的策略。
- 本地规则优先级保持不变；规则、MITM 节点与指纹注入均使用 YAML 结构。订阅与本地 MITM 节点重名时明确失败；无效文档、重复键、多个 YAML 文档拒绝生成，错误不携带凭据。
- 设置页只保存实际修改的字段；失败恢复时，原本不存在的偏好键仍恢复为不存在。已有版本保存过的偏好继续视为本地设置，不猜测或删除用户意图。
- 沿用候选配置内核校验与原子替换；校验失败不会覆盖旧配置。

验证：纯函数测试、YAML 包回归测试、实际 ClashConfig → 合并器的隔离集成测试、arm64 Release 编译；合成普通/TUN 配置通过 mihomo v1.19.34 `-t` 校验。未启动生产内核、未做真实网络切换验收。

## P0 第二批实现（2026-11-13，未发布）

- DNS nameserver、TUN stack/MTU/device/auto-route/auto-detect-interface 和连接计时器显示 Subscription / Ares default / Core default / Local override 来源；继承值从实际合并器生成，展开锚点，不访问内核。Core default 表示文档未配置，不猜测内核最终取值。
- 继承状态只读；铅笔操作建立本地覆盖，回退箭头恢复继承，均等待 Apply Changes。显式建立与默认值相同的覆盖也会保存；删除覆盖参与原有校验与回滚事务。
- 工具栏增加纯图标 Review Changes，展示待应用字段的前后值和目标来源。这是拟生成配置差异，不宣称为运行内核的读回值。
- 编辑期间订阅 revision 改变时阻止应用，Discard/Reload 重新载入；读取失败不伪装成默认配置。继承的高级值不经过简化表单的限制校验，仍需通过内核候选配置校验。
- 端口、LAN/IPv6 等应用管理项仍保持原有控制方式；TUN 参数明确为启用 TUN 后使用。恢复全部默认设置仍产生明确的本地默认值，不隐式恢复订阅继承。

验证：103 项纯函数测试通过；YAML 包 16 项通过、1 项可选测试跳过；隔离集成验证删除 DNS 覆盖后恢复订阅值、失败恢复原覆盖；arm64 Release 编译通过。共享来源按钮在隔离预览中验证了显示、辅助功能可访问性及恢复继承交互。

## P0 第三批实现（2026-11-13，未发布）

- Settings 工具栏新增纯图标 Verify Running Configuration。只在内核已就绪且没有网络配置操作时发起 GET /configs；超时 5 秒、不缓存、不启动或修改内核。
- 对照当前模式最后校验写入的配置文件与接口读回值，显示 Saved / Running / Result 和核对时间。结果区分 Matches、Different、Not exposed、TUN inactive、Core default；配置未指定时不猜测默认值。模式和日志的运行时修改可能合理地不同于磁盘文件，因此差异不自动视为失败，也不自动重启。
- 核对过程检查内核 generation、接口地址、订阅 revision、TUN 模式与文件内容；变化或读取失败时不产生成功结果。界面里的待保存编辑不参与运行核对。
- 核对仅包含 mihomo v1.19.34 General 接口公开的白名单字段；DNS、规则、provider 等段不展示值，仅说明该接口未公开。此核对不替代 /rules、/providers 等后续专项验收，不导出节点密码或订阅 URL。
- 候选配置验证与原子写入抽取为生产共用的 ValidatedConfigurationFile。真实临时文件测试覆盖验证拒绝、验证抛错、验证后取消和成功提交，失败均保留旧文件并清除候选文件。

验证：106 项纯函数/文件测试通过；YAML 包 21 项通过、1 项可选测试跳过；模拟 HTTP 测试通过 GET-only、503 失败、内核 generation 和端口变更竞争场景；arm64 Release 编译通过。共享核对表完成隔离预览检查，未调用本机生产内核接口或更改系统网络。

## P0 第四批实现（2026-11-13，未发布）

- Inspect Configuration 菜单新增 Subscription → Saved Configuration，递归比较完整文档，忽略注释/映射键顺序，保留列表顺序意义。添加、删除、嵌套变化按叶子呈现，不截断数量。未知自定义键、名称和敏感值隐藏；即使隐藏值发生变化仍保留变化条目。此视图不是逐字段来源追踪，也不是待应用配置或订阅更新的预览。
- 设置应用前捕获上一份已保存配置，验证后的新配置直接交给启动流程；启动失败时恢复捕获内容，不从可能已更新的订阅重建旧配置。停止失败不启动另一个内核，文件恢复失败明确报告。捕获的是保存文件，尚未建立持久化的“已验证运行成功”版本库。
- 在专用 ares-flow-test Linux arm64 虚拟机运行 mihomo v1.19.34，使用实际 ClashConfig + EffectiveConfiguration 生成的合成配置。测试普通 → TUN → 普通，Node B 选择与读回、HTTP/SOCKS 和 TUN 真实流量；无效 reload 被拒绝且原流量继续；强制终止后端口释放、重启恢复；正常退出后端口关闭和 TUN 接口移除。虚拟机测试结束已关闭，宿主机代理及路由未操作。

验证：106 项纯函数/文件测试通过；YAML 包 25 项通过、1 项可选测试跳过；arm64 Release 编译通过。VM 测试是 Linux 内核行为验收，不代表 macOS App 的权限、休眠、升级或系统代理切换已验收。

尚未完成的 P0：持久化成功配置版本与来源记录、统一跨入口应用事务、macOS 特权/系统代理/休眠唤醒和升级的完整运行验收。只有这些基础闭环满足要求后才发布基础稳定版本，再进入规则/provider 功能扩展。

## 证据

- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/config/config.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/route/server.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/route/provider.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/route/dns.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/adapter/outboundgroup/parser.go

读回字段依据：
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/route/configs.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/executor/executor.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/listener/config/tun.go

## 基础阶段集中收敛（2026-11-13）

后续以大阶段验收，不再按单文件改动交付。设置、订阅、TUN、重启已接入共同切换流程；新增私有持久化成功快照和显式恢复入口、关键配置启动核验、运行模式/日志快照更新、恢复后真实端口同步、休眠唤醒检查及实例级退出处理。

阶段验收与发布门槛统一记录在 [foundation-acceptance.md](foundation-acceptance.md)。本批通过隔离自动测试及 macOS 原生回环内核测试；macOS 真实 TUN/系统代理/整机休眠及实际升级安装仍需隔离主机验收，不能跳过后直接发布“基础稳定版”。

## 退出收敛与规则/资源阶段（2026-11-13，未发布）

- 退出共用可验证的交接状态：成功后一直阻止新操作，普通退出不重复清理；失败解锁重试；Sparkle 等待清理期间中止不会执行过期安装回调。正常退出使用可读回、失败可回滚的异步代理恢复。
- 显式恢复增加完整行为验收：快照缺失、订阅不符、捕获失败、验证失败、停止失败、无运行内核、激活/代理恢复失败与清理失败。
- Rules 保留内核 index 顺序，读取 `extra.hitCount`，未公开计数显示横线。失效响应不覆盖新内核数据；获取失败不伪装成成功空列表。
- 本地规则编辑使用独立草稿，取消不保存；订阅 revision 校验后通过共享配置事务应用，失败恢复原偏好（包括未设置），停止状态只校验保存。仍为文本编辑，不宣称图形化逐条编辑/拖动排序已完成。
- Rule Sets 展示实际 behavior、vehicleType、ruleCount、updatedAt，支持单项更新与读回，Inline 不提供下载操作。名称安全编码，HTTP 失败可见，内核切换使旧列表失效；可查看顶层 RULE-SET 引用，不伪造嵌套规则来源。
- macOS 原生回环内核验收新增 HTTP 规则集下载更新、计数读回及实际 RULE-SET 流量命中。合成资源使用本地服务器，不访问用户订阅、不更改系统代理或 TUN。

剩余执行顺序：规则图形化编辑/顺序与完整来源映射 → 策略组及 proxy-provider 管理 → DNS 与诊断 → 链路/监听/接口 → 场景组合。基础阶段的真实 macOS 特权和签名升级验收仍单独保留；不因进入可隔离实现的规则工作而标记这些项目完成。

接口依据：
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/route/rules.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/hub/route/provider.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/rules/provider/provider.go

## 规则编辑与来源检查（2026-11-13，未发布）

- 本地规则新增列表/源码编辑：逐条新增、编辑、删除、上移/下移；常见类型使用表单，复杂或无法无损投影的表达式使用源码。未修改行、注释、空行、重复规则保留；顺序操作仅交换规则行，不自动移动相邻注释。
- MATCH 遮挡后续规则时显示提示；最终语义仍由固定版本内核验证。编辑期间订阅 revision 或本地规则变化会拒绝旧草稿覆盖。
- Rule Sources 从当前已验证配置快照提取规则，包含全部顶层规则、全部 sub-rules 段及嵌套 RULE-SET 引用；来源通过订阅尾部/本地前缀的顺序核对，不能确认时标为 Verified configuration。提供快照时间，不将这些静态行冒充实时命中统计。
- Rule Sets 增加 Inspect all references；来源视图只投影规则，不暴露 provider URL 或代理凭据。远端规则集内部内容未下载展开；表达式解析遇到防御深度上限或格式问题会明确提示。
- 隔离原生内核验证真实规则顺序、嵌套 RULE-SET、SUB-RULE 流量；源码/表单无损转换、重复规则、引用与来源失配均有测试。
- 原生界面验证新增、移动、源码同步与来源快照。修复窄布局下 Editor 标签折行：隐藏冗余视觉标签、保留辅助功能名称，固定标题和操作按钮的自然尺寸；长资源名称单行中间截断并保留完整提示。

本批验收：122 项基础测试通过；SubscriptionKit 33 项通过、1 项可选跳过；配置协调器及草稿冲突测试通过；隔离原生回环测试通过；arm64 Release 编译通过。未替换安装 App，未操作宿主机系统代理/TUN。

## 策略组与节点资源阶段（2026-11-13，未发布）

- Proxies 工具栏新增 Policy Groups 与 Node Resources，沿用原生表格、紧凑操作和稳定标题布局。
- Policy Groups 展示订阅组类型、显式 provider 引用和匹配当前订阅的运行成员快照；全部成员边参与检查，循环/缺失成员可见。负载均衡不再当作单一当前出口；成员关系不冒充物理路由。
- 已有组支持按类型覆盖 interval、timeout、tolerance、lazy、filter、exclude-filter、strategy；本地覆盖按订阅 UUID 隔离，未选中字段继承，恢复继承也走验证/应用/回滚。未知字段、探测 URL 与 provider 更新周期保留。未知/不存在的组不自动创建，类型改变后不兼容覆盖明确验证失败。
- 参数 UI 提供布尔/策略选择，时间单位明确；编辑时核对订阅 revision 和原始覆盖值，失败恢复缺省键的缺失状态。当前不包含新增/删除组及任意依赖重连编辑。
- Node Resources 展示真实来源、成员数量、更新时间及逐节点测量值/时间；HTTP/File 可更新，Inline/Compatible 不伪装下载。健康检查使用内核 provider 配置；接口成功只表示请求完成，不保证每个节点可用。超时后提示刷新确认，不重复后台触发。
- 更新/检查读回当前资源和 proxy 快照，淘汰受影响成员的旧应用测速缓存。每个请求核对 runtime generation/endpoint，过期结果不写回；全局操作门禁避免与配置切换并行。
- 原生回环 mihomo 验证四类组类型、嵌套选择、URLTest/Fallback 固定与恢复自动、负载均衡实际流量、HTTP provider 更新、新节点出现与选择，以及健康历史。测试 HTTP 代理显式实现 CONNECT 且仅允许连接本地测试 origin，未访问用户节点。
- Fallback 对不健康的固定节点会在读回时恢复自动，这是内核行为；应用仍要求选择读回确认，不能把 HTTP 204 当成持续固定成功。

验收：127 项基础测试通过；SubscriptionKit 37 项通过、1 项可选跳过；策略参数生产事务模拟（成功、验证失败、激活/清理失败、草稿冲突、停止状态）通过；资源 HTTP 方法/名称编码/503/过期响应测试通过；普通/TUN 合成参数配置通过 v1.19.34 -t；arm64 Release 编译通过。真实界面用独立 mock 预览检查。宿主系统代理、TUN 与安装 App 未操作。

下一阶段：DNS 配置与查询诊断。真实 macOS 特权、系统代理切换和签名升级发布验收仍保持未完成，不因本阶段通过而替代。

依据：
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/adapter/outboundgroup/parser.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/adapter/outboundgroup/fallback.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/adapter/provider/provider.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/adapter/provider/healthcheck.go

## DNS 配置与查询阶段（2026-11-13，未发布）

- Settings → DNS → Configuration & Query，以及 Inspect Configuration 菜单进入同一视图；基本设置存在未应用草稿时先要求处理草稿，避免两个编辑器混用配置。
- 15 项高级字段：域名/节点域名策略、节点/直连/引导/备用解析器、备用过滤、DNS 模式、Fake IP 过滤与模式、respect-rules、hosts 与系统 hosts 开关。列表/映射按字段 YAML 编辑；布尔/模式使用原生控件，不修改应用管理的 enable/listen/nameserver/IPv6。
- 按订阅 UUID 保存本地覆盖。显示 Subscription / App default / Core default / Local override；关闭覆盖恢复继承。仅生成生效配置，不改写订阅。字段类型、重复键、非法文档先检查，再通过固定内核严格校验和统一切换/回滚事务。
- /dns/query 展示完整 Answer/Authority/Additional、记录类型、TTL 秒、RCODE、截断标记、查询时间和应用测得的 API 往返毫秒。NXDOMAIN、成功无记录、请求失败分开处理。修改输入、切换订阅/内核、离开查询页会失效或取消旧请求。
- 明确边界：该接口访问通用 resolver，不报告实际上游，也不模拟 direct-nameserver/proxy-server-nameserver、hosts/Fake IP 分配路径；不伪造 DNS 决策链。DNS 页面复杂字段当前是按字段 YAML 编辑器，并非完整可视化策略构建器。
- 验证：127 项安全测试通过；包测试 42 通过、1 可选跳过；真实配置普通/TUN 两种生成结果均通过 v1.19.34 `-t`；隔离事务覆盖提交、验证失败、启动失败、清理失败、过期草稿与停机保存；HTTP 替身覆盖错误、空结果、NXDOMAIN 和运行代次竞争。
- 原生隔离内核 + 4 个本地 UDP DNS fixture + 本地 HTTP origin 验证：A/AAAA/TTL、域名策略命中、NXDOMAIN/空响应，以及实际 HTTP 直连/代理流量分别使用 direct-nameserver / proxy-server-nameserver。所有临时监听与进程退出后回收，没有修改系统 DNS/代理/TUN。
- Release 编译和实际 SwiftUI 隔离预览通过；740×540 内容区检查标题、tab、编辑器、继承开关和查询输入，没有拆字。未替换用户应用，未发布。下一阶段进入代理链、出站接口、监听与转发。

## 出口、监听与转发阶段（2026-11-13，未发布）

- Settings → Traffic / Inspect Configuration 新增 Routing & Listeners。Outbounds 按节点编辑 dialer-proxy / interface-name；默认出站接口独立覆盖。关闭覆盖恢复继承，空的节点接口表示继承全局接口。接口名单来自系统，应用时核对接口存在。
- 覆盖按订阅 UUID 保存。节点重命名/删除后保留草稿并提供 Remove stale overrides，应用时明确拒绝丢失目标，不静默忽略。只投影静态节点名称、类型、dialer 和接口，不把节点账号/凭据带入列表；provider 管理的节点仍由资源负责。
- 完整静态依赖检查包含节点 dialer 和组的所有显式成员，可发现“节点 → 策略组 → 节点”循环。动态 provider 成员依赖不冒充完整可验证图，仍由内核校验。
- Listeners 支持 HTTP/SOCKS/Mixed 的显式 IP + 单端口编辑；Forwarding 支持 TCP/UDP 固定转发。当前使用独立 YAML 段编辑器，整段覆盖并保留未知字段/认证/TLS，不是完整表单构建器。未覆盖的其他监听协议、端口范围保留；不宣称支持跨平台透明网关。
- 新增校验：端口范围、协议、重复监听名称、代理/子规则引用、静态循环、与应用端口/API/DNS/其他监听的冲突。只操作本地配置和候选文件，不关闭占用端口的第三方进程。
- 启动后的额外监听检查通过 lsof 核对协议、地址、端口属于同一个拥有控制 API 的 Ares 内核 PID；不能确认则启动失败并走现有恢复流程。普通用户读取不足时仅尝试已有 sudo -n 授权，不新增授权提示。支持的单端口监听和 tunnels 纳入此检查；复杂继承监听不宣称全覆盖。系统端口竞争仍以实际激活结果为准，-t 本身不能证明绑定成功。
- 全局 interface-name 加入 /configs 读回验证。macOS 内核有 IP_BOUND_IF / IPV6_BOUND_IF 支持，但回环测试不证明物理网卡切换与多网卡路由，后者保留在隔离 macOS 验收范围。

验证：127 项安全测试通过；SubscriptionKit 49 通过、1 可选跳过；路由事务提交、验证/激活/清理失败回滚、过期草稿、停止状态保存测试通过。正常/TUN 合成配置均通过 v1.19.34 -t。独立原生内核实际验证 Entry → Exit → HTTP origin 两级代理链、HTTP 认证拒绝/成功、listener 的 DIRECT 指定出口、SOCKS TCP/UDP、固定 TCP/UDP 转发，以及生产监听归属校验器。740×560 实际 SwiftUI 预览检查标题/控件/编辑器；arm64 Release 编译通过。未替换 App、未修改系统网络、未发布。

下一阶段：活动诊断整合与手动场景。先建立可解释、可恢复的配置组合，再增加环境触发。

依据：
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/adapter/outbound/base.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/listener/inbound/base.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/listener/parse.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/listener/config/tunnel.go
- https://github.com/MetaCubeX/mihomo/blob/v1.19.34/component/dialer/bind_darwin.go

## 活动诊断与手动场景（2026-11-13，未发布）

- Activity 工具栏新增 Diagnostics。按一次读取批次展示订阅 revision、已验证运行快照与保存文件差异、/configs 可读字段、策略成员依赖、节点资源历史测量和规则资源数量。部分接口失败单独显示；运行代次/订阅变化或停止时清空旧快照，拒绝晚到响应。不发送测速，不将历史结果当作实时健康、不将成员关系当物理路由。
- Diagnostics 的 Inspect 汇合 DNS 查询、规则来源、节点资源和 Scenes。证据列可选择后在下方查看完整内容，保留时间戳和 API 未暴露字段数量。
- Settings → Inspect → Scenes 支持保存当前覆盖、按当前订阅列出、删除、切换前区块级差异确认、应用和撤回上次切换。每个场景包含本地规则、DNS、策略组、出站/监听覆盖；不包含基本网络设置、订阅原文、节点选择、代理/TUN 开关。当前是第一版手动配置组合，不是自动环境切换。
- 订阅 UUID 绑定；保存时核对原设置与 revision，切换时重新核对 review 基线。订阅更新后允许明确提示并对当前内容重建、内核验证；移除节点/错误配置失败恢复。全局 localRules 的影响在确认页明确说明。
- 运行中通过共享 coordinator 重新启动并验证，失败恢复全部四类偏好，包括原本不存在的键；停止时只验证保存。撤回保留在本次应用会话中；相关偏好或订阅 revision 变化后失效，不覆盖后续编辑。匹配标记仅表示已保存设置相同，不代表内核健康。
- 场景库存放在独立 0700 目录、0600 原子文件，含版本校验；损坏库不当成空库覆盖。同订阅名称不区分大小写去重。诊断/差异视图不输出覆盖文档或凭据。

验收：131 项安全测试通过；包测试 49 通过、1 可选跳过。事务替身覆盖场景应用/撤回、多区块准备/激活/清理失败、过期 review、跨订阅、停止状态，以及后续编辑/订阅更新使撤回失效。诊断替身验证配置差异、未测量与历史测量区分、部分失败、过期代次与停止状态。组合配置测试验证场景保存值进入 policy/DNS/egress 合并并恢复继承；合成普通/TUN 配置通过固定内核 -t。真实 SwiftUI 隔离预览检查场景列表、差异确认、诊断及关联入口；arm64 Release 编译通过。未替换安装 App、未修改系统网络、未发布。

后续优先：将场景扩充为可编辑的配置组合、关联节点选择和模式；随后增加有冲突解释与防抖的环境触发。先完成隔离 macOS 的特权/TUN/系统代理/签名升级验收，再安排生产发布。
