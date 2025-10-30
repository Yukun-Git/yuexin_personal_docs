# ZooKeeper同步策略优化开发计划

## 一、背景与目标

### 当前问题
当前的ZooKeeper同步策略存在以下问题：
- 在不必要的时机触发同步（如创建通道、连接/断开连接）
- 缺少数据完整性验证
- 没有根据通道启用状态智能同步
- 同步逻辑分散，难以维护

### 优化目标
建立清晰、高效的ZooKeeper同步策略：
1. 只同步启用状态的通道
2. 在关键状态变更时自动同步
3. 增加数据完整性验证
4. 简化同步逻辑，提高可维护性

## 二、新的ZooKeeper同步规则

### 规则定义

#### 1. 通道启用时 → 插入ZooKeeper
**触发条件**: 通道从`is_enabled=False`变为`is_enabled=True`

**操作**: 调用`ChannelZooKeeperSyncService.sync_channel(channel)`

**前置条件**: 数据完整性验证通过

---

#### 2. 通道禁用时 → 从ZooKeeper删除
**触发条件**: 通道从`is_enabled=True`变为`is_enabled=False`

**操作**: 调用`ChannelZooKeeperSyncService.delete_channel(channel_id)`

**说明**: 从ZooKeeper中移除该通道配置

---

#### 3. 通道删除时 → 无需同步
**触发条件**: 通道被软删除/硬删除

**说明**: 因为只有未启用的通道才能被删除，此时ZooKeeper中已无该通道数据，无需操作

---

#### 4. 通道修改时 → 条件更新ZooKeeper
**触发条件**:
- 编辑通道基本信息（`update_channel`）
- 修改通道参数（`update_channel_parameters`）

**条件判断**:
```python
if channel.is_enabled:
    # 通道处于启用状态，更新ZooKeeper
    ChannelZooKeeperSyncService.sync_channel(channel)
```

**前置条件**: 数据完整性验证通过

---

#### 5. 数据完整性验证
在向ZooKeeper插入或更新数据前，必须验证以下必填字段：

**必填字段**:
- `channel_id`: 通道ID
- `path`: 网关地址/路径
- `port`: 端口号
- `account`: 上游账号（upstream_account）
- `password`: 密码
- `default_encoding`: 默认编码
- `rate_limit`: 速率限制
- `max_connection`: 最大连接数

**验证逻辑**:
- 字符串字段不能为空（None或空字符串）
- 数值字段必须大于0（除了default_encoding可以为0）

---

#### 6. 其他操作 → 不同步
除了以上5种情况，通道管理页面的其他操作都不会触发ZooKeeper同步：
- ❌ 创建通道（新创建的通道默认未启用）
- ❌ 连接/断开连接操作
- ❌ 批量关闭通道（禁用操作会触发规则2）
- ❌ 批量删除通道（已按规则3处理）
- ❌ 查询、导出等只读操作

## 三、技术方案设计

### 3.1 ChannelZooKeeperSyncService改造

#### 新增方法：数据完整性验证

```python
@classmethod
def validate_channel_data(cls, channel: Channel) -> Tuple[bool, Optional[str]]:
    """
    Validate channel data integrity before syncing to ZooKeeper.

    Args:
        channel: Channel instance to validate

    Returns:
        Tuple of (is_valid, error_message)
        - (True, None) if valid
        - (False, error_message) if invalid
    """
    # Required fields validation
    required_fields = {
        'channel_id': channel.channel_id,
        'path': channel.path,
        'port': channel.port,
        'account': channel.upstream_account,
        'password': channel.password,
        'default_encoding': channel.default_encoding,
        'rate_limit': channel.rate_limit,
        'max_connection': channel.max_connection,
    }

    # Check for missing or empty string fields
    for field_name, field_value in required_fields.items():
        if field_name in ['channel_id', 'path', 'account', 'password']:
            if not field_value or (isinstance(field_value, str) and not field_value.strip()):
                return False, f"Field '{field_name}' is required and cannot be empty"

        # Numeric fields validation
        if field_name in ['port', 'rate_limit', 'max_connection']:
            if field_value is None or field_value <= 0:
                return False, f"Field '{field_name}' must be greater than 0"

        # default_encoding can be 0
        if field_name == 'default_encoding':
            if field_value is None:
                return False, f"Field 'default_encoding' is required"

    return True, None
```

#### 改造sync_channel方法

```python
@classmethod
def sync_channel(cls, channel: Channel) -> Tuple[bool, Optional[str]]:
    """
    Sync channel data to pigeon ZooKeeper with data validation.

    Args:
        channel: Channel instance to sync

    Returns:
        Tuple of (success, error_message)
    """
    # Step 1: Validate data integrity
    is_valid, error_msg = cls.validate_channel_data(channel)
    if not is_valid:
        current_app.logger.error(
            f"Channel data validation failed for {channel.channel_id}: {error_msg}"
        )
        return False, error_msg

    # Step 2: Sync to ZooKeeper
    try:
        channel_json = cls._channel_to_pigeon_json(channel)
        success = PigeonZooKeeperClient.create_channel_node(
            channel.channel_id,
            channel_json
        )

        if success:
            current_app.logger.info(
                f"Successfully synced channel to pigeon ZooKeeper: {channel.channel_id}"
            )
            return True, None
        else:
            error_msg = "Failed to create/update ZooKeeper node"
            return False, error_msg

    except Exception as e:
        error_msg = f"Exception during ZooKeeper sync: {str(e)}"
        current_app.logger.error(
            f"Failed to sync channel {channel.channel_id} to pigeon ZooKeeper: {error_msg}"
        )
        return False, error_msg
```

### 3.2 ChannelService改造

#### update_channel方法改造

在更新通道时，检测`is_enabled`状态变化：

```python
def update_channel(self, channel_id: str, data: Dict[str, Any], current_user: Any = None) -> Optional[Channel]:
    """Update channel with smart ZooKeeper sync."""
    channel = self.get_by_id(channel_id)
    if not channel:
        return None

    # Track old state
    old_is_enabled = channel.is_enabled

    # ... (existing update logic)

    # Smart ZooKeeper sync logic
    new_is_enabled = channel.is_enabled

    if not old_is_enabled and new_is_enabled:
        # Case 1: 从未启用 → 启用，插入ZooKeeper
        success, error_msg = ChannelZooKeeperSyncService.sync_channel(channel)
        if not success:
            current_app.logger.warning(
                f"Failed to sync enabled channel {channel_id} to ZooKeeper: {error_msg}"
            )

    elif old_is_enabled and not new_is_enabled:
        # Case 2: 从启用 → 未启用，从ZooKeeper删除
        ChannelZooKeeperSyncService.delete_channel(channel_id)

    elif new_is_enabled:
        # Case 3: 启用状态下的修改，更新ZooKeeper
        success, error_msg = ChannelZooKeeperSyncService.sync_channel(channel)
        if not success:
            current_app.logger.warning(
                f"Failed to update enabled channel {channel_id} in ZooKeeper: {error_msg}"
            )

    # If channel is not enabled, no ZooKeeper operation needed

    return channel
```

#### update_channel_parameters方法改造

```python
def update_channel_parameters(self, channel_id: str, params: Dict[str, Any], current_user: Any = None) -> Dict[str, Any]:
    """Update channel parameters with conditional ZooKeeper sync."""
    channel = self.get_by_id(channel_id)
    if not channel:
        raise ValueError("Channel not found")

    # ... (existing parameter update logic)

    # Only sync if channel is enabled
    if channel.is_enabled:
        success, error_msg = ChannelZooKeeperSyncService.sync_channel(channel)
        if not success:
            current_app.logger.warning(
                f"Failed to update enabled channel {channel_id} parameters in ZooKeeper: {error_msg}"
            )

    return new_params
```

#### 移除不必要的同步

1. **delete_channel**: 移除ZooKeeper同步（规则3）
2. **batch_close_channels**: 移除直接同步，依赖update_channel的逻辑（规则2）
3. **batch_delete_channels**: 移除ZooKeeper同步（规则3）

## 四、实施步骤

### Step 1: 改造ChannelZooKeeperSyncService
- [ ] 添加`validate_channel_data`方法
- [ ] 改造`sync_channel`方法返回值和验证逻辑
- [ ] 添加详细的日志记录

### Step 2: 改造ChannelService.update_channel
- [ ] 添加状态变化检测
- [ ] 实现启用/禁用的智能同步逻辑
- [ ] 实现启用状态下的更新同步
- [ ] 添加错误处理和日志

### Step 3: 改造ChannelService.update_channel_parameters
- [ ] 添加启用状态检测
- [ ] 只在启用状态下同步
- [ ] 添加错误处理和日志

### Step 4: 清理不必要的同步调用
- [ ] `delete_channel`: 移除第613行的同步调用
- [ ] `batch_close_channels`: 移除第988-991行的同步循环
- [ ] `batch_delete_channels`: 移除第1087-1095行的同步循环

### Step 5: 测试验证
- [ ] 测试通道启用时的ZooKeeper插入
- [ ] 测试通道禁用时的ZooKeeper删除
- [ ] 测试启用通道修改时的ZooKeeper更新
- [ ] 测试未启用通道修改时不同步
- [ ] 测试数据完整性验证
- [ ] 测试通道删除不触发同步

### Step 6: 文档更新
- [ ] 更新ZooKeeper同步规则文档
- [ ] 更新接口文档和注释
- [ ] 记录变更日志

## 五、测试计划

### 5.1 单元测试场景

#### 测试1: 数据完整性验证
```python
def test_validate_channel_data_missing_required_fields():
    """Test validation fails when required fields are missing"""
    channel = Channel(channel_id='test', path='', port=0)
    is_valid, error = ChannelZooKeeperSyncService.validate_channel_data(channel)
    assert is_valid is False
    assert 'required' in error.lower()
```

#### 测试2: 通道启用同步
```python
def test_enable_channel_syncs_to_zookeeper():
    """Test enabling channel syncs data to ZooKeeper"""
    # Create disabled channel
    # Update to enabled
    # Verify ZooKeeper sync was called
```

#### 测试3: 通道禁用删除
```python
def test_disable_channel_deletes_from_zookeeper():
    """Test disabling channel deletes from ZooKeeper"""
    # Create enabled channel
    # Update to disabled
    # Verify ZooKeeper delete was called
```

#### 测试4: 启用状态修改同步
```python
def test_update_enabled_channel_syncs():
    """Test updating enabled channel syncs to ZooKeeper"""
    # Create enabled channel
    # Update parameters
    # Verify ZooKeeper sync was called
```

#### 测试5: 未启用状态修改不同步
```python
def test_update_disabled_channel_no_sync():
    """Test updating disabled channel does not sync"""
    # Create disabled channel
    # Update parameters
    # Verify ZooKeeper sync was NOT called
```

### 5.2 集成测试场景

#### 测试6: 通道生命周期完整流程
1. 创建通道（未启用）→ 不同步
2. 启用通道 → 插入ZooKeeper
3. 修改参数 → 更新ZooKeeper
4. 禁用通道 → 删除ZooKeeper
5. 删除通道 → 不同步

#### 测试7: 批量操作
1. 批量关闭启用通道 → 每个通道都从ZooKeeper删除
2. 批量删除未启用通道 → 不同步

## 六、注意事项

### 6.1 向后兼容性
- 现有已启用的通道在系统升级后需要确保ZooKeeper中有对应数据
- 建议在部署后运行一次全量同步：`ChannelZooKeeperSyncService.sync_all_channels()`

### 6.2 错误处理
- ZooKeeper同步失败不应阻止数据库操作
- 所有同步失败都要记录详细日志
- 考虑增加重试机制或异步同步队列

### 6.3 性能考虑
- 批量操作时避免频繁的ZooKeeper写入
- 考虑批量同步接口优化

### 6.4 监控和告警
- 监控ZooKeeper同步失败率
- 定期检查数据库与ZooKeeper数据一致性
- 对同步失败建立告警机制

## 七、预期影响

### 正面影响
1. ✅ 减少不必要的ZooKeeper写入，提升性能
2. ✅ 同步逻辑更清晰，易于维护
3. ✅ 数据完整性得到保障
4. ✅ ZooKeeper中只保留活跃通道配置，减少存储

### 需要注意的变更
1. ⚠️ 未启用通道的修改不再同步到ZooKeeper
2. ⚠️ 通道删除不再主动删除ZooKeeper节点（但删除前必须先禁用，禁用时已删除）
3. ⚠️ 需要确保现有系统中启用通道的ZooKeeper数据完整

## 八、验收标准

- [ ] 所有单元测试通过
- [ ] 所有集成测试通过
- [ ] 代码review通过
- [ ] 文档更新完成
- [ ] 在测试环境验证通过
- [ ] 性能指标满足要求（ZooKeeper写入减少）
- [ ] 日志记录完整准确
