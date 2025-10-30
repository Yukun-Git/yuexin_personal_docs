# 添加 deleted_at 软删除字段任务

## 任务背景

当前系统中通道（channels）等实体的删除操作存在以下问题：
1. 使用 `status = INACTIVE` 表示软删除，语义不清晰
2. `status` 字段有多个业务含义（active, inactive, maintenance, suspended），不适合专门用于标记删除状态
3. 系统中多个实体表都缺少专门的软删除标记

## 解决方案

统一为 mgmt schema 下需要软删除功能的实体表添加 `deleted_at` 字段。

**字段定义**：
```sql
deleted_at TIMESTAMP DEFAULT NULL
```

**查询过滤**：
- 未删除记录：`WHERE deleted_at IS NULL`
- 已删除记录：`WHERE deleted_at IS NOT NULL`

**优势**：
1. 语义清晰，专门用于软删除标记
2. 记录删除时间，便于审计和数据恢复
3. 不影响现有的 status 业务逻辑

---

## 需要添加 deleted_at 的表

### 1. 核心业务实体表

#### 1.1 通道管理模块
| 表名 | 说明 | 优先级 |
|------|------|--------|
| `mgmt.channels` | 通道协议配置 | **P0 - 立即处理** |
| `mgmt.channel_groups` | 通道组 | P1 |
| `mgmt.vendors` | 供应商管理 | P1 |
| `mgmt.sender_configs` | Sender配置 | P2 |

#### 1.2 账号管理模块
| 表名 | 说明 | 优先级 |
|------|------|--------|
| `mgmt.accounts` | 发送账号 | P0 |
| `mgmt.enterprises` | 企业账号 | P0 |

#### 1.3 权限管理模块
| 表名 | 说明 | 优先级 |
|------|------|--------|
| `mgmt.admin_users` | 管理员用户 | P0 |
| `mgmt.roles` | 角色 | P1 |

#### 1.4 黑白名单模块
| 表名 | 说明 | 优先级 |
|------|------|--------|
| `mgmt.blacklists` | 黑名单列表 | P1 |
| `mgmt.whitelists` | 白名单列表 | P1 |

#### 1.5 系统配置模块
| 表名 | 说明 | 优先级 |
|------|------|--------|
| `mgmt.country_regions` | 国家区域配置 | P2 |
| `mgmt.custom_sensitive_word_libraries` | 自定义敏感词库 | P2 |
| `mgmt.global_sensitive_word_libraries` | 全局敏感词库 | P2 |
| `mgmt.platform_errors` | 平台错误码配置 | P2 |
| `mgmt.feishu_app_configs` | 飞书应用配置 | P2 |

---

## 不需要添加 deleted_at 的表

### 日志和历史记录表
这些表记录历史操作，不应删除：
- `mgmt.channel_operation_logs`
- `mgmt.vendor_operation_logs`
- `mgmt.connection_logs`
- `mgmt.connection_status_logs`
- `mgmt.channel_alert_logs`
- `mgmt.blacklist_intercept_logs`
- `mgmt.whitelist_operation_log`
- `mgmt.sensitive_word_import_history`
- `mgmt.account_connections` (连接状态记录)
- `mgmt.sms_test_records` (测试记录)

### 关联配置表（中间表）
这些表随主表级联删除：
- `mgmt.user_roles`
- `mgmt.role_permissions`
- `mgmt.account_blacklist_configs`
- `mgmt.channel_blacklist_configs`
- `mgmt.account_sender_configs`
- `mgmt.channel_group_relations`
- `mgmt.custom_sensitive_word_applications`
- `mgmt.whitelist_membership`
- `mgmt.exemption_rules`

### 子表和详细条目表
这些表随父表删除：
- `mgmt.channel_params`
- `mgmt.routing_rules`
- `mgmt.channel_monitors`
- `mgmt.channel_alert_configs`
- `mgmt.channel_speed_statistics`
- `mgmt.blacklist_phone_entries`
- `mgmt.whitelist_phone_entries`
- `mgmt.custom_sensitive_words`
- `mgmt.global_sensitive_words`

### 价格配置表
这些表通常只更新，不删除：
- `mgmt.channel_country_prices`
- `mgmt.channel_country_actual_prices`
- `mgmt.channel_country_adjusted_prices`
- `mgmt.channel_country_future_prices`

### 系统权限表
这些是系统基础数据，不删除：
- `mgmt.permissions`

### 认证token表
这些表有过期机制，不需要软删除：
- `mgmt.feishu_auth_users`
- `mgmt.feishu_tokens`

---

## 实施步骤

### 阶段一：P0 优先级表（立即处理）
1. ✅ **channels** - 已确认需要
2. **accounts**
3. **enterprises**
4. **admin_users**

### 阶段二：P1 优先级表
5. **channel_groups**
6. **vendors**
7. **roles**
8. **blacklists**
9. **whitelists**

### 阶段三：P2 优先级表
10. **sender_configs**
11. **country_regions**
12. **custom_sensitive_word_libraries**
13. **global_sensitive_word_libraries**
14. **platform_errors**
15. **feishu_app_configs**

---

## 每个表的修改清单

### 1. SQL 数据库结构修改

```sql
-- 示例：channels 表
ALTER TABLE mgmt.channels
ADD COLUMN deleted_at TIMESTAMP DEFAULT NULL;

-- 添加索引（提升软删除查询性能）
CREATE INDEX IF NOT EXISTS idx_channels_deleted_at ON mgmt.channels(deleted_at);

-- 添加复合索引（常用查询模式）
CREATE INDEX IF NOT EXISTS idx_channels_status_deleted ON mgmt.channels(status, deleted_at);

-- 添加列注释
COMMENT ON COLUMN mgmt.channels.deleted_at IS 'Soft delete timestamp (NULL = not deleted)';
```

### 2. Python Model 修改

```python
# 示例：Channel 模型
class Channel(db.Model, TimestampMixin):
    deleted_at = db.Column(db.DateTime, nullable=True, index=True, comment='Soft delete timestamp')

    @property
    def is_deleted(self):
        """Check if channel is soft deleted."""
        return self.deleted_at is not None
```

### 3. Service 层修改

```python
# 示例：ChannelService
def get_query(self):
    """Get base query - exclude soft deleted records by default."""
    return Channel.query.filter(Channel.deleted_at.is_(None))

def delete_channel(self, channel_id: str, current_user: Any = None):
    """Soft delete channel."""
    channel = Channel.query.filter_by(channel_id=channel_id).first()
    if not channel:
        return False, 'Channel not found'

    # Soft delete
    channel.deleted_at = datetime.utcnow()
    channel.status = ChannelStatus.INACTIVE
    channel.is_enabled = False

    db.session.commit()

    # Sync to ZooKeeper
    ChannelZooKeeperSyncService.sync_channel(channel)

    return True, 'Channel deleted successfully'
```

### 4. SQL 初始化脚本更新

需要同步更新：
- `/Users/yukun-admin/projects/pigeon/pigeon_web/sql/modules/{table_name}.sql`
- `/Users/yukun-admin/projects/pigeon/pigeon_web/sql/pigeon_web.sql`
- `/Users/yukun-admin/projects/pigeon/pigeon_web/sql/mock_data/{table_name}.sql`（如果有）

---

## 注意事项

1. **向后兼容**：
   - 添加 `deleted_at` 字段时默认值为 NULL
   - 现有数据不受影响
   - 现有查询需要添加 `WHERE deleted_at IS NULL` 过滤

2. **级联删除**：
   - 软删除父表时，子表是否同时软删除需要明确
   - 例如：删除 channel_group 时，channel_group_relations 是否需要软删除？
   - 建议：关联关系表使用数据库级联删除（ON DELETE CASCADE），不使用软删除

3. **ZooKeeper 同步**：
   - channels 表软删除时，需要同步更新 ZooKeeper 状态
   - 不从 ZooKeeper 删除节点，只更新 is_enabled=false

4. **查询性能**：
   - 所有涉及该表的查询都需要添加 `deleted_at IS NULL` 条件
   - 建议在 `deleted_at` 字段上添加索引
   - 对于常用查询模式，添加复合索引

5. **API 变更**：
   - DELETE 接口移除 `force` 参数
   - 统一只支持软删除
   - 响应消息改为 "deleted successfully" 而非 "deactivated"

---

## 数据迁移脚本模板

```sql
-- 迁移脚本模板
-- 文件：migrations/add_deleted_at_to_{table_name}.sql

BEGIN;

-- 1. 添加字段
ALTER TABLE mgmt.{table_name}
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP DEFAULT NULL;

-- 2. 添加索引
CREATE INDEX IF NOT EXISTS idx_{table_name}_deleted_at
ON mgmt.{table_name}(deleted_at);

-- 3. 添加复合索引（根据实际查询模式）
CREATE INDEX IF NOT EXISTS idx_{table_name}_{field}_deleted
ON mgmt.{table_name}({field}, deleted_at);

-- 4. 添加注释
COMMENT ON COLUMN mgmt.{table_name}.deleted_at IS 'Soft delete timestamp (NULL = not deleted)';

-- 5. 数据迁移（如果需要）
-- 示例：将 status = 'deleted' 的记录标记为软删除
-- UPDATE mgmt.{table_name}
-- SET deleted_at = updated_at
-- WHERE status = 'deleted' AND deleted_at IS NULL;

COMMIT;
```

---

## 相关文档

- 需求文档：无（技术优化任务）
- 设计文档：本文档
- 涉及模块：通道管理、账号管理、权限管理、黑白名单管理、系统配置

---

## 工作量估算

- **P0 表（4个）**：约 1-2 天
  - 数据库修改：0.5 天
  - Model 层修改：0.5 天
  - Service 层修改：0.5 天
  - 测试验证：0.5 天

- **P1 表（5个）**：约 2-3 天
- **P2 表（6个）**：约 2-3 天

**总计**：约 5-8 天

---

## 完成标准

1. ✅ 所有目标表添加 `deleted_at` 字段
2. ✅ 所有相关 Model 类更新
3. ✅ 所有 Service 层查询添加软删除过滤
4. ✅ 所有删除接口改为软删除
5. ✅ SQL 初始化脚本更新
6. ✅ Mock 数据脚本更新
7. ✅ 前端构建无错误（npm run build）
8. ✅ 所有相关测试通过

---

**创建时间**：2025-10-30
**创建人**：Claude
**状态**：待处理
**优先级**：P0（channels 表）
