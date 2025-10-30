# Channel Management 页面 ZooKeeper 同步操作总结

本文档总结了 `http://localhost:5173/business/channel-management` 页面中ZooKeeper数据同步的最新规则和实现。

**最后更新**: 2025年1月

---

## 一、ZooKeeper同步服务

### 服务类
**文件**: `app/services/sync/channel_zookeeper_sync.py`
**类名**: `ChannelZooKeeperSyncService`

### 核心方法

#### 1. `validate_channel_data(channel) -> Tuple[bool, Optional[str]]`
**功能**: 验证通道数据完整性

**必填字段**:
- `channel_id`: 通道ID（字符串，非空）
- `path`: 网关地址/路径（字符串，非空）
- `port`: 端口号（整数，> 0）
- `account`: 上游账号（字符串，非空）
- `password`: 密码（字符串，非空）
- `default_encoding`: 默认编码（整数，>= 0）
- `rate_limit`: 速率限制（整数，> 0）
- `max_connection`: 最大连接数（整数，> 0）

**返回值**:
- `(True, None)`: 验证通过
- `(False, error_message)`: 验证失败，返回错误信息

---

#### 2. `sync_channel(channel) -> Tuple[bool, Optional[str]]`
**功能**: 将通道数据同步到ZooKeeper，包含数据验证

**流程**:
1. 调用 `validate_channel_data()` 验证数据完整性
2. 如果验证通过，将数据转换为pigeon格式并同步到ZooKeeper
3. 返回操作结果和可能的错误信息

**返回值**:
- `(True, None)`: 同步成功
- `(False, error_message)`: 同步失败，返回错误信息

---

#### 3. `delete_channel(channel_id) -> bool`
**功能**: 从ZooKeeper删除通道配置

**返回值**:
- `True`: 删除成功
- `False`: 删除失败

---

## 二、新的ZooKeeper同步规则

### 规则1: 通道启用时 → 插入ZooKeeper

**触发条件**: 通道从 `is_enabled=False` 变为 `is_enabled=True`

**代码位置**: `ChannelService.update_channel()` - channel_service.py:546-552

**实现逻辑**:
```python
if not old_is_enabled and new_is_enabled:
    # Channel enabled (False -> True), insert to ZooKeeper
    success, error_msg = ChannelZooKeeperSyncService.sync_channel(channel)
    if not success:
        current_app.logger.warning(
            f"Failed to sync enabled channel {channel_id} to ZooKeeper: {error_msg}"
        )
```

**说明**:
- 在通道更新时，检测 `is_enabled` 状态从 `False` 变为 `True`
- 调用 `sync_channel()` 将通道数据插入ZooKeeper
- 数据必须通过完整性验证
- 失败时记录警告日志，但不影响数据库操作

---

### 规则2: 通道禁用时 → 从ZooKeeper删除

**触发条件**: 通道从 `is_enabled=True` 变为 `is_enabled=False`

**代码位置**: `ChannelService.update_channel()` - channel_service.py:553-555

**实现逻辑**:
```python
elif old_is_enabled and not new_is_enabled:
    # Channel disabled (True -> False), delete from ZooKeeper
    ChannelZooKeeperSyncService.delete_channel(channel_id)
```

**说明**:
- 在通道更新时，检测 `is_enabled` 状态从 `True` 变为 `False`
- 调用 `delete_channel()` 从ZooKeeper删除通道配置
- 删除失败不影响数据库操作

---

### 规则3: 通道删除时 → 无需同步

**触发操作**:
- 单个删除：表格行操作 → "删除"按钮
- 批量删除：选中多个通道 → "批量删除"按钮

**代码位置**:
- `ChannelService.delete_channel()` - channel_service.py:632-633
- `ChannelService.batch_delete_channels()` - channel_service.py:1110-1111

**实现逻辑**:
```python
# No ZooKeeper sync needed: only disabled channels can be deleted,
# and they are already removed from ZooKeeper when disabled
```

**说明**:
- 系统只允许删除已禁用的通道（`is_enabled=False`）
- 通道禁用时已经从ZooKeeper删除了配置（规则2）
- 删除操作无需额外的ZooKeeper同步

---

### 规则4: 启用状态的通道修改时 → 更新ZooKeeper

**触发操作**:
- **编辑通道**: 表格行操作 → "编辑"按钮 → 修改并保存
- **参数配置**: 表格行操作 → "参数配置"按钮 → 修改并保存

#### 4.1 编辑通道基本信息

**代码位置**: `ChannelService.update_channel()` - channel_service.py:556-562

**实现逻辑**:
```python
elif new_is_enabled:
    # Channel remains enabled, update ZooKeeper
    success, error_msg = ChannelZooKeeperSyncService.sync_channel(channel)
    if not success:
        current_app.logger.warning(
            f"Failed to update enabled channel {channel_id} in ZooKeeper: {error_msg}"
        )
```

**说明**:
- 当通道保持启用状态（`is_enabled=True`）时
- 修改通道的任何字段后，更新ZooKeeper中的配置
- 数据必须通过完整性验证
- 失败时记录警告日志，但不影响数据库操作

#### 4.2 修改通道参数

**代码位置**: `ChannelService.update_channel_parameters()` - channel_service.py:774-780

**实现逻辑**:
```python
# Sync to ZooKeeper only if channel is enabled
if channel.is_enabled:
    success, error_msg = ChannelZooKeeperSyncService.sync_channel(channel)
    if not success:
        current_app.logger.warning(
            f"Failed to update enabled channel {channel_id} parameters in ZooKeeper: {error_msg}"
        )
```

**说明**:
- 仅当通道处于启用状态时才同步
- 修改参数后立即更新ZooKeeper配置
- 失败时记录警告日志，但不影响数据库操作

---

### 规则5: 未启用状态的通道修改时 → 不同步

**触发条件**: 修改 `is_enabled=False` 的通道

**代码位置**:
- `ChannelService.update_channel()` - 没有else分支（隐式）
- `ChannelService.update_channel_parameters()` - 只在 `is_enabled=True` 时执行

**说明**:
- 未启用的通道本身就不在ZooKeeper中
- 修改未启用通道的任何信息都不会触发ZooKeeper同步
- 当通道被启用时，会按照规则1插入ZooKeeper

---

### 规则6: 其他操作 → 不同步

以下操作**不会**触发ZooKeeper同步：

#### 6.1 创建通道
- **原因**: 新创建的通道默认为未启用状态
- **代码**: 已移除的同步调用（channel_service.py:442-443）

#### 6.2 批量关闭通道
- **前端操作**: 选中多个通道 → "批量关闭"按钮
- **原因**: 批量关闭会将 `is_enabled` 设为 `False`，触发规则2
- **代码位置**: `ChannelService.batch_close_channels()` - channel_service.py:1013-1014
```python
# No ZooKeeper sync needed: batch_close sets is_enabled=False,
# which triggers ZooKeeper deletion in update_channel method
```

#### 6.3 连接/断开连接
- **原因**: 连接状态变化不影响ZooKeeper中的通道配置
- **代码**: 已移除的同步调用（channel_service.py:846-847, 914-915）

#### 6.4 查询、导出等只读操作
- **原因**: 只读操作不修改数据

---

## 三、数据完整性验证

### 验证时机
所有向ZooKeeper插入或更新数据的操作，都会先经过数据完整性验证。

### 验证内容

| 字段名 | 字段类型 | 验证规则 | 错误信息 |
|--------|---------|---------|---------|
| channel_id | 字符串 | 不能为空 | Field 'channel_id' is required and cannot be empty |
| path | 字符串 | 不能为空 | Field 'path' is required and cannot be empty |
| port | 整数 | 必须 > 0 | Field 'port' must be greater than 0 |
| account | 字符串 | 不能为空 | Field 'account' is required and cannot be empty |
| password | 字符串 | 不能为空 | Field 'password' is required and cannot be empty |
| default_encoding | 整数 | 不能为None（可以为0） | Field 'default_encoding' is required |
| rate_limit | 整数 | 必须 > 0 | Field 'rate_limit' must be greater than 0 |
| max_connection | 整数 | 必须 > 0 | Field 'max_connection' must be greater than 0 |

### 验证失败处理
- 记录错误日志
- 不同步到ZooKeeper
- **不影响数据库操作**（数据仍会保存到数据库）

---

## 四、ZooKeeper同步的数据内容

同步到ZooKeeper的通道数据字段（参考 `channel_zookeeper_sync.py:_channel_to_pigeon_json`）：

```json
{
    "channel_id": "通道ID",
    "provider_id": "供应商ID",
    "is_direct": "是否直连",
    "protocol": "协议类型（SMPP_V32/HTTP_V1）",
    "country": "国家",
    "operator": "运营商",
    "signature": "签名",
    "allow_message_types": "允许的消息类型",
    "allow_content_types": "允许的内容类型",
    "path": "路径",
    "port": "端口",
    "account": "账号（upstream_account）",
    "password": "密码",
    "default_encoding": "默认编码",
    "sender_id": "发送者ID",
    "error_codes": null,
    "sender_id_len_limit": "发送者ID长度限制",
    "content_bytes_limit": "内容字节限制",
    "rate_limit": "速率限制",
    "max_connection": "最大连接数",
    "day_send_count_limit": "日发送限制",
    "is_enabled": "是否启用",
    "is_online": "是否在线",
    "current_connection": "当前连接数（cur_connection）"
}
```

---

## 五、错误处理策略

### 同步失败处理原则
**ZooKeeper同步失败不会阻止数据库操作**

### 具体处理方式

1. **数据验证失败**
   - 记录错误日志：`Channel data validation failed for {channel_id}: {error_msg}`
   - 不执行ZooKeeper操作
   - 数据库操作正常完成

2. **ZooKeeper写入失败**
   - 记录警告日志：`Failed to sync/update enabled channel {channel_id} to/in ZooKeeper: {error_msg}`
   - 数据库操作正常完成
   - 不抛出异常，不回滚数据库事务

3. **ZooKeeper删除失败**
   - 记录错误日志：`Failed to delete channel {channel_id} from pigeon ZooKeeper: {error_msg}`
   - 数据库操作正常完成

### 日志级别

| 场景 | 日志级别 | 日志方法 |
|------|---------|---------|
| 数据验证失败 | ERROR | `current_app.logger.error()` |
| 同步成功 | INFO | `current_app.logger.info()` |
| 同步失败（非阻塞） | WARNING | `current_app.logger.warning()` |
| ZooKeeper操作失败 | ERROR | `current_app.logger.error()` |

---

## 六、总结

### 会触发ZooKeeper同步的操作（4种）

| # | 操作 | 触发条件 | ZooKeeper操作 | 前置验证 |
|---|------|---------|--------------|---------|
| 1 | 启用通道 | is_enabled: False → True | 插入数据 | ✅ 必须 |
| 2 | 禁用通道 | is_enabled: True → False | 删除数据 | ❌ 不需要 |
| 3 | 编辑启用的通道 | is_enabled保持True | 更新数据 | ✅ 必须 |
| 4 | 修改启用通道的参数 | is_enabled保持True | 更新数据 | ✅ 必须 |

### 不触发ZooKeeper同步的操作

- ❌ 创建通道（新通道默认未启用）
- ❌ 删除通道（只能删除未启用的通道）
- ❌ 批量删除通道（只能删除未启用的通道）
- ❌ 批量关闭通道（会触发规则2）
- ❌ 修改未启用的通道
- ❌ 连接/断开连接操作
- ❌ 查询、导出等只读操作

### 设计优势

1. ✅ **性能优化**: 减少不必要的ZooKeeper写入
2. ✅ **数据一致性**: ZooKeeper中只保留启用状态的通道
3. ✅ **数据完整性**: 强制验证关键字段
4. ✅ **容错性**: ZooKeeper失败不影响业务操作
5. ✅ **可维护性**: 同步逻辑清晰，集中管理

---

## 七、注意事项

### 部署建议
1. 系统升级后，建议运行一次全量同步，确保ZooKeeper中已启用通道的数据完整：
   ```python
   ChannelZooKeeperSyncService.sync_all_channels()
   ```

### 监控建议
1. 监控ZooKeeper同步失败率
2. 定期检查数据库与ZooKeeper数据一致性
3. 对数据验证失败建立告警机制

### 业务约束
1. 只有未启用的通道（`is_enabled=False`）才能被删除
2. 删除通道前必须先禁用
3. ZooKeeper中只保留启用状态的通道配置

---

**文档版本**: v2.0
**生效日期**: 2025年1月
**维护人**: yukun.xing <xingyukun@gmail.com>
