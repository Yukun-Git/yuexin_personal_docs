# SMS费用计算接口设计文档

## 文档信息
- **创建时间**: 2025-10-21
- **作者**: yukun.xing
- **版本**: v1.0
- **相关需求**: FEAT-3 通道价格管理、财务对账、成本分析

## 1. 背景与目标

### 1.1 业务背景

在SMS业务中，费用计算是核心功能之一，涉及：
- **客户账单**: 按实际发送的SMS数量和价格计费
- **财务对账**: 历史价格可能需要调整，需要区分原始费用和调整后费用
- **成本分析**: 运营需要分析不同通道、国家、时间段的费用分布
- **利润分析**: 对比收入和成本，计算利润率

### 1.2 核心问题

当前系统缺少费用查询能力：
1. 无法查询单条SMS的费用
2. 无法查询聚合维度的费用统计（按通道、国家、时间段等）
3. 无法区分actual_cost（原始费用）和adjusted_cost（调整后费用）

### 1.3 设计目标

设计一套完整的SMS费用查询接口，支持：
- ✅ 单条消息费用查询
- ✅ 批量消息费用查询
- ✅ 聚合统计查询（按多维度分组）
- ✅ 区分actual_cost和adjusted_cost
- ✅ 高性能查询（支持大数据量）

---

## 2. 费用计算原理

### 2.1 双价格表机制

系统维护两个价格表：

| 表名 | 用途 | 是否受历史调整影响 |
|------|------|-------------------|
| `channel_country_actual_prices` | 记录真实的历史价格变更 | ❌ 否 |
| `channel_country_adjusted_prices` | 记录包含历史调整的价格 | ✅ 是 |

**示例场景**：
```
时间线:
T0: 设置价格 0.0500
T1: 设置价格 0.0600
T2: 插入历史调整，在T0.5时刻价格应为 0.0550

actual_prices表:
[T0, T1): 0.0500
[T1, ∞): 0.0600

adjusted_prices表:
[T0, T0.5): 0.0500
[T0.5, T1): 0.0550  ← 历史调整插入的时间段
[T1, ∞): 0.0600
```

### 2.2 费用计算逻辑

**核心原则**: 费用 = 根据SMS的`submit_time`查找对应时间段的价格

```sql
-- 查询actual_cost（原始费用）
SELECT price FROM channel_country_actual_prices
WHERE channel_id = ?
  AND country_code = ?
  AND start_time <= submit_time
  AND (end_time IS NULL OR end_time > submit_time);

-- 查询adjusted_cost（调整后费用）
SELECT price FROM channel_country_adjusted_prices
WHERE channel_id = ?
  AND country_code = ?
  AND start_time <= submit_time
  AND (end_time IS NULL OR end_time > submit_time);
```

**时间段匹配规则**：
- `submit_time` 落在 `[start_time, end_time)` 区间内
- `end_time = NULL` 表示当前生效的价格段

---

## 3. 接口设计

### 3.1 单条消息费用查询

#### 3.1.1 接口定义

```
GET /api/v1/sms/outbox/{message_id}/cost
```

**权限要求**: `sms_read`

**路径参数**:
- `message_id` (string, required): 消息ID

**响应示例**:
```json
{
  "success": true,
  "data": {
    "messageId": "MSG_20251021_001",
    "accountId": "ACC_001",
    "channelId": "CHANNEL_GB_001",
    "countryCode": "GB",
    "submitTime": "2025-10-21 10:30:00",
    "actualCost": 0.0500,
    "adjustedCost": 0.0550,
    "currency": "CNY",
    "costDifference": 0.0050
  },
  "message": "Cost retrieved successfully"
}
```

**字段说明**:
- `actualCost`: 基于actual_prices表的原始费用
- `adjustedCost`: 基于adjusted_prices表的调整后费用
- `costDifference`: `adjustedCost - actualCost`，快速查看调整金额

**错误响应**:
```json
{
  "success": false,
  "code": 404,
  "message": "Message not found"
}
```

---

### 3.2 聚合费用统计查询

#### 3.2.1 接口定义

```
GET /api/v1/sms/outbox/cost-statistics
```

**权限要求**: `sms_read` 或 `sms_cost_analysis`

**查询参数**:

| 参数 | 类型 | 必填 | 说明 | 示例 |
|------|------|------|------|------|
| `start_time` | string | 是 | 开始时间（submit_time） | `2025-10-01 00:00:00` |
| `end_time` | string | 是 | 结束时间（submit_time） | `2025-10-31 23:59:59` |
| `channel_id` | string | 否 | 通道ID过滤 | `CHANNEL_GB_001` |
| `country_code` | string | 否 | 国家代码过滤 | `GB` |
| `account_id` | string | 否 | 账号ID过滤 | `ACC_001` |
| `group_by` | string | 否 | 分组维度，多个用逗号分隔 | `channel_id,country_code` |
| `page` | int | 否 | 页码，默认1 | `1` |
| `per_page` | int | 否 | 每页数量，默认20，最大100 | `20` |

**group_by支持的维度**:
- `channel_id`: 按通道分组
- `country_code`: 按国家分组
- `account_id`: 按账号分组
- `date`: 按日期分组（submit_time的日期部分）
- `hour`: 按小时分组（submit_time的小时部分）

**组合示例**:
- `group_by=channel_id,country_code`: 按通道+国家分组
- `group_by=date,channel_id`: 按日期+通道分组
- 不传`group_by`: 不分组，返回总计

#### 3.2.2 响应示例

**场景1: 不分组查询（总计）**

请求:
```
GET /api/v1/sms/outbox/cost-statistics?start_time=2025-10-01%2000:00:00&end_time=2025-10-31%2023:59:59&channel_id=CHANNEL_GB_001
```

响应:
```json
{
  "success": true,
  "data": {
    "summary": {
      "totalMessages": 15000,
      "totalActualCost": 750.00,
      "totalAdjustedCost": 765.00,
      "totalCostDifference": 15.00,
      "averageActualCost": 0.0500,
      "averageAdjustedCost": 0.0510,
      "currency": "CNY"
    },
    "filters": {
      "startTime": "2025-10-01 00:00:00",
      "endTime": "2025-10-31 23:59:59",
      "channelId": "CHANNEL_GB_001"
    }
  },
  "message": "Statistics retrieved successfully"
}
```

**场景2: 按通道+国家分组**

请求:
```
GET /api/v1/sms/outbox/cost-statistics?start_time=2025-10-01%2000:00:00&end_time=2025-10-31%2023:59:59&group_by=channel_id,country_code
```

响应:
```json
{
  "success": true,
  "data": {
    "summary": {
      "totalMessages": 50000,
      "totalActualCost": 2500.00,
      "totalAdjustedCost": 2550.00,
      "totalCostDifference": 50.00,
      "currency": "CNY"
    },
    "groups": [
      {
        "channelId": "CHANNEL_GB_001",
        "countryCode": "GB",
        "messageCount": 15000,
        "actualCost": 750.00,
        "adjustedCost": 765.00,
        "costDifference": 15.00,
        "averageActualCost": 0.0500,
        "averageAdjustedCost": 0.0510
      },
      {
        "channelId": "CHANNEL_GB_001",
        "countryCode": "US",
        "messageCount": 12000,
        "actualCost": 480.00,
        "adjustedCost": 492.00,
        "costDifference": 12.00,
        "averageActualCost": 0.0400,
        "averageAdjustedCost": 0.0410
      },
      {
        "channelId": "CHANNEL_US_001",
        "countryCode": "GB",
        "messageCount": 10000,
        "actualCost": 520.00,
        "adjustedCost": 530.00,
        "costDifference": 10.00,
        "averageActualCost": 0.0520,
        "averageAdjustedCost": 0.0530
      }
    ],
    "pagination": {
      "page": 1,
      "perPage": 20,
      "total": 3,
      "pages": 1
    }
  },
  "message": "Statistics retrieved successfully"
}
```

**场景3: 按日期分组**

请求:
```
GET /api/v1/sms/outbox/cost-statistics?start_time=2025-10-01%2000:00:00&end_time=2025-10-07%2023:59:59&group_by=date&channel_id=CHANNEL_GB_001
```

响应:
```json
{
  "success": true,
  "data": {
    "summary": {
      "totalMessages": 7000,
      "totalActualCost": 350.00,
      "totalAdjustedCost": 357.00,
      "currency": "CNY"
    },
    "groups": [
      {
        "date": "2025-10-01",
        "messageCount": 1000,
        "actualCost": 50.00,
        "adjustedCost": 51.00
      },
      {
        "date": "2025-10-02",
        "messageCount": 1000,
        "actualCost": 50.00,
        "adjustedCost": 51.00
      }
      // ... 其他日期
    ]
  }
}
```

---

### 3.3 批量消息费用查询

#### 3.3.1 接口定义

```
POST /api/v1/sms/outbox/batch-cost
```

**权限要求**: `sms_read`

**请求体**:
```json
{
  "messageIds": [
    "MSG_001",
    "MSG_002",
    "MSG_003"
  ]
}
```

**限制**: 单次最多查询100条消息

**响应示例**:
```json
{
  "success": true,
  "data": {
    "costs": [
      {
        "messageId": "MSG_001",
        "actualCost": 0.0500,
        "adjustedCost": 0.0550
      },
      {
        "messageId": "MSG_002",
        "actualCost": 0.0520,
        "adjustedCost": 0.0520
      },
      {
        "messageId": "MSG_003",
        "actualCost": null,
        "adjustedCost": null,
        "error": "Message not found"
      }
    ],
    "summary": {
      "totalRequested": 3,
      "totalFound": 2,
      "totalActualCost": 0.1020,
      "totalAdjustedCost": 0.1070
    }
  }
}
```

---

## 4. 数据库查询优化

### 4.1 核心挑战

聚合查询可能涉及：
- 大量消息记录（百万级）
- 跨表JOIN（short_messages + actual_prices + adjusted_prices）
- 复杂分组和聚合计算

### 4.2 优化策略

#### 4.2.1 索引设计

**short_messages表**:
```sql
-- 复合索引：支持时间范围+通道+国家查询
CREATE INDEX idx_messages_time_channel_country
ON sms.short_messages(submit_time, send_channel_id, to_country_code);

-- 复合索引：支持时间范围+账号查询
CREATE INDEX idx_messages_time_account
ON sms.short_messages(submit_time, account_id);
```

**actual_prices / adjusted_prices表**:
```sql
-- 复合索引：支持通道+国家+时间范围查询
CREATE INDEX idx_prices_channel_country_time
ON channel_country_actual_prices(channel_id, country_code, start_time, end_time);

CREATE INDEX idx_adjusted_prices_channel_country_time
ON channel_country_adjusted_prices(channel_id, country_code, start_time, end_time);
```

#### 4.2.2 查询SQL示例

**不分组总计查询**:
```sql
WITH message_costs AS (
    SELECT
        m.message_id,
        m.submit_time,
        m.send_channel_id,
        m.to_country_code,
        -- 查询actual_cost
        (SELECT ap.price
         FROM channel_country_actual_prices ap
         WHERE ap.channel_id = m.send_channel_id
           AND ap.country_code = m.to_country_code
           AND ap.start_time <= m.submit_time
           AND (ap.end_time IS NULL OR ap.end_time > m.submit_time)
         LIMIT 1
        ) as actual_cost,
        -- 查询adjusted_cost
        (SELECT adp.price
         FROM channel_country_adjusted_prices adp
         WHERE adp.channel_id = m.send_channel_id
           AND adp.country_code = m.to_country_code
           AND adp.start_time <= m.submit_time
           AND (adp.end_time IS NULL OR adp.end_time > m.submit_time)
         LIMIT 1
        ) as adjusted_cost
    FROM sms.short_messages m
    WHERE m.submit_time BETWEEN :start_time AND :end_time
      AND (:channel_id IS NULL OR m.send_channel_id = :channel_id)
      AND (:country_code IS NULL OR m.to_country_code = :country_code)
      AND (:account_id IS NULL OR m.account_id = :account_id)
)
SELECT
    COUNT(*) as total_messages,
    SUM(actual_cost) as total_actual_cost,
    SUM(adjusted_cost) as total_adjusted_cost,
    AVG(actual_cost) as avg_actual_cost,
    AVG(adjusted_cost) as avg_adjusted_cost
FROM message_costs;
```

**按通道+国家分组查询**:
```sql
WITH message_costs AS (
    -- 同上
)
SELECT
    send_channel_id,
    to_country_code,
    COUNT(*) as message_count,
    SUM(actual_cost) as actual_cost_sum,
    SUM(adjusted_cost) as adjusted_cost_sum,
    AVG(actual_cost) as avg_actual_cost,
    AVG(adjusted_cost) as avg_adjusted_cost
FROM message_costs
GROUP BY send_channel_id, to_country_code
ORDER BY actual_cost_sum DESC
LIMIT :limit OFFSET :offset;
```

#### 4.2.3 性能目标

| 场景 | 数据量 | 目标响应时间 |
|------|--------|-------------|
| 单条消息查询 | 1条 | < 50ms |
| 批量查询 | 100条 | < 200ms |
| 聚合查询（不分组） | 100万条消息 | < 2s |
| 聚合查询（分组） | 100万条消息 | < 5s |

---

## 5. 实现架构

### 5.1 代码结构

```
app/
├── api/v1/sms/route/
│   ├── outbox_cost.py          # 单条消息费用查询API
│   ├── outbox_cost_batch.py    # 批量费用查询API
│   └── outbox_cost_statistics.py  # 聚合统计查询API
├── services/sms/
│   └── cost_service.py         # 费用计算Service
└── models/messages/
    └── message.py              # ShortMessage模型
```

### 5.2 Service层设计

```python
class SmsCostService:
    """SMS费用计算服务"""

    def calculate_message_cost(self, message_id: str) -> Dict[str, Any]:
        """计算单条消息费用"""
        pass

    def calculate_batch_cost(self, message_ids: List[str]) -> Dict[str, Any]:
        """批量计算消息费用"""
        pass

    def calculate_statistics(
        self,
        start_time: datetime,
        end_time: datetime,
        filters: Dict[str, Any],
        group_by: Optional[List[str]] = None,
        page: int = 1,
        per_page: int = 20
    ) -> Dict[str, Any]:
        """聚合统计查询"""
        pass

    def _query_price_at_time(
        self,
        table: str,  # 'actual' or 'adjusted'
        channel_id: str,
        country_code: str,
        time_point: datetime
    ) -> Optional[Decimal]:
        """在指定时间点查询价格"""
        pass

    def _get_message_info(self, message_id: str) -> Optional[Dict]:
        """获取消息基本信息"""
        pass

    def _build_statistics_query(
        self,
        start_time: datetime,
        end_time: datetime,
        filters: Dict[str, Any],
        group_by: Optional[List[str]]
    ) -> str:
        """构建聚合查询SQL"""
        pass
```

---

## 6. 使用场景示例

### 6.1 场景：查看单条SMS费用

**用途**: 客户咨询某条消息的计费情况

**操作**:
```bash
curl -X GET \
  'http://api.example.com/api/v1/sms/outbox/MSG_001/cost' \
  -H 'Authorization: Bearer {token}'
```

**结果**:
```json
{
  "actualCost": 0.0500,
  "adjustedCost": 0.0550,
  "costDifference": 0.0050
}
```

### 6.2 场景：财务对账 - 查看某通道某月总费用

**用途**: 月度财务对账，计算通道费用

**操作**:
```bash
curl -X GET \
  'http://api.example.com/api/v1/sms/outbox/cost-statistics?start_time=2025-10-01%2000:00:00&end_time=2025-10-31%2023:59:59&channel_id=CHANNEL_GB_001'
```

**结果**:
```json
{
  "totalMessages": 150000,
  "totalActualCost": 7500.00,
  "totalAdjustedCost": 7650.00,
  "totalCostDifference": 150.00
}
```

**分析**:
- 本月该通道发送15万条消息
- 原始费用7500元
- 由于历史价格调整，实际应付7650元
- 调整金额150元

### 6.3 场景：成本分析 - 各通道各国家费用分布

**用途**: 运营分析不同通道和国家的费用情况，优化通道选择

**操作**:
```bash
curl -X GET \
  'http://api.example.com/api/v1/sms/outbox/cost-statistics?start_time=2025-10-01%2000:00:00&end_time=2025-10-31%2023:59:59&group_by=channel_id,country_code'
```

**结果**:
```json
{
  "groups": [
    {
      "channelId": "CHANNEL_GB_001",
      "countryCode": "GB",
      "messageCount": 50000,
      "actualCost": 2500.00,
      "averageActualCost": 0.0500
    },
    {
      "channelId": "CHANNEL_GB_002",
      "countryCode": "GB",
      "messageCount": 45000,
      "actualCost": 2340.00,
      "averageActualCost": 0.0520
    }
  ]
}
```

**分析**:
- CHANNEL_GB_001单价0.0500，发送5万条
- CHANNEL_GB_002单价0.0520，发送4.5万条
- 虽然GB_002单价略高，但可能送达率更好

### 6.4 场景：按日统计趋势分析

**用途**: 查看每日费用趋势，发现异常

**操作**:
```bash
curl -X GET \
  'http://api.example.com/api/v1/sms/outbox/cost-statistics?start_time=2025-10-01%2000:00:00&end_time=2025-10-31%2023:59:59&group_by=date&channel_id=CHANNEL_GB_001'
```

**结果**:
```json
{
  "groups": [
    {"date": "2025-10-01", "actualCost": 240.00},
    {"date": "2025-10-02", "actualCost": 250.00},
    {"date": "2025-10-03", "actualCost": 245.00},
    {"date": "2025-10-04", "actualCost": 520.00},  // 异常高
    {"date": "2025-10-05", "actualCost": 248.00}
  ]
}
```

**分析**: 10月4日费用异常高，需要排查是否有批量发送或价格异常

---

## 7. 安全与权限

### 7.1 权限控制

| 接口 | 权限 | 说明 |
|------|------|------|
| 单条费用查询 | `sms_read` | 基础查询权限 |
| 批量费用查询 | `sms_read` | 基础查询权限 |
| 聚合统计查询 | `sms_read` 或 `sms_cost_analysis` | 统计分析权限 |

### 7.2 数据隔离

- 普通用户只能查询自己账号的消息费用
- 管理员可以查询所有消息费用
- 基于 `account_id` 进行数据过滤

### 7.3 访问频率限制

- 单条查询: 100次/分钟
- 批量查询: 20次/分钟
- 聚合查询: 10次/分钟

---

## 8. 错误处理

### 8.1 常见错误码

| 错误码 | 说明 | 处理建议 |
|--------|------|----------|
| 400 | 参数错误 | 检查参数格式和范围 |
| 404 | 消息不存在 | 确认message_id正确 |
| 404 | 价格未配置 | 该通道+国家组合没有价格配置 |
| 403 | 权限不足 | 检查用户权限 |
| 429 | 请求过于频繁 | 降低请求频率 |
| 500 | 服务器错误 | 联系技术支持 |

### 8.2 异常情况处理

**情况1: 消息存在但价格未配置**
```json
{
  "messageId": "MSG_001",
  "actualCost": null,
  "adjustedCost": null,
  "warning": "No price configured for channel CHANNEL_001 and country GB"
}
```

**情况2: 部分消息查询失败（批量查询）**
```json
{
  "costs": [
    {"messageId": "MSG_001", "actualCost": 0.05},
    {"messageId": "MSG_002", "error": "Message not found"}
  ]
}
```

---

## 9. 测试计划

### 9.1 单元测试

- ✅ Service层费用计算逻辑
- ✅ 价格查询准确性（边界时间点）
- ✅ 参数验证
- ✅ 错误处理

### 9.2 集成测试

- ✅ 单条费用查询（test_price_calculation_for_sms_with_time_segments）
- ✅ 批量费用查询
- ✅ 聚合统计查询（各种分组维度）
- ✅ 历史价格调整影响验证

### 9.3 性能测试

- ✅ 100万消息聚合查询 < 5s
- ✅ 索引效果验证
- ✅ 并发查询测试

---

## 10. 实施计划

### 10.1 开发阶段

**Phase 1: 基础功能（优先级P0）**
- [ ] 实现单条消息费用查询API
- [ ] 实现费用计算Service层
- [ ] 添加数据库索引
- [ ] 编写单元测试

10月21日：只实现了 phase 1

**Phase 2: 批量查询（优先级P1）**
- [ ] 实现批量费用查询API
- [ ] 优化批量查询性能

**Phase 3: 聚合统计（优先级P1）**
- [ ] 实现聚合统计查询API
- [ ] 支持多维度分组
- [ ] 性能优化和调优

**Phase 4: 优化迭代（优先级P2）**
- [ ] 查询结果缓存
- [ ] 异步导出大数据量统计
- [ ] 监控和告警

### 10.2 工作量估算

| 阶段 | 工作量 | 说明 |
|------|--------|------|
| Phase 1 | 1天 | 核心功能实现 |
| Phase 2 | 0.5天 | 批量查询 |
| Phase 3 | 2天 | 聚合统计，含SQL优化 |
| Phase 4 | 1天 | 优化迭代 |
| **总计** | **4.5天** | 含测试和文档 |

---

## 11. 未来扩展

### 11.1 短期规划

- 导出功能：支持CSV/Excel导出聚合统计结果
- 可视化：费用趋势图表
- 预警：费用异常自动告警

### 11.2 长期规划

- 实时费用计算：消息发送时即时计算并记录费用
- 费用预测：基于历史数据预测未来费用
- 智能推荐：基于费用分析推荐最优通道配置

---

## 12. 总结

本设计文档提供了完整的SMS费用计算接口方案：

1. ✅ **双价格机制**: 区分actual_cost和adjusted_cost，支持历史调整
2. ✅ **三层API**: 单条查询、批量查询、聚合统计
3. ✅ **多维度分组**: 支持按通道、国家、账号、时间等维度统计
4. ✅ **高性能设计**: 索引优化、SQL优化，支持百万级数据查询
5. ✅ **完整的错误处理**: 覆盖各种异常情况

通过这套接口，可以满足：
- 客户账单查询
- 财务对账
- 成本分析
- 运营决策

的全方位需求。
