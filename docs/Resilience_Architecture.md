# Antigravity Resilience Protocol (ARP) 架构设计方案

> **状态**: 草案 (Draft)
> **目标**: 解决 Agent 在复杂网络环境下的 TCP 抖动、DPI 识别及大包传输中断问题。
> **核心策略**: 引入用户态网络栈 (User-space Network Stack) 接管连接管理，实现“应用层无感知的底层重连”。

---

## 1. 核心问题分析

您提供的资料中提到的三个痛点，本质上是标准操作系统内核网络栈（Kernel Network Stack）在面对现代复杂网络环境时的局限性：

1.  **内核太"诚实"**：收到 RST 包（连接重置）或 FIN 包，内核会立即通知应用程序断开连接。对于长时间运行的 AI Agent 任务，这会导致前功尽弃。
2.  **指纹太"标准"**：标准库（如 Swift Network, Go `net/http`）发出的 TLS 握手包特征非常固定，极易被防火墙识别。
3.  **拥塞控制太"保守"**：默认的 Cubic/Reno 算法在遇到丢包时会剧烈降低发送窗口，导致大 Payload 传输卡顿甚至超时。

## 2. 解决方案：引入 "Resilience Sidecar" (韧性边车)

既然由于内核的局限性导致问题，我们的方案是**跳过内核**，引入一个基于 **用户态网络栈 (User-space Networking)** 的中间层。

推荐引入框架：**gVisor (Google)** 的 `netstack` 组件 或 **Smoltcp** (Rust)。考虑到 Ares 后端主要可能是 Swift/Go 混合，使用 Go 编写一个微服务 Sidecar 是最可行的。

### 架构图解

```mermaid
[Antigravity Agent (App)]
       │
       ▼ HTTP/WebSocket (明文或标准TLS)
[ 🛡️ Resilience Sidecar (本地微服务/进程内模块) ]  <-- 新引入的核心组件
       │  1. 影子状态机 (Shadow TCP)
       │  2. 拟态 TLS (uTLS)
       │  3. 弹性缓冲 (Elastic Buffer)
       │
       ▼ 加密混淆流量
[ macOS Network Interface (en0/Wi-Fi) ]
       │
       ▼
[ 公司网关 / GFW / 复杂网络 ]
       │
       ▼
[ 远端代理服务器 (Server) ]
```

---

## 3. 详细功能模块设计

### 3.1. 针对“TCP 抖动”：Shadow-TCP (影子状态机)

**原理**：
在 Sidecar 中维护一个虚拟的 TCP 状态机。当物理网络连接断开时，Sidecar **欺骗**上层 Agent：“连接还活着，别挂断”。同时，Sidecar 在后台疯狂尝试重连远端。

*   **捕获阶段**：
    *   通过 `TUN` 接口或本地 Socks5 代理接管 Agent 所有流量。
    *   当收到底层的 `RST` 或异常 `FIN` 包时，Sidecar **拦截**该信号，不传递给 Agent。
*   **解决阶段 (静默重连)**：
    *   Agent 继续向 Sidecar 发送数据，Sidecar 将这些数据暂时缓存在内存环形缓冲区 (Ring Buffer) 中。
    *   Sidecar 启动“快速重连机制”，建立新的到底层服务器的物理连接。
    *   连接恢复后，Sidecar 将缓冲区的数据**重放 (Replay)** 到新连接上。
    *   **结果**：Agent 感觉只是稍微卡了一下（几百毫秒），但连接从未断开。

### 3.2. 针对“DPI 识别”：Mimicry-TLS (拟态传输层)

**原理**：
放弃使用标准的 TLS 库，改用 **uTLS (Client Hello 伪装库)**。

*   **捕获阶段**：
    *   识别目标服务器的特征（如 Google/OpenAI）。
*   **解决阶段**：
    *   **指纹模拟**：Sidecar 在发起握手时，字节级精确模拟 Chrome 120、Firefox 或 iOS Safari 的 `ClientHello` 数据包（包括 Cipher Suites 顺序、Extensions扩展字段排列、JA3 指纹）。
    *   **Padding 混淆**：对握手包长度进行随机填充，防止通过包大小分析识别出这是“代理流量”。
    *   **结果**：网关认为这是一个标准的浏览器正在访问网页，从而放行流量。

### 3.3. 针对“Payload 过大”：Elastic-Pipe (弹性管道)

**原理**：
接管传输层的拥塞控制，针对上传大文本（Prompt）场景优化。

*   **捕获阶段**：
    *   监控 `RTT` (往返时延) 的变化率，而不是单纯看丢包。
*   **解决阶段**：
    *   **BBR 拥塞控制**：在用户态栈中实现 BBR 算法，在丢包率高的环境下依然保持高吞吐。
    *   **动态分片**：如果发现大包频繁失败，Sidecar 自动将 Agent 的大 Payload 切割成更小的 MTU 单元进行传输，到了远端再组装。
    *   **HTTP/3 (QUIC) 升级**：如果 TCP 实在容易断，Sidecar 可以透明地将底层传输升级为 QUIC 协议（基于 UDP），利用 QUIC 的连接迁移特性彻底解决 IP 切换和断网问题。

---

## 4. 实施路线图 (Roadmap)

如果决定实施此方案，建议分三步走：

1.  **Phase 1: 集成 uTLS (解决最紧迫的 DPI 问题)**
    *   不需要完整的用户态栈。
    *   直接在现有的 Clash Core (Mihomo) 配置中，启用 `tls-tracer` 或类似指纹伪装功能。
    *   修改 Ares 的配置生成逻辑，为关键节点添加 `client-fingerprint: chrome` 字段。

2.  **Phase 2: "Resilience Mode" Sidecar 原型**
    *   使用 Go 开发一个简单的 Socks5 Server sidecar。
    *   实现“断线不报错”的逻辑：收到上游断开后，Hold 住下游连接 5 秒，尝试重连。
    *   集成进 Ares，作为一个可选的后台进程启动。

3.  **Phase 3: 完整的用户态栈 (终极形态)**
    *   引入 gVisor/netstack。
    *   实现全链路的 TCP 状态接管和 QUIC 隧道回退。

## 5. 总结

您资料中提到的神奇功能是**真实可行**的，但它不是“配置一下配置表”就能实现的。它需要我们构建一个**比操作系统更智能、更坚韧的网络中间层**。

对于 Ares 来说，目前性价比最高的第一步是：**利用 Mihomo 内核的 uTLS 能力，在配置层面解决 DPI 识别问题。** 这能解决 80% 的连接中断问题。
