# FEAT-6-2-3 通道组功能开发计划

## 📋 项目概述

**功能名称**: 通道组管理功能
**需求编号**: FEAT-6-2-3
**优先级**: P1 - 高
**开发类型**: 新功能开发
**预估工期**: 2-3个工作日

**功能描述**: 开发完整的通道组查看功能，允许查看指定通道协议所属的通道组关系，包括通道组ID、名称、类型和策略等基本信息。

## 🎯 需求分析总结

### 功能需求
- **核心功能**: 查看当前通道协议所属的所有通道组列表信息
- **展示内容**: 序号、通道组ID、通道组名称、通道策略
- **界面要求**: 表格形式，清晰展示通道组归属关系
- **性能要求**: 查询响应时间 < 500ms

### UI/UX要求
- **页面标题**: "通道组列表"
- **布局方式**: 标准表格布局，600px宽度弹窗（如适用）
- **设计规范**: Ant Design组件库，蓝色主色调 #1890ff
- **交互设计**: 简洁界面，专注于信息展示

### 技术要求
- **前端**: React 18 + TypeScript + Ant Design 5.x
- **后端**: Flask 3.0 + PostgreSQL + SQLAlchemy
- **架构**: 三层分离（API + Service + Model）
- **数据权限**: 确保通道组信息的安全访问

## 🗃️ 数据库设计分析

### 现有表结构分析
通过分析现有数据库结构，发现：

1. **channels表**: 已存在，包含完整的通道信息
2. **channel_group_relations表**: 已存在，维护通道与通道组的多对多关系
3. **❌ 缺失**: `channel_groups`主表 - 需要新建

### 数据库设计方案

#### 阶段1: 创建通道组主表
```sql
-- channel_groups 表 - 通道组主表
CREATE TABLE IF NOT EXISTS channel_groups (
    -- Primary key
    group_id VARCHAR(255) PRIMARY KEY,
    unique_id UUID DEFAULT uuid_generate_v4(),

    -- Basic information
    group_name VARCHAR(255) NOT NULL,
    group_description TEXT,

    -- Strategy and routing
    routing_strategy VARCHAR(100) DEFAULT 'primary',  -- 'primary', 'combined', 'backup'
    load_balance_method VARCHAR(50) DEFAULT 'round_robin',  -- 'round_robin', 'weighted', 'least_connections'

    -- Configuration
    is_active BOOLEAN DEFAULT TRUE,
    max_channels INTEGER DEFAULT 10,
    failover_enabled BOOLEAN DEFAULT TRUE,

    -- Management
    admin_id INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### 阶段2: 索引和约束优化
```sql
-- Indexes for channel_groups
CREATE INDEX IF NOT EXISTS idx_channel_groups_group_name ON channel_groups(group_name);
CREATE INDEX IF NOT EXISTS idx_channel_groups_routing_strategy ON channel_groups(routing_strategy);
CREATE INDEX IF NOT EXISTS idx_channel_groups_is_active ON channel_groups(is_active);
CREATE INDEX IF NOT EXISTS idx_channel_groups_admin_id ON channel_groups(admin_id);

-- Comments
COMMENT ON COLUMN channel_groups.group_id IS 'Unique identifier for the channel group';
COMMENT ON COLUMN channel_groups.group_name IS 'Human-readable name for the channel group';
COMMENT ON COLUMN channel_groups.routing_strategy IS 'Routing strategy (primary, combined, backup)';
COMMENT ON COLUMN channel_groups.load_balance_method IS 'Load balancing method within group';
```

#### 阶段3: Mock数据准备
```sql
-- Insert sample channel groups
INSERT INTO channel_groups (group_id, group_name, group_description, routing_strategy, admin_id) VALUES
('group_asia_pacific', 'Asia Pacific Channel Group', 'Primary channel group for Asia Pacific region', 'primary', 1),
('group_europe', 'Europe Channel Group', 'Channel group for European markets', 'combined', 1),
('group_americas', 'Americas Channel Group', 'Channel group for North and South America', 'primary', 2),
('group_backup_global', 'Global Backup Group', 'Backup channels for global failover', 'backup', 1)
ON CONFLICT (group_id) DO NOTHING;
```

### 数据关系图
```
Channel (1) ←→ (N) ChannelGroupRelation (N) ←→ (1) ChannelGroup
```

## 🔧 后端开发计划

### 阶段1: 数据模型层开发

#### 1.1 创建ChannelGroup模型
**文件**: `app/models/customers/channel_group.py`
```python
class ChannelGroupStrategy(enum.Enum):
    PRIMARY = 'primary'
    COMBINED = 'combined'
    BACKUP = 'backup'

class ChannelGroup(db.Model, TimestampMixin):
    __tablename__ = 'channel_groups'

    group_id = db.Column(db.String(255), primary_key=True)
    group_name = db.Column(db.String(255), nullable=False)
    routing_strategy = db.Column(db.Enum(ChannelGroupStrategy), default=ChannelGroupStrategy.PRIMARY)
    # ... 其他字段
```

#### 1.2 扩展ChannelGroupRelation模型
**文件**: `app/models/customers/channel_group_relation.py`
```python
class ChannelGroupRelation(db.Model, TimestampMixin):
    __tablename__ = 'channel_group_relations'

    # 添加关联关系
    channel = db.relationship('Channel', backref='group_relations')
    channel_group = db.relationship('ChannelGroup', backref='channel_relations')
```

### 阶段2: 业务服务层开发

#### 2.1 创建ChannelGroupService
**文件**: `app/services/channels/channel_group_service.py`
```python
class ChannelGroupService:
    def get_channel_groups_by_channel_id(self, channel_id: str):
        """获取指定通道的所有通道组"""

    def get_channel_group_details(self, group_id: str):
        """获取通道组详细信息"""

    def get_channels_in_group(self, group_id: str):
        """获取通道组中的所有通道"""
```

### 阶段3: API层开发

#### 3.1 创建通道组API端点
**文件**: `app/api/v1/channels/route/channel_groups.py`
```python
class ChannelGroupListResource(Resource):
    @login_required
    def get(self, channel_id: str):
        """获取指定通道的通道组列表

        Query Parameters:
        - page: 页码 (默认1)
        - per_page: 每页数量 (默认20)
        - status: 筛选状态
        """
```

#### 3.2 API路由注册
**文件**: `app/api/v1/channels/routes.py`
```python
# 通道组相关路由
api.add_resource(ChannelGroupListResource,
    '/channels/<string:channel_id>/groups',
    endpoint='channel_groups')
```

### 阶段4: 数据序列化Schema

#### 4.1 ChannelGroup Schema
**文件**: `app/api/v1/channels/schema/channel_group.py`
```python
class ChannelGroupSchema(ma.Schema):
    group_id = ma.Str(required=True)
    group_name = ma.Str(required=True)
    routing_strategy = ma.Str()
    # ... 其他字段

class ChannelGroupListSchema(ma.Schema):
    data = ma.List(ma.Nested(ChannelGroupSchema))
    total = ma.Int()
    page = ma.Int()
    per_page = ma.Int()
```

## 🎨 前端开发计划

### 阶段1: API接口层开发

#### 1.1 扩展channelApi.ts
**文件**: `frontend/src/api/channelApi.ts`
```typescript
// 通道组相关接口类型定义
interface ChannelGroup {
  groupId: string;
  groupName: string;
  routingStrategy: 'primary' | 'combined' | 'backup';
  isActive: boolean;
  createTime: string;
  updateTime: string;
}

interface ChannelGroupListResponse {
  data: ChannelGroup[];
  total: number;
  success: boolean;
  message?: string;
}

// API方法
const channelApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getChannelGroups: builder.query<ChannelGroupListResponse, {
      channelId: string;
      page?: number;
      per_page?: number;
      status?: string;
    }>({
      query: ({ channelId, ...params }) => ({
        url: `/channels/${channelId}/groups`,
        params,
      }),
      providesTags: ['ChannelGroup'],
    }),
  }),
});
```

### 阶段2: 核心组件开发

#### 2.1 通道组列表页面
**文件**: `frontend/src/pages/ChannelManagement/components/ChannelGroupModal.tsx`
```typescript
interface ChannelGroupModalProps {
  visible: boolean;
  channelId: string;
  onClose: () => void;
}

const ChannelGroupModal: React.FC<ChannelGroupModalProps> = ({
  visible,
  channelId,
  onClose
}) => {
  // 600px宽度弹窗
  // 使用Ant Design Table展示通道组列表
  // 包含加载状态、空数据状态、错误处理
};
```

#### 2.2 通道组表格组件
**文件**: `frontend/src/pages/ChannelManagement/components/ChannelGroupTable.tsx`
```typescript
const ChannelGroupTable: React.FC<{
  channelId: string;
  loading?: boolean;
}> = ({ channelId, loading }) => {
  // 表格列定义
  const columns = [
    { title: '序号', width: 80, align: 'center' },
    { title: '通道组ID', width: 120, dataIndex: 'groupId' },
    { title: '通道组名称', width: 300, dataIndex: 'groupName' },
    { title: '通道策略', width: 150, dataIndex: 'routingStrategy' }
  ];

  // 策略标签渲染
  const renderStrategy = (strategy: string) => {
    const colorMap = {
      'primary': '#1890ff',
      'combined': '#52c41a',
      'backup': '#fa8c16'
    };
    return <Tag color={colorMap[strategy]}>{strategy}</Tag>;
  };
};
```

### 阶段3: 状态管理

#### 3.1 Redux Store集成
**文件**: `frontend/src/store/slices/channelSlice.ts`
```typescript
interface ChannelState {
  // ... 现有状态
  channelGroupModal: {
    visible: boolean;
    channelId: string | null;
  };
}

const channelSlice = createSlice({
  // ... 现有逻辑
  reducers: {
    showChannelGroupModal: (state, action) => {
      state.channelGroupModal.visible = true;
      state.channelGroupModal.channelId = action.payload;
    },
    hideChannelGroupModal: (state) => {
      state.channelGroupModal.visible = false;
      state.channelGroupModal.channelId = null;
    },
  },
});
```

### 阶段4: 主页面集成

#### 4.1 集成到通道列表页面
**文件**: `frontend/src/pages/ChannelManagement/ChannelListPage.tsx`
```typescript
// 在通道操作按钮中添加"查看通道组"按钮
const ChannelActionButtons = ({ record }) => {
  const dispatch = useAppDispatch();

  const handleViewGroups = () => {
    dispatch(showChannelGroupModal(record.channelId));
  };

  return (
    <Space>
      {/* 现有按钮 */}
      <Button
        type="link"
        icon={<TeamOutlined />}
        onClick={handleViewGroups}
      >
        通道组
      </Button>
    </Space>
  );
};
```

## 🧪 测试和验证计划

### 阶段1: 单元测试
- **模型测试**: ChannelGroup模型CRUD操作
- **服务测试**: ChannelGroupService业务逻辑
- **API测试**: 通道组查询API端点

### 阶段2: 集成测试
- **数据库集成**: 通道组关系查询正确性
- **API集成**: 前后端接口调用成功
- **UI集成**: 页面组件正确渲染

### 阶段3: 用户验收测试
- **功能验证**: 通道组列表正确显示
- **性能验证**: 查询响应时间 < 500ms
- **UI验证**: 界面符合设计规范

## 📁 文件结构规划

### 后端文件
```
app/
├── models/customers/
│   ├── channel_group.py              # 通道组模型 (新建)
│   └── channel_group_relation.py     # 通道组关系模型 (新建)
├── services/channels/
│   └── channel_group_service.py      # 通道组业务服务 (新建)
├── api/v1/channels/
│   ├── route/
│   │   └── channel_groups.py         # 通道组API端点 (新建)
│   └── schema/
│       └── channel_group.py          # 通道组序列化 (新建)
```

### 前端文件
```
frontend/src/
├── api/
│   └── channelApi.ts                 # 扩展通道组API (修改)
├── pages/ChannelManagement/
│   └── components/
│       ├── ChannelGroupModal.tsx     # 通道组弹窗 (新建)
│       └── ChannelGroupTable.tsx     # 通道组表格 (新建)
├── store/slices/
│   └── channelSlice.ts              # 扩展状态管理 (修改)
└── types/
    └── channel.ts                   # 扩展类型定义 (修改)
```

### 数据库文件
```
pigeon_web/sql/
├── modules/
│   └── channels.sql                 # 扩展通道组表 (修改)
└── init_mock_data.sql              # 添加测试数据 (修改)
```

## ⏱️ 开发时间计划

### Day 1: 数据库和后端开发
- **上午 (2-3小时)**:
  - 设计和创建channel_groups表
  - 创建ChannelGroup和ChannelGroupRelation模型
  - 添加Mock测试数据

- **下午 (3-4小时)**:
  - 开发ChannelGroupService业务逻辑
  - 创建通道组API端点
  - 编写数据序列化Schema

### Day 2: 前端开发
- **上午 (2-3小时)**:
  - 扩展channelApi.ts接口定义
  - 开发ChannelGroupTable核心表格组件
  - 实现加载状态和空数据处理

- **下午 (3-4小时)**:
  - 开发ChannelGroupModal弹窗组件
  - 集成Redux状态管理
  - 集成到主通道列表页面

### Day 3: 测试和优化
- **上午 (2小时)**:
  - 前后端联调测试
  - 修复集成问题
  - 性能测试和优化

- **下午 (2-3小时)**:
  - 用户界面测试
  - 样式和交互优化
  - 文档更新和代码提交

## 🎯 验收标准

### 功能验收
- ✅ 通道组列表正确显示所有相关通道组
- ✅ 表格包含序号、通道组ID、名称、策略四列
- ✅ 支持通道组数据的完整展示
- ✅ 关闭功能正常工作

### 性能验收
- ✅ 通道组查询响应时间 < 500ms
- ✅ 页面加载流畅，无明显卡顿
- ✅ 大数据量时的渲染性能良好

### UI/UX验收
- ✅ 界面设计符合Ant Design规范
- ✅ 表格布局清晰，信息易读
- ✅ 加载状态和空数据状态正确显示
- ✅ 错误处理和用户反馈完善

### 技术验收
- ✅ 代码质量符合项目规范
- ✅ TypeScript类型定义完整
- ✅ API接口设计RESTful
- ✅ 数据库查询效率优化

## 🔗 依赖关系

### 前置依赖
- ✅ 现有通道管理系统正常运行
- ✅ channels表和channel_group_relations表存在
- ✅ 用户认证和权限系统可用

### 并行开发
- 可与其他FEAT-6-2-X功能并行开发
- 不影响现有通道管理功能

### 后续扩展
- 为FEAT-6-2-4到FEAT-6-2-8功能提供基础
- 支持未来通道组管理功能扩展

## 📝 风险评估

### 技术风险
- **低风险**: 基于现有成熟架构开发
- **缓解措施**: 复用现有通道管理代码模式

### 时间风险
- **中等风险**: 需要创建新的数据表和关系
- **缓解措施**: 预留1天缓冲时间

### 兼容性风险
- **低风险**: 纯新增功能，不影响现有系统
- **缓解措施**: 充分的向后兼容测试

## 📄 文档交付

1. **技术文档**: 数据库Schema设计文档
2. **API文档**: 通道组查询接口规范
3. **用户文档**: 通道组功能使用说明
4. **测试报告**: 功能测试和性能测试结果

---

**创建时间**: 2025-09-17
**负责人**: Claude Code Assistant
**状态**: 待开发
**优先级**: P1 - 高优先级