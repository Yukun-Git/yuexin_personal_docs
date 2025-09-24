# FEAT-1-3 发送账号连接信息功能开发计划

## 📋 项目概述

**功能目标**: 开发发送账号连接信息管理系统，实现发送账号与企业账号连接关系的查看、筛选、监控功能
**优先级**: P1 - 高
**预计工期**: 5-7个工作日

## 🏗️ 现有架构分析

### 数据库架构
- **PostgreSQL** 数据库，模块化SQL文件组织
- **已有表结构**:
  - `accounts` - 发送账号表（支持多协议：SMPP、HTTP等）
  - `enterprises` - 企业账号表（简化架构，专注账号管理）
- **索引策略**: 完善的查询索引，支持高性能检索
- **时间戳管理**: 统一的created_at/updated_at字段

### 后端架构
- **Flask + SQLAlchemy** 框架
- **RESTful API** 设计，按模块组织 (`/app/api/v1/`)
- **RBAC权限系统** 完整实现
- **三层架构**: API层 → Service层 → Model层

### 前端架构
- **React 18 + TypeScript** 技术栈
- **Redux Toolkit + RTK Query** 状态管理
- **Ant Design** UI组件库
- **模块化页面组织** 结构清晰

## 🗃️ 数据库Schema设计

### 核心表设计

#### 1. 发送账号连接记录表 (account_connections)

```sql
-- Copyright(c) 2025
-- All rights reserved.
--
-- Author: yukun.xing <xingyukun@gmail.com>
-- Date:   2025/09/23
--
-- 发送账号连接信息表

CREATE TABLE IF NOT EXISTS account_connections (
    -- 主键
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 关联关系
    account_id VARCHAR(255) NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    enterprise_id UUID REFERENCES enterprises(id) ON DELETE SET NULL,

    -- 连接信息
    client_ip INET NOT NULL,
    client_name VARCHAR(255),
    protocol_type protocol_type NOT NULL,

    -- 状态信息
    connection_status connection_status_enum DEFAULT 'connected' NOT NULL,
    data_status data_status_enum DEFAULT 'current' NOT NULL,

    -- 连接详情
    connection_details JSONB DEFAULT '{}',
    error_message TEXT,

    -- 时间信息
    connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    disconnected_at TIMESTAMP,
    last_heartbeat_at TIMESTAMP,

    -- 审计信息
    created_by INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- 枚举类型定义
CREATE TYPE connection_status_enum AS ENUM (
    'connected',      -- 已连接
    'disconnected',   -- 已断开
    'connecting',     -- 连接中
    'error',          -- 异常
    'timeout'         -- 超时
);

CREATE TYPE data_status_enum AS ENUM (
    'current',        -- 当前
    'historical'      -- 历史
);
```

#### 2. 连接状态变更日志表 (connection_status_logs)

```sql
-- 连接状态变更日志表
CREATE TABLE IF NOT EXISTS connection_status_logs (
    -- 主键
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 关联连接记录
    connection_id UUID NOT NULL REFERENCES account_connections(id) ON DELETE CASCADE,

    -- 状态变更信息
    old_status connection_status_enum,
    new_status connection_status_enum NOT NULL,

    -- 变更原因
    change_reason TEXT,
    error_details JSONB DEFAULT '{}',

    -- 时间信息
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,

    -- 操作人信息
    changed_by INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,
    change_source VARCHAR(50) DEFAULT 'system' -- system, manual, heartbeat
);
```

### 索引设计

```sql
-- account_connections 表索引
CREATE INDEX IF NOT EXISTS idx_account_connections_account_id
    ON account_connections(account_id);
CREATE INDEX IF NOT EXISTS idx_account_connections_enterprise_id
    ON account_connections(enterprise_id);
CREATE INDEX IF NOT EXISTS idx_account_connections_client_ip
    ON account_connections(client_ip);
CREATE INDEX IF NOT EXISTS idx_account_connections_status
    ON account_connections(connection_status);
CREATE INDEX IF NOT EXISTS idx_account_connections_data_status
    ON account_connections(data_status);
CREATE INDEX IF NOT EXISTS idx_account_connections_protocol
    ON account_connections(protocol_type);
CREATE INDEX IF NOT EXISTS idx_account_connections_connected_at
    ON account_connections(connected_at);
CREATE INDEX IF NOT EXISTS idx_account_connections_heartbeat
    ON account_connections(last_heartbeat_at);

-- 复合索引用于常见查询
CREATE INDEX IF NOT EXISTS idx_account_connections_active
    ON account_connections(connection_status, data_status, connected_at);
CREATE INDEX IF NOT EXISTS idx_account_connections_enterprise_status
    ON account_connections(enterprise_id, connection_status);

-- connection_status_logs 表索引
CREATE INDEX IF NOT EXISTS idx_connection_logs_connection_id
    ON connection_status_logs(connection_id);
CREATE INDEX IF NOT EXISTS idx_connection_logs_changed_at
    ON connection_status_logs(changed_at);
CREATE INDEX IF NOT EXISTS idx_connection_logs_status
    ON connection_status_logs(new_status);
```

### Mock数据设计

```sql
-- 测试连接记录数据
INSERT INTO account_connections (
    account_id, enterprise_id, client_ip, client_name, protocol_type,
    connection_status, data_status, connected_at, last_heartbeat_at
) VALUES
-- 已连接状态
('vCuneG', (SELECT id FROM enterprises WHERE account_code = 'ENT001'),
 '121.40.208.180', 'cmsip', 'smpp', 'connected', 'current',
 '2025-09-22 16:16:34', '2025-09-22 16:20:00'),

-- 异常状态
('vCuneG', (SELECT id FROM enterprises WHERE account_code = 'ENT001'),
 '121.40.208.180', 'cmsip', 'smpp', 'error', 'historical',
 '2025-09-22 16:16:03', '2025-09-22 16:16:05'),

-- 不同协议的连接
('VzbYp5', (SELECT id FROM enterprises WHERE account_code = 'ENT002'),
 '8.219.208.223', 'smsip', 'http', 'connected', 'current',
 '2025-09-22 16:09:28', '2025-09-22 16:21:00'),

('VgbMn', (SELECT id FROM enterprises WHERE account_code = 'ENT003'),
 '223.118.36.5', 'smsip', 'smpp', 'connected', 'current',
 '2025-09-22 16:01:31', '2025-09-22 16:22:00');
```

## 🔧 后端API设计

### API模块结构

```
app/api/v1/account_connections/
├── route/
│   ├── __init__.py
│   ├── routes.py                    # 路由注册
│   ├── connection_list.py           # 连接列表API
│   ├── connection_detail.py         # 连接详情API
│   ├── connection_statistics.py     # 连接统计API
│   └── connection_export.py         # 数据导出API
├── schema/
│   ├── __init__.py
│   ├── connection.py               # 连接信息Schema
│   └── query.py                    # 查询参数Schema
└── __init__.py
```

### 核心API端点

#### 1. 连接列表查询 API

```python
# GET /api/v1/account-connections
# 查询参数Schema
class ConnectionListQuerySchema(Schema):
    # 分页参数
    page = fields.Integer(validate=Range(min=1), default=1)
    per_page = fields.Integer(validate=Range(min=1, max=100), default=20)

    # 筛选参数
    account_id = fields.String(allow_none=True)
    enterprise_id = fields.UUID(allow_none=True)
    client_ip = fields.String(allow_none=True)
    client_name = fields.String(allow_none=True)
    protocol_type = fields.String(validate=OneOf(['smpp', 'http', 'custom']))
    connection_status = fields.String(validate=OneOf(['connected', 'disconnected', 'error']))
    data_status = fields.String(validate=OneOf(['current', 'historical']))

    # 时间范围筛选
    start_date = fields.DateTime(allow_none=True)
    end_date = fields.DateTime(allow_none=True)

    # 排序参数
    sort_by = fields.String(default='connected_at')
    sort_order = fields.String(validate=OneOf(['asc', 'desc']), default='desc')

# 响应Schema
class ConnectionListResponseSchema(Schema):
    id = fields.UUID()
    account_id = fields.String()
    account_name = fields.String()
    enterprise_id = fields.UUID()
    enterprise_name = fields.String()
    client_ip = fields.String()
    client_name = fields.String()
    protocol_type = fields.String()
    connection_status = fields.String()
    data_status = fields.String()
    connected_at = fields.DateTime()
    disconnected_at = fields.DateTime(allow_none=True)
    last_heartbeat_at = fields.DateTime(allow_none=True)
    error_message = fields.String(allow_none=True)
```

#### 2. 实时统计 API

```python
# GET /api/v1/account-connections/statistics
class ConnectionStatisticsSchema(Schema):
    total_connections = fields.Integer()
    connected_count = fields.Integer()
    disconnected_count = fields.Integer()
    error_count = fields.Integer()

    by_protocol = fields.Dict()
    by_status = fields.Dict()
    last_updated = fields.DateTime()
```

#### 3. 自动刷新数据 API

```python
# GET /api/v1/account-connections/refresh
# 支持轮询更新，返回增量数据
class RefreshResponseSchema(Schema):
    has_updates = fields.Boolean()
    last_check = fields.DateTime()
    updated_connections = fields.List(fields.Nested(ConnectionListResponseSchema))
    statistics = fields.Nested(ConnectionStatisticsSchema)
```

### Service层设计

```python
class AccountConnectionService:

    @staticmethod
    def get_connections_list(query_params: dict) -> dict:
        """获取连接列表"""

    @staticmethod
    def get_connection_statistics() -> dict:
        """获取连接统计信息"""

    @staticmethod
    def update_connection_status(connection_id: str, status: str, reason: str = None):
        """更新连接状态"""

    @staticmethod
    def cleanup_historical_data(days: int = 30):
        """清理历史数据"""

    @staticmethod
    def export_connections_data(query_params: dict, format: str = 'excel') -> bytes:
        """导出连接数据"""
```

## 🎨 前端组件架构设计

### 页面组织结构

```
src/pages/AccountControl/SendingAccountConnections/
├── index.tsx                        # 主页面入口
├── SendingAccountConnectionPage.tsx # 主页面组件
├── components/
│   ├── index.ts                     # 组件统一导出
│   ├── ConnectionTable.tsx          # 连接列表表格
│   ├── ConnectionSearchFilter.tsx   # 搜索筛选组件
│   ├── ConnectionStatistics.tsx     # 统计面板
│   ├── AutoRefreshControl.tsx       # 自动刷新控制
│   ├── ConnectionDetailModal.tsx    # 连接详情弹窗
│   └── ConnectionStatusBadge.tsx    # 状态标签组件
├── hooks/
│   ├── useConnectionData.ts         # 连接数据Hook
│   ├── useAutoRefresh.ts           # 自动刷新Hook
│   └── useConnectionFilter.ts       # 筛选逻辑Hook
└── types/
    └── connection.ts               # TypeScript类型定义
```

### 核心组件设计

#### 1. 主页面组件

```typescript
// SendingAccountConnectionPage.tsx
interface SendingAccountConnectionPageProps {}

export const SendingAccountConnectionPage: React.FC = () => {
  const [filterParams, setFilterParams] = useState<ConnectionFilterParams>({});
  const [autoRefreshEnabled, setAutoRefreshEnabled] = useState(false);
  const [refreshInterval, setRefreshInterval] = useState(60); // 60秒

  // 数据获取
  const {
    data: connections,
    isLoading,
    error,
    refetch
  } = useConnectionData(filterParams);

  // 自动刷新
  useAutoRefresh({
    enabled: autoRefreshEnabled,
    interval: refreshInterval,
    callback: refetch
  });

  return (
    <div className="sending-account-connection-page">
      <PageHeader title="发送账号连接信息" />

      <ConnectionSearchFilter
        onFilterChange={setFilterParams}
        onReset={() => setFilterParams({})}
      />

      <AutoRefreshControl
        enabled={autoRefreshEnabled}
        interval={refreshInterval}
        onToggle={setAutoRefreshEnabled}
        onIntervalChange={setRefreshInterval}
        lastUpdate={data?.lastUpdate}
      />

      <ConnectionStatistics data={connections?.statistics} />

      <ConnectionTable
        data={connections?.data}
        loading={isLoading}
        onRefresh={refetch}
      />
    </div>
  );
};
```

#### 2. 自动刷新控制组件

```typescript
// AutoRefreshControl.tsx
interface AutoRefreshControlProps {
  enabled: boolean;
  interval: number; // 秒
  onToggle: (enabled: boolean) => void;
  onIntervalChange: (interval: number) => void;
  lastUpdate?: string;
  status?: 'idle' | 'refreshing' | 'error' | 'paused';
}

export const AutoRefreshControl: React.FC<AutoRefreshControlProps> = ({
  enabled,
  interval,
  onToggle,
  onIntervalChange,
  lastUpdate,
  status = 'idle'
}) => {
  const [countdown, setCountdown] = useState(interval);

  // 倒计时逻辑
  useEffect(() => {
    if (!enabled || status === 'paused') return;

    const timer = setInterval(() => {
      setCountdown(prev => {
        if (prev <= 1) {
          return interval;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(timer);
  }, [enabled, interval, status]);

  const getStatusText = () => {
    if (!enabled) return '已停止';
    if (status === 'refreshing') return '正在刷新...';
    if (status === 'paused') return '已暂停(用户操作中)';
    if (status === 'error') return '刷新失败';
    return `下次刷新: ${countdown}秒后`;
  };

  const getStatusIcon = () => {
    if (status === 'refreshing') return <LoadingOutlined spin />;
    if (status === 'error') return <ExclamationCircleOutlined style={{ color: '#ff4d4f' }} />;
    if (status === 'paused') return <PauseOutlined style={{ color: '#faad14' }} />;
    return enabled ? <CheckCircleOutlined style={{ color: '#52c41a' }} /> : null;
  };

  return (
    <div className="auto-refresh-control">
      <Space size="large">
        <div className="refresh-toggle">
          <span>自动刷新:</span>
          <Switch
            checked={enabled}
            onChange={onToggle}
            checkedChildren="开启"
            unCheckedChildren="关闭"
          />
        </div>

        <div className="refresh-interval">
          <span>刷新间隔:</span>
          <Select
            value={interval}
            onChange={onIntervalChange}
            style={{ width: 80 }}
            options={[
              { label: '30秒', value: 30 },
              { label: '60秒', value: 60 },
              { label: '2分钟', value: 120 },
              { label: '5分钟', value: 300 },
            ]}
          />
        </div>

        <div className="refresh-status">
          <Space>
            {getStatusIcon()}
            <span>状态: {getStatusText()}</span>
          </Space>
        </div>

        {lastUpdate && (
          <div className="last-update">
            <span>最后更新: {formatDateTime(lastUpdate)}</span>
          </div>
        )}

        <Button
          icon={<ReloadOutlined />}
          onClick={() => window.location.reload()}
          disabled={status === 'refreshing'}
        >
          手动刷新
        </Button>
      </Space>
    </div>
  );
};
```

#### 3. 连接状态标签组件

```typescript
// ConnectionStatusBadge.tsx
interface ConnectionStatusBadgeProps {
  status: 'connected' | 'disconnected' | 'error' | 'connecting' | 'timeout';
  errorMessage?: string;
}

export const ConnectionStatusBadge: React.FC<ConnectionStatusBadgeProps> = ({
  status,
  errorMessage
}) => {
  const getStatusConfig = () => {
    switch (status) {
      case 'connected':
        return {
          color: 'success',
          icon: <CheckCircleOutlined />,
          text: '已连接'
        };
      case 'disconnected':
        return {
          color: 'default',
          icon: <MinusCircleOutlined />,
          text: '已断开'
        };
      case 'error':
        return {
          color: 'error',
          icon: <ExclamationCircleOutlined />,
          text: '异常'
        };
      case 'connecting':
        return {
          color: 'processing',
          icon: <LoadingOutlined spin />,
          text: '连接中'
        };
      case 'timeout':
        return {
          color: 'warning',
          icon: <ClockCircleOutlined />,
          text: '超时'
        };
      default:
        return {
          color: 'default',
          icon: null,
          text: status
        };
    }
  };

  const config = getStatusConfig();

  const badge = (
    <Badge
      status={config.color as any}
      text={
        <Space size={4}>
          {config.icon}
          {config.text}
        </Space>
      }
    />
  );

  // 如果有错误信息，添加Tooltip
  if (status === 'error' && errorMessage) {
    return (
      <Tooltip title={errorMessage} placement="topLeft">
        {badge}
      </Tooltip>
    );
  }

  return badge;
};
```

### API和状态管理

```typescript
// src/api/accountConnectionApi.ts
export const accountConnectionApi = createApi({
  reducerPath: 'accountConnectionApi',
  baseQuery: fetchBaseQuery({
    baseUrl: '/api/v1/account-connections',
    prepareHeaders: (headers, { getState }) => {
      const token = (getState() as RootState).auth.token;
      if (token) {
        headers.set('authorization', `Bearer ${token}`);
      }
      return headers;
    },
  }),
  tagTypes: ['AccountConnection', 'ConnectionStatistics'],
  endpoints: (builder) => ({
    getConnections: builder.query<ConnectionListResponse, ConnectionListQuery>({
      query: (params) => ({
        url: '',
        params: params,
      }),
      providesTags: ['AccountConnection'],
    }),

    getConnectionStatistics: builder.query<ConnectionStatistics, void>({
      query: () => '/statistics',
      providesTags: ['ConnectionStatistics'],
    }),

    refreshConnections: builder.query<RefreshResponse, string>({
      query: (lastCheck) => ({
        url: '/refresh',
        params: { last_check: lastCheck },
      }),
    }),

    exportConnections: builder.mutation<Blob, ConnectionExportQuery>({
      query: (params) => ({
        url: '/export',
        method: 'POST',
        body: params,
        responseHandler: (response) => response.blob(),
      }),
    }),
  }),
});

export const {
  useGetConnectionsQuery,
  useGetConnectionStatisticsQuery,
  useRefreshConnectionsQuery,
  useExportConnectionsMutation,
} = accountConnectionApi;
```

## 📝 详细开发计划

### 阶段1：数据库Schema实现 (1天)

#### 任务1.1：创建数据库Schema文件
- **文件**: `pigeon_web/sql/modules/account_connections.sql`
- **内容**:
  - account_connections表定义
  - connection_status_logs表定义
  - 枚举类型定义
  - 索引创建
- **验证**: SQL语法检查，数据库初始化测试

#### 任务1.2：添加Mock数据
- **文件**: `pigeon_web/sql/mock_data/account_connections.sql`
- **内容**:
  - 测试连接记录数据
  - 覆盖各种状态和协议类型
  - 关联现有accounts和enterprises数据
- **验证**: 数据插入成功，查询正常

#### 任务1.3：更新主SQL文件
- **文件**: `pigeon_web/sql/pigeon_web.sql`
- **任务**: 集成新的模块文件
- **验证**: 完整数据库初始化成功

### 阶段2：后端Model和Service开发 (1.5天)

#### 任务2.1：创建Model层
- **文件**: `pigeon_web/app/models/customers/account_connection.py`
- **内容**:
  - AccountConnection模型类
  - ConnectionStatusLog模型类
  - 关系定义和方法
- **验证**: Model导入测试，基本CRUD操作

#### 任务2.2：创建Service层
- **文件**: `pigeon_web/app/services/account_connection_service.py`
- **功能**:
  - 连接列表查询（支持筛选、分页、排序）
  - 连接统计信息
  - 状态更新和日志记录
  - 数据导出功能
- **验证**: Service方法单元测试

#### 任务2.3：创建Schema层
- **目录**: `pigeon_web/app/api/v1/account_connections/schema/`
- **文件**:
  - `connection.py` - 连接信息Schema
  - `query.py` - 查询参数Schema
- **验证**: Schema序列化/反序列化测试

### 阶段3：后端API开发 (1.5天)

#### 任务3.1：创建API路由
- **目录**: `pigeon_web/app/api/v1/account_connections/route/`
- **文件**:
  - `routes.py` - 路由注册
  - `connection_list.py` - 列表查询API
  - `connection_detail.py` - 详情查询API
  - `connection_statistics.py` - 统计API
  - `connection_export.py` - 导出API
- **验证**: API端点访问测试

#### 任务3.2：集成到主应用
- **文件**: `pigeon_web/app/__init__.py`
- **任务**: 注册新的API模块
- **验证**: API路由正确注册

#### 任务3.3：权限配置
- **任务**:
  - 添加account_connection相关权限
  - 配置RBAC权限验证
- **验证**: 权限控制正常工作

### 阶段4：前端基础组件开发 (1.5天)

#### 任务4.1：创建页面结构
- **目录**: `pigeon_web/frontend/src/pages/AccountControl/SendingAccountConnections/`
- **文件**:
  - `index.tsx` - 页面入口
  - `SendingAccountConnectionPage.tsx` - 主页面
  - `types/connection.ts` - TypeScript类型
- **验证**: 页面路由正常显示

#### 任务4.2：开发核心组件
- **文件**:
  - `ConnectionTable.tsx` - 列表表格
  - `ConnectionSearchFilter.tsx` - 搜索筛选
  - `ConnectionStatusBadge.tsx` - 状态标签
- **验证**: 组件正常渲染，交互正常

#### 任务4.3：创建API集成
- **文件**:
  - `src/api/accountConnectionApi.ts` - RTK Query API
  - `src/hooks/useConnectionData.ts` - 数据Hook
- **验证**: API调用正常，数据显示正确

### 阶段5：高级功能开发 (1天)

#### 任务5.1：自动刷新功能
- **文件**:
  - `AutoRefreshControl.tsx` - 自动刷新控制
  - `useAutoRefresh.ts` - 自动刷新Hook
- **功能**:
  - 可配置刷新间隔
  - 智能暂停机制
  - 状态显示和错误处理
- **验证**: 自动刷新正常工作

#### 任务5.2：统计面板
- **文件**: `ConnectionStatistics.tsx`
- **功能**:
  - 实时连接统计
  - 状态分布图表
  - 协议类型统计
- **验证**: 统计数据准确显示

#### 任务5.3：导出功能
- **功能**:
  - Excel格式导出
  - 筛选条件应用
  - 下载进度显示
- **验证**: 导出文件格式正确

### 阶段6：集成测试和优化 (0.5天)

#### 任务6.1：路由集成
- **文件**: `src/router/index.tsx`
- **任务**: 添加新页面路由
- **验证**: 页面导航正常

#### 任务6.2：菜单集成
- **文件**: `src/pages/Layout/Sidebar/menuConfig.tsx`
- **任务**: 添加菜单项
- **验证**: 菜单显示和跳转正常

#### 任务6.3：权限集成
- **任务**: 前端权限验证
- **验证**: 无权限用户无法访问

#### 任务6.4：性能优化
- **任务**:
  - 数据缓存策略
  - 分页性能优化
  - 查询索引验证
- **验证**: 大数据量下性能表现良好

### 阶段7：测试和文档 (0.5天)

#### 任务7.1：功能测试
- **测试项目**:
  - 筛选功能测试
  - 自动刷新测试
  - 导出功能测试
  - 权限控制测试
- **验证**: 所有功能正常工作

#### 任务7.2：集成测试
- **测试项目**:
  - 前后端数据流测试
  - 异常情况处理测试
  - 并发访问测试
- **验证**: 系统稳定可靠

#### 任务7.3：文档更新
- **任务**:
  - 更新API文档
  - 更新用户使用说明
  - 更新部署文档
- **验证**: 文档完整准确

## 🎯 关键技术要点

### 性能优化
1. **数据库层**:
   - 合理索引设计，支持复合查询
   - 分页查询优化
   - 历史数据清理策略

2. **后端层**:
   - 查询结果缓存
   - 批量操作优化
   - 异步任务处理

3. **前端层**:
   - 虚拟滚动（大数据量）
   - 智能刷新策略
   - 组件懒加载

### 用户体验
1. **响应式设计**: 支持不同屏幕尺寸
2. **实时反馈**: 加载状态、操作结果提示
3. **智能交互**: 自动暂停、错误恢复
4. **可访问性**: 键盘导航、屏幕阅读器支持

### 安全性
1. **权限控制**: 基于RBAC的细粒度权限
2. **数据脱敏**: 敏感信息保护
3. **输入验证**: 前后端双重验证
4. **操作审计**: 完整的操作日志

## 📋 验收标准

### 功能性验收
- [ ] 发送账号连接信息查询和显示正常
- [ ] 多维度筛选功能工作正常
- [ ] 自动刷新功能稳定可靠
- [ ] 导出功能正确生成文件
- [ ] 权限控制有效

### 性能验收
- [ ] 查询响应时间 < 3秒
- [ ] 大数据量(10000+)处理正常
- [ ] 自动刷新不影响用户操作
- [ ] 内存使用稳定，无内存泄漏

### 安全验收
- [ ] 权限验证有效
- [ ] 敏感数据脱敏正确
- [ ] 操作审计完整

### 兼容性验收
- [ ] 多浏览器兼容
- [ ] 响应式设计正常
- [ ] 移动端显示良好

## 🚀 部署和发布

### 数据库更新
```bash
# 应用新的Schema更改
psql -h localhost -p 8668 -U yuexin -d pigeon_sms -f pigeon_web/sql/modules/account_connections.sql

# 导入Mock数据
psql -h localhost -p 8668 -U yuexin -d pigeon_sms -f pigeon_web/sql/mock_data/account_connections.sql
```

### 后端部署
```bash
# 激活虚拟环境
source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 启动服务
python run.py
```

### 前端部署
```bash
# 安装依赖
cd frontend && npm install

# 构建生产版本
npm run build

# 启动开发服务器（开发环境）
npm run dev
```

## 📊 项目里程碑

| 里程碑 | 预计完成时间 | 关键交付物 |
|--------|------------|-----------|
| 数据库Schema完成 | Day 1 | 数据表创建、Mock数据 |
| 后端API完成 | Day 3 | 完整REST API、权限集成 |
| 前端基础功能完成 | Day 5 | 列表显示、筛选、状态管理 |
| 高级功能完成 | Day 6 | 自动刷新、统计、导出 |
| 测试和发布 | Day 7 | 功能验证、文档更新 |

---

**最后更新**: 2025-09-23
**当前负责人**: Claude Code Assistant
**项目状态**: 📋 **开发计划已完成，等待实施确认**