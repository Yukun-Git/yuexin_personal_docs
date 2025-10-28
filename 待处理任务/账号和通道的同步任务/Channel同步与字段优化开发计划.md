# Channel同步与字段优化开发计划

## 一、概述

本次开发包含三个主要任务：
1. **C1**: 实现Channel到ZooKeeper的同步服务（包含字段名映射和error_codes处理）
2. **C2**: 前端添加`is_enabled`字段
3. **去除冗余**: 删除Channel模型中的`enabled`字段，统一使用`is_enabled`

## 二、任务详细分解

### 任务1: 去除enabled字段冗余（优先执行）

**原因**: 先清理冗余，避免后续开发中的混淆

#### 1.1 数据库层面

**文件**: `pigeon_web/sql/modules/channels.sql`

**修改内容**:
- 删除 `enabled BOOLEAN DEFAULT TRUE,` 列定义
- 保留 `is_enabled BOOLEAN DEFAULT TRUE,`
- 保留索引 `idx_chan_is_enabled`

**SQL注释**:
```sql
-- REMOVED: enabled field (redundant with is_enabled)
-- KEEPING: is_enabled as the single source of truth for enable/disable state
```

#### 1.2 数据库初始化脚本

**文件**: `pigeon/deployment/sql/init-db.sql`

**检查内容**:
- 查看是否有Channel表定义
- 如果有，同步删除`enabled`字段

#### 1.3 Mock数据脚本

**文件**: `pigeon_web/sql/mock_data/channels.sql`

**修改内容**:
- INSERT语句中移除`enabled`字段
- 只保留`is_enabled`字段

#### 1.4 pigeon_web.sql主脚本

**文件**: `pigeon_web/sql/pigeon_web.sql`

**检查内容**:
- 确保引用的模块脚本已更新

#### 1.5 Channel模型

**文件**: `pigeon_web/app/models/customers/channel.py`

**修改内容**:
```python
# 第127行：删除
# enabled = db.Column(db.Boolean, default=True)

# 保留
is_enabled = db.Column(db.Boolean, default=True)

# 第182-185行：修改is_active属性
@property
def is_active(self):
    """Check if channel is active (enabled and status is active)."""
    return (self.is_enabled and
            self.status == ChannelStatus.ACTIVE)

# 第308行：to_dict方法中删除
# 'enabled': self.enabled,
# 保留
'is_enabled': self.is_enabled,
```

#### 1.6 Channel Service

**文件**: `pigeon_web/app/services/channels/channel_service.py`

**修改内容**:
- 第248行: `Channel.enabled` → `Channel.is_enabled`
- 第629行: 删除 `channel.enabled = False`，保留 `channel.is_enabled = False`
- 第860行: 删除 `channel.enabled = True`，保留 `channel.is_enabled = True`
- 第922行: 删除 `channel.enabled = False`，保留 `channel.is_enabled = False`
- 第991行: 删除 `channel.enabled = False`，保留 `channel.is_enabled = False`
- 第2204行: `Channel.enabled == False` → `Channel.is_enabled == False`

**搜索替换规则**:
```python
# 查找所有出现的模式
channel.enabled = False  → 删除此行（下一行已有is_enabled）
channel.enabled = True   → 删除此行（下一行已有is_enabled）
Channel.enabled          → Channel.is_enabled
```

#### 1.7 前端API类型定义

**文件**: `pigeon_web/frontend/src/api/channelApi.ts`

**修改内容**:
```typescript
// 第137-138行：删除enabled，保留is_enabled
// enabled: boolean;  // 删除这行
is_enabled: boolean;

// 第186行：同样处理
// enabled: boolean;  // 删除这行

// 第266行：查询参数
// enabled?: boolean;  // 删除这行

// 第671行：过滤参数
// enabled?: boolean;  // 删除这行

// 第737、919行：查询字符串构建
// 删除 enabled 相关的代码
```

---

### 任务2: 实现Channel到ZooKeeper的同步服务（C1）

#### 2.1 创建ZooKeeper客户端工具类

**新建文件**: `pigeon_web/app/utils/pigeon_zookeeper_client.py`

**实现内容**:
```python
# Copyright(c) 2025
# All rights reserved.
#
# Author: yukun.xing <xingyukun@gmail.com>
# Date:   2025/01/24

"""Pigeon ZooKeeper client utility."""

import os
import json
from typing import Optional
from kazoo.client import KazooClient
from kazoo.exceptions import NodeExistsError, NoNodeError
from flask import current_app


class PigeonZooKeeperClient:
    """ZooKeeper client for pigeon backend services."""

    # ZooKeeper configuration from environment variables
    ZOOKEEPER_HOSTS = os.environ.get('PIGEON_ZOOKEEPER_HOSTS', 'localhost:2181')
    ZOOKEEPER_TIMEOUT = int(os.environ.get('PIGEON_ZOOKEEPER_TIMEOUT', '10'))

    # ZooKeeper path prefix for channels
    CHANNEL_PATH_PREFIX = '/pigeon/channel_worker/jobs'

    _zk_client: Optional[KazooClient] = None

    @classmethod
    def get_client(cls) -> KazooClient:
        """Get or create ZooKeeper client."""

    @classmethod
    def ensure_connected(cls):
        """Ensure ZooKeeper client is connected."""

    @classmethod
    def test_connection(cls) -> bool:
        """Test ZooKeeper connection."""

    @classmethod
    def close(cls):
        """Close ZooKeeper connection."""
```

**环境变量**:
- `PIGEON_ZOOKEEPER_HOSTS`: ZooKeeper服务器地址（默认: localhost:2181）
- `PIGEON_ZOOKEEPER_TIMEOUT`: 连接超时（默认: 10秒）

#### 2.2 创建Channel ZooKeeper同步服务

**新建文件**: `pigeon_web/app/services/sync/channel_zookeeper_sync.py`

**实现内容**:
```python
# Copyright(c) 2025
# All rights reserved.
#
# Author: yukun.xing <xingyukun@gmail.com>
# Date:   2025/01/24

"""Channel ZooKeeper synchronization service."""

import json
from typing import Optional
from flask import current_app

from app.models.customers.channel import Channel
from app.utils.pigeon_zookeeper_client import PigeonZooKeeperClient


class ChannelZooKeeperSyncService:
    """Service for synchronizing channel data to pigeon's ZooKeeper."""

    @classmethod
    def sync_channel(cls, channel: Channel) -> bool:
        """Sync channel data to pigeon ZooKeeper."""

    @classmethod
    def delete_channel(cls, channel_id: str) -> bool:
        """Delete channel from pigeon ZooKeeper."""

    @classmethod
    def _channel_to_pigeon_json(cls, channel: Channel) -> str:
        """Convert Channel model to pigeon-compatible JSON format."""

    @classmethod
    def _map_protocol(cls, protocol: str) -> str:
        """Map protocol field to pigeon format."""

    @classmethod
    def _map_encoding(cls, encoding: int) -> int:
        """Map default_encoding to pigeon format."""
```

**关键字段映射规则**:

| pigeon_web字段 | ZooKeeper字段 | 映射规则 |
|---------------|--------------|---------|
| `channel_id` | `channel_id` | 直接使用 |
| `upstream_account` | `account` | 字段名映射 |
| `cur_connection` | `current_connection` | 字段名映射 |
| `protocol` | `protocol` | 需要映射到SMPP_V32等格式 |
| `default_encoding` | `default_encoding` | 使用models/types.go中的映射 |
| `is_enabled` | `is_enabled` | 直接使用 |
| `max_connection` | `max_connection` | 如果为0则默认为1 |
| `error_codes` | `error_codes` | 填null |

**encoding映射**（根据pigeon/src/models/types.go）:
```python
# 0x00 (0) → GSM-7bit
# 0x01 (1) → ASCII
# 0x03 (3) → ISO-8859-1 (Latin1)
# 0x08 (8) → UCS2
```

**protocol映射**:
- 数据库存储改为直接使用 "SMPP_V32", "HTTP_V1"
- 同步时直接使用

**ZooKeeper节点路径**:
```
/pigeon/channel_worker/jobs/{channel_id}
```

**ZooKeeper数据格式**（参考文档）:
```json
{
  "channel_id": "channel_001",
  "provider_id": "",
  "is_direct": false,
  "protocol": "SMPP_V32",
  "country": "",
  "operator": "",
  "signature": "",
  "allow_message_types": [],
  "allow_content_types": [],
  "path": "172.27.10.192",
  "port": 2776,
  "account": "account_out",
  "password": "password123",
  "default_encoding": 1,
  "sender_id": "CMCC_SENDER",
  "error_codes": null,
  "sender_id_len_limit": 0,
  "content_bytes_limit": 160,
  "rate_limit": 10000,
  "max_connection": 2,
  "day_send_count_limit": 0,
  "is_enabled": true,
  "is_online": false,
  "current_connection": 0
}
```

#### 2.3 修改数据库初始化脚本 - protocol字段

**文件**: `pigeon_web/sql/modules/channels.sql`

**修改内容**:
```sql
-- 修改protocol列的注释和默认值示例
protocol VARCHAR(50) COMMENT 'Protocol type (e.g., SMPP_V32, HTTP_V1)',

-- 添加CHECK约束（可选）
ALTER TABLE mgmt.channels
ADD CONSTRAINT check_protocol_format
CHECK (protocol IN ('SMPP_V32', 'HTTP_V1') OR protocol IS NULL);
```

**文件**: `pigeon_web/sql/mock_data/channels.sql`

**修改内容**:
```sql
-- 将所有 protocol 值从 'smpp' 改为 'SMPP_V32'
-- 将所有 protocol 值从 'http' 改为 'HTTP_V1'
```

**文件**: `pigeon/deployment/sql/init-db.sql`

**检查内容**:
- 如果有Channel表定义，同步修改protocol字段

#### 2.4 修改Channel Service - 调用同步

**文件**: `pigeon_web/app/services/channels/channel_service.py`

**需要修改的方法**:

1. **create_channel()** - 创建通道后同步
```python
# 在commit之后
from app.services.sync.channel_zookeeper_sync import ChannelZooKeeperSyncService

db.session.commit()
# Sync to ZooKeeper
ChannelZooKeeperSyncService.sync_channel(channel)
```

2. **update_channel()** - 更新通道后同步
```python
# 在commit之后
db.session.commit()
# Sync to ZooKeeper
ChannelZooKeeperSyncService.sync_channel(channel)
```

3. **delete_channel()** - 删除通道后同步
```python
# 在commit之后（软删除或硬删除）
db.session.commit()
# Delete from ZooKeeper
ChannelZooKeeperSyncService.delete_channel(channel_id)
```

4. **其他可能需要同步的操作**:
- `activate_channel()` - 激活通道
- `deactivate_channel()` - 停用通道
- `suspend_channel()` - 暂停通道
- `batch_update_channels()` - 批量更新

**查找所有需要同步的位置**:
```bash
# 查找所有对Channel进行commit的位置
grep -n "db.session.commit()" pigeon_web/app/services/channels/channel_service.py
```

#### 2.5 更新__init__.py导出

**文件**: `pigeon_web/app/services/sync/__init__.py`

**修改内容**:
```python
from .account_redis_sync import AccountRedisSyncService
from .channel_zookeeper_sync import ChannelZooKeeperSyncService

__all__ = [
    'AccountRedisSyncService',
    'ChannelZooKeeperSyncService',
]
```

---

### 任务3: 前端添加is_enabled字段（C2）

#### 3.1 理解现有状态管理

**当前情况**:
- `status` 字段: active/inactive/maintenance/suspended（运营状态）
- `is_enabled` 字段: true/false（启用开关）

**关系**:
- `active` 对应 `is_enabled=true`
- `inactive` 对应 `is_enabled=false`
- 但是 `status` 可以是 maintenance 或 suspended，此时 `is_enabled` 可能仍然是 true

**决策**:
根据用户确认，简化处理：
- **active = is_enabled=true**
- **inactive = is_enabled=false**
- 前端只显示 active/inactive，不使用 maintenance/suspended

#### 3.2 修改前端ChannelFormModal

**文件**: `pigeon_web/frontend/src/pages/ChannelManagement/components/ChannelFormModal.tsx`

**修改位置1**: TypeScript接口定义（约第51行）
```typescript
// 删除或注释
// status: ChannelStatus;

// 替换为
is_enabled: boolean;
```

**修改位置2**: useEffect中的表单初始化（约第134-148行）
```typescript
// 编辑模式
form.setFieldsValue({
  channel_id: channelData.channel_id,
  channel_name: channelData.channel_name,
  sender_id: channelData.sender_id,
  sms_billing_count: channelData.sms_billing_count || 160,
  long_sms_billing_count: channelData.long_sms_billing_count || 153,
  gateway_signature: channelData.gateway_signature || false,
  remove_signature: channelData.remove_signature || false,
  uplink_config: channelData.uplink_config || 'deliver_match',
  is_enabled: channelData.is_enabled !== false, // 修改这里
  payment_type: channelData.payment_type || 'postpaid',
  provider_name: channelData.provider_name,
  billing_method: channelData.billing_method || 'submit_billing',
  notes: channelData.notes,
});

// 创建模式默认值（约第152-162行）
form.setFieldsValue({
  sms_billing_count: 160,
  long_sms_billing_count: 153,
  gateway_signature: false,
  remove_signature: false,
  uplink_config: 'deliver_match',
  is_enabled: true, // 修改这里，默认启用
  payment_type: 'postpaid',
  billing_method: 'submit_billing',
});
```

**修改位置3**: 表单UI（约第340-346行）
```typescript
// 将原来的 status 字段改为 is_enabled
<Col span={12}>
  <Form.Item name="is_enabled" label="通道启用状态">
    <Radio.Group>
      <Radio value={true}>启用</Radio>
      <Radio value={false}>禁用</Radio>
    </Radio.Group>
  </Form.Item>
</Col>
```

#### 3.3 修改API类型定义

**文件**: `pigeon_web/frontend/src/api/channelApi.ts`

**修改内容**:
- 确保 `is_enabled` 字段存在于所有相关接口
- 删除或注释 `enabled` 字段的引用

#### 3.4 修改后端API响应

**文件**: `pigeon_web/app/api/v1/channels/*.py`

**检查内容**:
- 确保API返回的Channel数据包含 `is_enabled` 字段
- 确保API接受的创建/更新数据可以处理 `is_enabled` 字段

---

## 三、实施顺序

### 阶段1: 去除冗余（基础清理）
1. 修改数据库脚本（channels.sql, mock_data）
2. 修改Channel模型（channel.py）
3. 修改Channel Service（channel_service.py）
4. 修改前端API类型（channelApi.ts）

### 阶段2: 后端同步服务（C1）
1. 创建ZooKeeper客户端（pigeon_zookeeper_client.py）
2. 创建同步服务（channel_zookeeper_sync.py）
3. 修改数据库脚本 - protocol字段格式
4. 修改Channel Service - 调用同步
5. 更新__init__.py导出

### 阶段3: 前端字段添加（C2）
1. 修改ChannelFormModal组件
2. 测试前端表单功能

### 阶段4: 测试与验证
1. 单元测试
2. 集成测试
3. 手工测试

---

## 四、测试计划

### 4.1 单元测试

**测试文件**: `pigeon_web/tests/unit/test_channel_zookeeper_sync.py`

**测试内容**:
- `test_sync_channel()` - 测试同步Channel到ZooKeeper
- `test_delete_channel()` - 测试从ZooKeeper删除Channel
- `test_field_mapping()` - 测试字段名映射
- `test_protocol_mapping()` - 测试protocol映射
- `test_encoding_mapping()` - 测试encoding映射
- `test_max_connection_default()` - 测试max_connection默认值

### 4.2 集成测试

**测试文件**: `pigeon_web/tests/integration/test_channel_sync_workflow.py`

**测试场景**:
1. 创建Channel → 验证ZooKeeper中存在节点
2. 更新Channel → 验证ZooKeeper中数据更新
3. 删除Channel → 验证ZooKeeper中节点删除
4. 批量操作 → 验证多个Channel同步

### 4.3 手工测试

**测试步骤**:

1. **环境准备**
   - 启动ZooKeeper服务
   - 配置环境变量
   - 启动pigeon_web服务

2. **创建通道测试**
   - 在前端创建一个新通道
   - 设置 is_enabled = true
   - 设置 protocol = "SMPP_V32"
   - 提交表单
   - 使用zkCli.sh验证ZooKeeper中的数据

3. **更新通道测试**
   - 修改通道的is_enabled = false
   - 提交表单
   - 验证ZooKeeper中数据更新

4. **删除通道测试**
   - 删除通道
   - 验证ZooKeeper中节点被删除

5. **验证命令**:
```bash
# 连接ZooKeeper
zkCli.sh -server localhost:2181

# 查看通道列表
ls /pigeon/channel_worker/jobs

# 查看具体通道数据
get /pigeon/channel_worker/jobs/channel_001

# 验证数据格式
# 1. account字段（不是upstream_account）
# 2. current_connection字段（不是cur_connection）
# 3. protocol格式（SMPP_V32而不是smpp）
# 4. is_enabled字段存在且正确
# 5. error_codes为null
# 6. max_connection至少为1
```

---

## 五、依赖和环境配置

### 5.1 Python依赖

**检查文件**: `pigeon_web/requirements.txt`

**需要的包**:
```
kazoo>=2.8.0
```

**安装命令**:
```bash
source /Users/yukun-admin/projects/pigeon/venv/bin/activate
pip install kazoo
```

### 5.2 环境变量

**文件**: `.env` 或系统环境变量

**需要配置**:
```bash
# ZooKeeper配置
PIGEON_ZOOKEEPER_HOSTS=localhost:2181
PIGEON_ZOOKEEPER_TIMEOUT=10

# Redis配置（已有）
PIGEON_REDIS_HOST=localhost
PIGEON_REDIS_PORT=8168
PIGEON_REDIS_PASSWORD=
PIGEON_REDIS_DB=10
```

### 5.3 ZooKeeper服务

**启动命令**:
```bash
# 使用Docker启动（如果有docker-compose配置）
cd pigeon/deployment/docker/middleware/zookeeper
docker-compose up -d

# 或者本地启动
zkServer.sh start
```

---

## 六、注意事项

### 6.1 数据迁移

**问题**: 数据库中已有的Channel记录可能有 `enabled` 字段数据

**解决方案**:
1. 在删除 `enabled` 列之前，确保 `is_enabled` 已经有正确的值
2. 如果需要，先运行数据迁移脚本：
```sql
-- 将enabled的值复制到is_enabled（如果is_enabled为NULL）
UPDATE mgmt.channels
SET is_enabled = enabled
WHERE is_enabled IS NULL;
```

### 6.2 向后兼容

**问题**: 前端可能还在使用 `status` 字段判断通道是否active

**解决方案**:
1. 先添加 `is_enabled` 的支持
2. 保持 `status` 字段不删除
3. 后端自动同步：`is_enabled=true` → `status='active'`，`is_enabled=false` → `status='inactive'`

### 6.3 错误处理

**ZooKeeper同步失败的处理**:
1. 记录详细的错误日志
2. 不阻止数据库操作（数据库为主，ZooKeeper为辅）
3. 考虑添加重试机制
4. 考虑添加手动同步接口

### 6.4 性能考虑

**批量操作的优化**:
1. `batch_update_channels()` 方法中，避免每个Channel都单独同步
2. 考虑批量同步或异步同步
3. 添加同步队列机制（如果需要）

---

## 七、风险和应对

### 7.1 风险识别

| 风险 | 影响 | 概率 | 应对措施 |
|-----|------|------|---------|
| ZooKeeper连接失败 | Channel创建/更新失败 | 中 | 降级策略：数据库操作成功，记录同步失败日志 |
| 字段映射错误 | pigeon无法正确读取配置 | 中 | 严格按照文档实现，增加单元测试 |
| protocol格式不一致 | 历史数据同步失败 | 高 | 数据迁移脚本，兼容旧格式 |
| enabled字段删除影响现有功能 | 功能异常 | 低 | 全局搜索，逐个验证修改点 |

### 7.2 回滚方案

如果出现严重问题，回滚步骤：
1. 恢复数据库脚本（保留enabled字段）
2. 恢复Channel模型代码
3. 移除ZooKeeper同步调用
4. 恢复前端代码

---

## 八、验收标准

### 8.1 功能完整性
- [ ] Channel创建时自动同步到ZooKeeper
- [ ] Channel更新时自动同步到ZooKeeper
- [ ] Channel删除时自动从ZooKeeper删除
- [ ] 前端可以设置is_enabled字段
- [ ] enabled字段已完全移除

### 8.2 数据正确性
- [ ] ZooKeeper中的字段名正确映射（account, current_connection）
- [ ] protocol字段格式正确（SMPP_V32, HTTP_V1）
- [ ] encoding字段值正确
- [ ] max_connection最小值为1
- [ ] error_codes为null
- [ ] is_enabled值正确同步

### 8.3 代码质量
- [ ] 所有新增代码有文件头
- [ ] 所有注释使用英文
- [ ] 遵循项目编码规范
- [ ] 单元测试覆盖率 > 80%

### 8.4 文档完整性
- [ ] 代码注释清晰
- [ ] README更新（如需要）
- [ ] 配置说明文档更新

---

## 九、相关文档

- `/Users/yukun-admin/projects/pigeon/yuexin_personal_docs/pigeon_web配置同步改进需求.md`
- `/Users/yukun-admin/projects/pigeon/yuexin_personal_docs/account_in_redis_channel_in_zookeeper.md`
- `/Users/yukun-admin/projects/pigeon/pigeon/src/models/types.go`
- `/Users/yukun-admin/projects/pigeon/yuexin_personal_docs/编码习惯.md`
- `/Users/yukun-admin/projects/pigeon/yuexin_personal_docs/代码提交规范.md`

---

**文档版本**: v1.0
**创建日期**: 2025-01-24
**创建人**: Claude Code
