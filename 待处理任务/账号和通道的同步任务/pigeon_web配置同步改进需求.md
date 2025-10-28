# pigeon_web配置同步改进需求

## 1. 背景和目标

### 1.1 系统架构

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  pigeon_web │         │    Redis    │         │   pigeon    │
│  (配置管理)  │────────▶│   (Account) │────────▶│  (短信服务)  │
└─────────────┘         └─────────────┘         └─────────────┘
                        ┌─────────────┐
                        │  ZooKeeper  │
                        │  (Channel)  │
                        └─────────────┘
```

**关键点**：
- pigeon**只从Redis和ZooKeeper读取配置**，不访问数据库
- pigeon_web负责配置管理界面和配置同步
- 配置数据格式必须严格符合pigeon的期望（参考文档：`account_in_redis_channel_in_zookeeper.md`）

### 1.2 目标

确保pigeon_web的配置数据能够完整、准确地同步到Redis和ZooKeeper，让pigeon能够正常工作。

---

## 2. Account配置问题（Redis同步）

### 2.1 严重Bug（必须立即修复）

**问题位置**：`pigeon_web/app/services/sync/account_redis_sync.py`

| 问题 | 文档期望 | 当前实现 | 影响 |
|-----|---------|---------|------|
| **enabled字段错误** | 使用account的实际启用状态 | 硬编码为`True` | pigeon无法判断账户是否真正启用 |
| **unique_id字段错误** | 使用account的UUID | 硬编码为空字符串 | pigeon无法追踪账户唯一标识 |
| **sender_id为空** | 应该有发送者ID | 硬编码为空字符串 | pigeon可能无法正确使用sender_id |

**业务影响**：
- 禁用的账户仍然会被pigeon当作启用状态处理
- 无法通过unique_id追踪账户
- sender_id功能可能失效

### 2.2 缺失字段（暂不实现）

pigeon文档要求以下字段，但根据你的标注（NO），暂时保持为空值即可：

| 字段 | 用途 | 当前同步值 |
|-----|------|-----------|
| `pool_weights` | 通道池权重分配 | `{}` 空对象 |
| `number_frequency_limit_info` | 单个号码频率限制 | `{"frequency_limit": 0, "frequency_period": ""}` |
| `account_frequency_limit_info` | 账户总体频率限制 | `{"frequency_limit": 0, "frequency_period": ""}` |
| `allowed_countries` | 允许发送的国家列表 | `[]` 空数组 |
| `allow_content_types` | 允许的内容类型 | `[]` 空数组 |

**说明**：这些字段暂时不需要实现，保持空值即可。后续如有业务需求再添加。

### 2.3 sender_id处理方案（已决策）

**现状**：
- pigeon期望在Redis的`sender_id`字段中读取发送者ID
- pigeon_web已将sender_id从Account表迁移到独立的`AccountSenderConfig`表
- 一个account可以有多个sender配置（全局sender + 各国家特定sender）

**决策方案**：使用全局sender

**实现方式**：
- 从`AccountSenderConfig`表中查找`is_global=True`的配置
- 将其`sender_value`同步到Redis的`sender_id`字段
- 如果没有全局sender，则同步空字符串

**说明**：
- 国家特定的sender配置暂时不同步到Redis
- pigeon暂时只使用全局sender
- 后续如需支持多国家sender，需要pigeon和pigeon_web共同调整架构

---

## 3. Channel配置问题（ZooKeeper同步）

### 3.1 核心问题：完全未实现ZooKeeper同步

**现状**：
- pigeon_web只将Channel配置保存到数据库
- **没有任何代码**将Channel配置同步到ZooKeeper
- pigeon从ZooKeeper读取配置，因此pigeon_web创建的Channel对pigeon完全不可见

**需要做什么**：
- 创建Channel到ZooKeeper的同步服务（类似Account的Redis同步）
- 在Channel创建/更新/删除时调用同步
- 配置ZooKeeper连接参数

### 3.2 字段名映射问题

pigeon期望的字段名与pigeon_web数据库字段名不一致：

| pigeon期望 | pigeon_web字段 | 说明 |
|-----------|---------------|------|
| `account` | `upstream_account` | 上游账号名称 |
| `current_connection` | `cur_connection` | 当前连接数 |

**需要做什么**：同步到ZooKeeper时进行字段名转换

### 3.3 缺失字段（暂不实现）

| 字段 | 说明 | 处理方案 |
|-----|------|---------|
| `error_codes` | 错误码黑名单 | 暂时填null或空值即可 |

### 3.4 前端表单问题

**当前前端有两个表单**：
1. **ChannelFormModal**（通道修改）：基本信息、计费配置、状态配置
   - `channel_id`, `channel_name`, `sender_id`, `provider_name`, `notes`
   - `sms_billing_count`, `long_sms_billing_count`
   - `gateway_signature`, `remove_signature`, `uplink_config`
   - `status`, `payment_type`, `billing_method`

2. **ParamConfigModal**（参数修改）：连接参数、协议参数
   - `protocol`（发送协议）
   - `gateway_address`（网关地址）→ 对应`path`
   - `gateway_port`（网关端口）→ 对应`port`
   - `account`（账户）→ 对应`upstream_account`
   - `password`（密码）
   - `connection_count`（连接数）→ 对应`max_connection`
   - `total_speed`（总速度）→ 对应`rate_limit`
   - `gsm7_encoding`, `source_addr_ton`, `source_addr_npi`, `dest_addr_ton`, `dest_addr_npi`

**仍然缺失的字段**（根据你的标注）：

| 字段 | 用途 | 是否需要前端 | 说明 |
|-----|------|------------|------|
| `country` | 国家代码 | ❌ NO | 你标注为NO |
| `operator` | 运营商 | ❌ NO | 你标注为NO |
| `signature` | 消息签名 | ⚠️ TBD | 你标注为TBD，需要决策 |
| `allow_message_types` | 允许的消息类型 | ❌ NO | 你标注为NO |
| `allow_content_types` | 允许的内容类型 | ❌ NO | 你标注为NO |
| `default_encoding` | 默认编码 | ⚠️ TBD | 你标注为TBD，需要决策 |
| `sender_id_len_limit` | Sender ID长度限制 | ❌ NO | 你标注为NO |
| `content_bytes_limit` | 内容字节限制 | ❌ NO | 已经有了，不在前端 |
| `day_send_count_limit` | 每日发送限制 | ❌ NO | 你标注为NO |
| `is_enabled` | 启用状态 | ✅ YES | 你标注为YES，需要添加 |
| `is_online` | 在线状态 | ❌ NO | 你标注为NO，运行时状态 |
| `provider_id` | 供应商ID | ❌ NO | 你标注为NO |
| `is_direct` | 是否直连 | ❌ NO | 你标注为NO |
| `error_codes` | 错误码黑名单 | ❌ NO | 你标注为NO |
| `current_connection` | 当前连接数 | ❌ NO | 你标注为NO，运行时状态 |

**需要添加的前端字段**（根据你的标注为YES的）：
- `is_enabled`：通道启用/禁用开关（你标注YES）

**业务影响**：
- 大部分字段你已经标注为NO，说明不需要前端配置
- 只有`is_enabled`字段需要添加到前端
- `signature`和`default_encoding`标注为TBD，需要你决策是否需要

---

## 4. 改进需求汇总

### 4.1 Account配置改进

| 编号 | 需求 | 优先级 | 工作量估算 |
|-----|------|--------|-----------|
| A1 | 修复`enabled`字段硬编码bug（改为使用account.enabled） | P0-紧急 | 0.5小时 |
| A2 | 修复`unique_id`字段硬编码bug（改为使用account的UUID） | P0-紧急 | 0.5小时 |
| A3 | 实现`sender_id`同步（从AccountSenderConfig读取全局sender） | P0-紧急 | 2小时 |

**说明**：
- `pool_weights`, `number_frequency_limit_info`, `account_frequency_limit_info`, `allowed_countries`, `allow_content_types` 这些字段你已标注为NO，暂时保持为空值即可，不需要实现

### 4.2 Channel配置改进

| 编号 | 需求 | 优先级 | 工作量估算 |
|-----|------|--------|-----------|
| C1 | 实现Channel到ZooKeeper的同步服务（包含字段名映射和error_codes处理） | P0-紧急 | 2-3天 |
| C2 | 前端添加`is_enabled`字段 | P1-高 | 2小时 |
| C3 | 决策`signature`和`default_encoding`是否需要前端支持 | TBD | 需讨论 |

**说明**：
- 字段名映射（`upstream_account`→`account`, `cur_connection`→`current_connection`）在C1中一并处理
- `error_codes`字段同步时填null或空值即可，暂不需要额外处理

---

## 5. 关键决策点

### 决策1：Channel的signature和default_encoding是否需要前端支持

**问题描述**：
- 你在文档中将`signature`和`default_encoding`标注为TBD
- 这两个字段在数据库模型中存在
- 但前端表单中没有

**需要决策**：
1. `signature`（消息签名）是否需要前端配置？还是由系统自动处理？
2. `default_encoding`（默认编码）是否需要前端配置？还是使用固定默认值？

**建议**：根据业务场景决定
- 如果签名需要灵活配置，建议添加到ChannelFormModal
- 如果编码需要灵活配置，建议添加到ParamConfigModal

**优先级**：P2

### 决策2：是否需要Account前端表单支持新字段

**问题描述**：
- 新增的高级字段（pool_weights, 频率限制等）比较复杂
- 前端表单实现成本较高
- 这些功能使用频率可能不高

**方案A**：暂不实现前端表单，通过API或数据库配置
- 优点：快速上线核心功能
- 缺点：用户体验较差

**方案B**：完整实现前端表单
- 优点：用户体验好
- 缺点：开发周期长

**建议**：方案A，后续根据业务需求再实现前端

**优先级**：P3

---

## 6. 分阶段实施建议

### 第一阶段：紧急Bug修复（P0）

**目标**：让基本功能可用

**内容**：
- 修复Account Redis同步的3个bug（enabled, unique_id, sender_id）
- 实现Channel到ZooKeeper的同步服务

**预期工作量**：3-4天

**验收标准**：
- pigeon能够从Redis正确读取Account配置
- pigeon能够从ZooKeeper正确读取Channel配置
- 基本的短信发送功能可用

### 第二阶段：完善Channel前端表单（P1）

**目标**：补充缺失的`is_enabled`字段

**内容**：
- 在ChannelFormModal或ParamConfigModal中添加`is_enabled`开关
- 决策`signature`和`default_encoding`字段是否需要前端支持

**预期工作量**：0.5天

**验收标准**：
- 前端能够配置`is_enabled`字段
- 配置能够正确保存并同步到ZooKeeper

**说明**：
- Account的高级字段（pool_weights、频率限制等）你已标注为NO，暂时不实现
- 后续如有业务需求再添加

---

## 7. 风险和依赖

### 7.1 主要风险

| 风险 | 影响 | 应对措施 |
|-----|------|---------|
| sender_id架构冲突 | 可能影响发送功能 | 优先与pigeon团队对齐方案 |
| ZooKeeper连接问题 | Channel配置无法同步 | 提前测试ZooKeeper连接和权限 |
| 字段映射错误 | pigeon解析配置失败 | 严格按照文档实现，联调测试 |
| 前端表单过于复杂 | 用户体验差 | 使用分步表单和折叠面板 |

### 7.2 外部依赖

- **pigeon团队**：需要确认sender_id处理方案
- **运维团队**：需要配置ZooKeeper连接参数和权限
- **测试团队**：需要进行端到端测试

---

## 8. 成功标准

### 8.1 功能完整性

- [ ] Account配置能够完整同步到Redis，包含所有pigeon期望的字段
- [ ] Channel配置能够完整同步到ZooKeeper，包含所有pigeon期望的字段
- [ ] 字段名映射正确，pigeon能够正常解析

### 8.2 可用性

- [ ] 前端表单能够配置所有核心字段
- [ ] 配置更新能够实时同步，无需重启
- [ ] 错误情况有明确的提示和日志

### 8.3 可靠性

- [ ] 同步失败有重试机制
- [ ] 有监控和告警
- [ ] 有完整的测试覆盖

---

## 附录：字段对比表

### A.1 Account字段对比

| 字段 | 文档要求 | pigeon_web实现 | Redis同步状态 | 问题 |
|-----|---------|---------------|--------------|------|
| account_id | ✅ | ✅ | ✅ | 无 |
| password | ✅ | ✅ | ✅ | 无 |
| sender_id | ✅ | ⚠️ 迁移到独立表 | ❌ 空字符串 | 需决策 |
| valid_ips | ✅ | ✅ | ✅ | 无 |
| is_banned | ✅ | ✅ | ✅ | 无 |
| max_connection_count | ✅ | ✅ | ✅ | 无 |
| max_deliver_resend_count | ✅ | ✅ | ✅ | 无 |
| protocol_type | ✅ | ✅ | ✅ | 无 |
| signatures | ✅ | ✅ | ✅ | 无 |
| whitelisted | ✅ | ✅ | ✅ | 无 |
| censor_words | ✅ | ✅ | ✅ | 无 |
| templates | ✅ | ✅ | ✅ | 无 |
YES(放个 12345即可）| unique_id | ✅ | ✅ | ❌ 硬编码空值 | **Bug** |     
YES | enabled | ✅ | ✅ | ❌ 硬编码true | **Bug** |  
| created_at | ✅ | ✅ | ✅ | 无 |
| updated_at | ✅ | ✅ | ✅ | 无 |
NO | pool_weights | ✅ | ❌ | ❌ 空对象 | 缺失 |
NO | number_frequency_limit_info | ✅ | ❌ | ❌ 空对象 | 缺失 |
NO | account_frequency_limit_info | ✅ | ❌ | ❌ 空对象 | 缺失 |
NO | allowed_countries | ✅ | ❌ | ❌ 空数组 | 缺失 |
NO | allow_content_types | ✅ | ❌ | ❌ 空数组 | 缺失 |

### A.2 Channel字段对比

| 字段 | 文档要求 | pigeon_web字段 | 前端表单 | 问题 |
|-----|---------|---------------|---------|------|
| channel_id | ✅ | channel_id | ✅ | 无 |
NO | provider_id | ✅ | provider_id | ❌ | 前端缺失 |    
NO | is_direct | ✅ | is_direct | ❌ | 前端缺失 |       
YES | protocol | ✅ | protocol | ❌ | 前端缺失 |     
NO | country | ✅ | country | ❌ | 前端缺失 |
NO | operator | ✅ | operator | ❌ | 前端缺失 |
TBD| signature | ✅ | signature | ❌ | 前端缺失 |
NO | allow_message_types | ✅ | allow_message_types | ❌ | 前端缺失 |
NO | allow_content_types | ✅ | allow_content_types | ❌ | 前端缺失 |
YES | path | ✅ | path | ❌ | 前端缺失 |
YES | port | ✅ | port | ❌ | 前端缺失 |
YES | account | ✅ | upstream_account | ❌ | 字段名映射 + 前端缺失 |
YES | password | ✅ | password | ❌ | 前端缺失 |
TBD | default_encoding | ✅ | default_encoding | ❌ | 前端缺失 |
| sender_id | ✅ | sender_id | ✅ | 无 |
NO | error_codes | ✅ | ❌ 可用channel_config | ❌ | 需决策存储方式 |
NO | sender_id_len_limit | ✅ | sender_id_len_limit | ❌ | 前端缺失 |
| content_bytes_limit | ✅ | content_bytes_limit | ❌ | 前端缺失 |
YES | rate_limit | ✅ | rate_limit | ❌ | 前端缺失 |
YES(default 1) | max_connection | ✅ | max_connection | ❌ | 前端缺失 |
NO | day_send_count_limit | ✅ | day_send_count_limit | ❌ | 前端缺失 |
YES| is_enabled | ✅ | is_enabled | ❌ | 前端缺失 |
NO| is_online | ✅ | is_online | ❌ | 前端缺失 |
NO| current_connection | ✅ | cur_connection | ❌ | 字段名映射 + 前端缺失 |

---

**文档版本**：v1.0
**创建日期**：2025年1月
**最后更新**：2025年1月
