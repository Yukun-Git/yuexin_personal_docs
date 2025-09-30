# FEAT-4-1 发件箱功能开发详细工作计划

## 项目概述

基于需求文档的全面分析和重新设计的数据库架构，开发发件箱管理系统。核心包括：多维度查询、拆分短信统一管理、统一时间线展示、灵活导出和回执重推等功能。

## 架构设计更新记录

**📅 2025-09-30 设计评审结果**：

经过深入分析现有数据库架构和业务需求，以及MVP原则重新评估，对原计划进行了重大简化：

1. **数据库设计大幅简化**：
   - ❌ 取消新建 `mgmt.receipt_resend_log` 表
   - ❌ 取消新建 `mgmt.outbox_query_configs` 表
   - ✅ **完全不需要新建任何表**

2. **技术决策依据**：
   - **回执重推**：现有 `sms.delivers` 表已包含核心信息（status、send_count、sent_time）
   - **查询配置**：需求不强烈，属于过度设计，可用浏览器localStorage替代

3. **功能影响评估**：
   - 回执重推：可实现95%功能，只缺少详细历史记录
   - 查询配置：完全移除，不影响核心业务价值

4. **方案优势**：
   - 架构极度简化，开发成本大幅降低
   - 维护复杂度最小化
   - 专注核心功能，快速交付价值

这一调整体现了"极简MVP"的设计理念，是最具性价比的技术方案。

**重要决定记录**：
- **暂时不考虑任何和补发相关的逻辑** - 包括补发记录、补发链追踪、补发状态标识等所有补发功能暂时不实现
- **完全不新建任何表** - 基于现有表结构实现所有核心功能
- **移除查询配置保存功能** - 避免过度设计，可用localStorage替代
- 专注于核心的查询、展示、拆分短信管理和导出功能

## 技术复杂度评估

### 高复杂度功能模块
1. **拆分短信统一管理** - 需要处理父子关系、状态聚合、独立追踪
2. **统一时间线展示** - 多消息状态变更的时间排序和展示
3. **导出功能双模式** - 拼接模式vs拆分模式的不同处理逻辑
4. **复杂权限控制** - 数据权限、功能权限、字段权限的多层控制

### 中等复杂度功能模块
1. **多维度查询** - 复杂条件组合、性能优化
2. **回执重推功能** - 状态验证、重推逻辑、日志记录
3. **视觉标识系统** - 按UI/UX规范实现状态标识

## 详细开发计划

### 第一阶段：数据库初始化脚本修改

#### 1.1 数据库Schema设计实施
**🎯 最终数据库设计决定：零修改方案**

经过深入分析，**完全不需要修改任何数据库表结构**！

**1. 不新建任何表**：
- ❌ 取消 `mgmt.receipt_resend_log` 表
- ❌ 取消 `mgmt.outbox_query_configs` 表

**2. 不新增任何字段**：
- ❌ 取消 `outbox_display_status` - 可基于现有 status 推导
- ❌ 取消 `is_visible_in_outbox` - 可使用现有 enabled 字段
- ❌ 取消 `client_receipt_status` - 与 sms.delivers.status 重复
- ❌ 取消 `last_receipt_push_time` - 与 sms.delivers.sent_time 重复

**3. 实现方案**：
- **回执重推**：基于 sms.delivers 表现有字段（status、send_count、sent_time）
- **查询配置**：前端 localStorage 简单存储
- **展示控制**：基于现有业务字段推导

**4. 架构优势**：
- ✅ 零数据库变更，无部署风险
- ✅ 极简架构，维护成本最低
- ✅ 开发周期大幅缩短
- ✅ 95%以上功能完整度


#### 1.2 第一阶段总结

由于采用"零数据库修改"方案，第一阶段的工作大幅简化：

**✅ 第一阶段完成项**：
- 数据库架构分析和设计决策
- 确定基于现有表的实现方案
- 明确技术路线和架构优势

**❌ 第一阶段移除项**：
- 数据库表创建脚本
- 字段新增脚本
- Mock数据脚本开发
- 数据库初始化脚本验证

**⏭️ 直接进入第二阶段**：核心服务层开发

## 📋 服务端代码设计调整总结

基于"零数据库修改"的架构决定，对服务端代码设计进行了以下调整：

### ✅ 已调整项目

1. **数据模型层调整**：
   - ❌ 移除：`SMSStatusTimeline` 新建模型类
   - ❌ 移除：`ReceiptResendLog` 新建模型类
   - ❌ 移除：`OutboxQueryConfig` 新建模型类
   - ✅ 调整：基于现有 `ShortMessage` 和 `Deliver` 模型扩展方法

2. **服务层调整**：
   - ✅ 调整：`TimelineService` 基于现有表数据构建时间线
   - ✅ 保持：`SplitMessageService` 基于现有拆分字段实现
   - ✅ 调整：`ReceiptResendService` 基于 `delivers` 表实现
   - ✅ 保持：`ExportService` 和 `QueryBuilder` 无需调整

3. **前端设计调整**：
   - ❌ 移除：`savedQueries` 状态管理
   - ❌ 移除：`SavedQueryPanel` 组件
   - ✅ 新增：`QueryStorageUtil` localStorage工具类
   - ✅ 调整：`QuickQueryPanel` 组件基于localStorage

4. **交付物调整**：
   - ❌ 移除：数据库脚本相关交付物
   - ✅ 保持：其他代码交付物不变

### 🎯 架构优势确认

通过这些调整，确保了：
- **零学习成本** - 开发人员无需学习新表结构
- **零维护成本** - 无新增数据库对象需要维护
- **零部署风险** - 完全基于现有架构
- **95%功能实现** - 核心业务需求全部满足

### 第二阶段：核心服务层开发（原第二阶段，现为主要开发阶段）

#### 2.1 数据模型层实现
**文件位置**：`pigeon_web/app/models/messages/`

**2.1.1 扩展短信模型**
```python
# message.py - 扩展现有模型
class ShortMessage(BaseModel):
    # 新增关联关系方法
    def get_split_children(self) -> List['ShortMessage']
    def get_parent_message(self) -> Optional['ShortMessage']
    def get_root_message(self) -> 'ShortMessage'

    # 状态聚合方法
    def get_aggregated_status(self) -> dict
    def is_split_message(self) -> bool

    # 业务判断方法
    def can_resend_receipt(self) -> bool
```

**2.1.2 扩展现有模型类**
```python
# message.py - 在现有ShortMessage模型中新增方法
class ShortMessage(BaseModel):
    # 新增发件箱相关业务方法
    def get_outbox_display_info(self) -> dict
    def get_client_receipt_info(self) -> dict
    def format_for_outbox_timeline(self) -> dict

# deliver.py - 在现有Deliver模型中新增方法
class Deliver(BaseModel):
    # 新增回执重推相关方法
    def can_resend(self) -> bool
    def get_resend_summary(self) -> dict
    def format_push_info(self) -> dict

# 注：不再创建新的模型类，基于现有表扩展功能
```

#### 2.2 复杂业务服务实现
**文件位置**：`pigeon_web/app/services/sms/outbox/`

**2.2.1 拆分短信管理服务**
```python
# split_message_service.py
class SplitMessageService:
    def aggregate_split_status(self, parent_id: str) -> dict
    def get_unified_timeline(self, root_id: str) -> List[dict]
    def merge_split_content(self, parent_id: str) -> str
    def get_split_display_data(self, parent_id: str) -> dict
```

**2.2.2 时间线服务**
```python
# timeline_service.py
class TimelineService:
    def build_unified_timeline(self, root_id: str) -> List[dict]
    def build_timeline_from_existing_data(self, message_id: str) -> List[dict]  # 基于现有表数据
    def calculate_duration_stats(self, timeline: List[dict]) -> dict
    def format_timeline_for_display(self, timeline: List[dict]) -> List[dict]
    def merge_message_and_deliver_timeline(self, message: ShortMessage, deliver: Deliver) -> List[dict]  # 合并两表数据
```

#### 2.3 高性能查询构建器
**文件位置**：`pigeon_web/app/services/sms/query_builder/`

```python
# outbox_query_builder.py
class OutboxQueryBuilder:
    def build_base_query(self) -> Query
    def apply_permission_filters(self, query: Query, user: AdminUser) -> Query
    def apply_search_conditions(self, query: Query, conditions: dict) -> Query
    def apply_split_message_grouping(self, query: Query, mode: str) -> Query
    def optimize_for_large_dataset(self, query: Query) -> Query

    def build_export_query(self, conditions: dict, export_mode: str) -> Query
    def build_statistics_query(self, conditions: dict) -> Query
```

#### 2.4 导出服务实现
**文件位置**：`pigeon_web/app/services/sms/export/`

```python
# export_service.py
class OutboxExportService:
    def export_with_merge_mode(self, query_params: dict, user: AdminUser) -> Tuple[str, bytes]
    def export_with_split_mode(self, query_params: dict, user: AdminUser) -> Tuple[str, bytes]
    def validate_export_permissions(self, user: AdminUser, field_list: List[str]) -> bool
    def generate_excel_file(self, data: List[dict], mode: str) -> bytes
    def handle_large_dataset_export(self, query_params: dict) -> str  # 返回任务ID
```

#### 2.5 回执重推服务
```python
# receipt_service.py
class ReceiptResendService:
    def can_resend_receipt(self, message_id: str) -> Tuple[bool, str]
    def execute_receipt_resend(self, message_id: str, operator: AdminUser) -> bool
    def get_resend_status(self, message_id: str) -> dict
    def update_resend_count(self, message_id: str) -> bool
    def get_push_summary(self, message_id: str) -> dict  # 基于delivers表的推送摘要
```

### 第三阶段：API接口层开发

#### 3.1 核心API实现
**文件位置**：`pigeon_web/app/api/v1/sms/route/outbox_v2.py`

```python
class OutboxListResourceV2(Resource):
    @jwt_required()
    @permission_required('sms_outbox_view')
    def get(self):
        """发件箱列表 - 支持拆分短信聚合显示"""

class OutboxDetailResourceV2(Resource):
    @jwt_required()
    def get(self, message_id):
        """发件箱详情 - 包含完整时间线、拆分短信"""

class OutboxExportResourceV2(Resource):
    @jwt_required()
    @permission_required('sms_outbox_export')
    def post(self):
        """异步导出 - 支持拼接/拆分双模式"""

class OutboxResendReceiptResource(Resource):
    @jwt_required()
    @permission_required('sms_receipt_resend')
    def post(self, message_id):
        """回执重推功能"""
```

#### 3.2 查询参数验证增强
**文件位置**：`pigeon_web/app/api/v1/sms/schema/outbox_v2_schema.py`

```python
class OutboxQuerySchemaV2(Schema):
    # 基础查询条件
    account_ids = fields.List(fields.Str(), missing=[])
    status_codes = fields.List(fields.Str(), missing=[])
    phone_number = fields.Str(validate=Length(max=20))
    content_keyword = fields.Str(validate=Length(max=100))

    # 时间范围（最大3个月限制）
    start_time = fields.DateTime(required=True)
    end_time = fields.DateTime(required=True)

    # 扩展筛选条件
    channel_ids = fields.List(fields.Str(), missing=[])
    country_codes = fields.List(fields.Str(), missing=[])
    sender_ids = fields.List(fields.Str(), missing=[])

    # 拆分短信处理模式
    split_display_mode = fields.Str(validate=OneOf(['merged', 'individual']), missing='merged')

    # 排序和分页
    sort_fields = fields.List(fields.Str(), missing=['send_time'])
    sort_orders = fields.List(fields.Str(validate=OneOf(['asc', 'desc'])), missing=['desc'])
    page = fields.Int(validate=Range(min=1), missing=1)
    per_page = fields.Int(validate=Range(min=1, max=1000), missing=20)

class OutboxExportSchemaV2(Schema):
    export_mode = fields.Str(validate=OneOf(['merge', 'split']), required=True)
    include_fields = fields.List(fields.Str(), missing='all')
    file_prefix = fields.Str(validate=Length(max=50))
    max_records = fields.Int(validate=Range(max=100000), missing=10000)
```

### 第四阶段：前端实现

#### 4.1 状态管理设计
**文件位置**：`pigeon_web/frontend/src/store/sms/outboxStore.ts`

```typescript
interface OutboxState {
  // 基础数据
  records: OutboxRecord[];
  totalCount: number;
  loading: boolean;

  // 查询相关
  queryParams: OutboxQueryParams;
  quickFilters: QuickFilter[];
  // 注：查询配置改为前端localStorage存储，不再需要savedQueries状态

  // 详情相关
  detailModalVisible: boolean;
  currentDetail: OutboxDetail | null;
  timelineData: TimelineEvent[];
  splitMessages: SplitMessage[];

  // 导出相关
  exportModalVisible: boolean;
  exportProgress: number;
  exportLoading: boolean;

  // 选择相关
  selectedRecords: string[];
  selectedMode: 'single' | 'batch';
}

interface OutboxRecord {
  messageId: string;
  messageType: 'original' | 'split';
  parentMessageId?: string;
  rootMessageId?: string;

  // 基础信息
  accountId: string;
  accountName: string;
  phoneNumber: string;
  content: string;
  status: string;
  sendTime: string;

  // 拆分短信信息
  isSplitMessage: boolean;
  splitInfo?: {
    totalSegments: number;
    segmentSequence: number;
    aggregatedStatus: string;
    statusSummary: {
      success: number;
      failed: number;
      pending: number;
    };
  };

  // 状态标识
  statusIndicator: {
    type: 'success' | 'failed' | 'processing';
    icon: string;
    color: string;
    description: string;
  };

  // 操作权限
  canResendReceipt: boolean;
  canViewDetail: boolean;
}
```

#### 4.2 核心组件开发
**文件位置**：`pigeon_web/frontend/src/pages/sms/outbox/`

**4.2.1 主页面重构**
```typescript
// OutboxPageV2.tsx
export const OutboxPageV2: React.FC = () => {
  return (
    <PageContainer>
      <PageHeader title="发件箱" />
      <QuerySection />
      <QuickFilterBar />
      <ResultSection />
      <DetailModal />
      <ExportModal />
    </PageContainer>
  );
};
```

**4.2.2 复杂查询组件**
```typescript
// components/QuerySection.tsx
export const QuerySection: React.FC = () => {
  return (
    <Card className="query-section">
      <Form layout="vertical">
        <Row gutter={16}>
          <Col span={6}><AccountMultiSelect /></Col>
          <Col span={6}><StatusMultiSelect /></Col>
          <Col span={6}><ChannelMultiSelect /></Col>
          <Col span={6}><CountryMultiSelect /></Col>
        </Row>
        <Row gutter={16}>
          <Col span={6}><SenderMultiSelect /></Col>
          <Col span={12}><DateRangePicker maxRange={90} /></Col>
          <Col span={6}><SplitDisplayModeSelect /></Col>
        </Row>
        <Row gutter={16}>
          <Col span={8}><PhoneInput placeholder="手机号码" /></Col>
          <Col span={8}><ContentInput placeholder="短信内容关键词" /></Col>
          <Col span={8}><QueryActions /></Col>
        </Row>
      </Form>
      <QuickQueryPanel />  {/* 使用localStorage实现的简单查询保存 */}
    </Card>
  );
};
```

**4.2.3 查询配置localStorage实现**
```typescript
// utils/queryStorage.ts - 查询配置本地存储工具
export class QueryStorageUtil {
  private static readonly STORAGE_KEY = 'outbox_query_configs';
  private static readonly MAX_SAVED_QUERIES = 10;

  // 保存查询条件
  static saveQuery(name: string, queryParams: OutboxQueryParams): void {
    const savedQueries = this.getSavedQueries();
    const newQuery = {
      id: Date.now().toString(),
      name,
      queryParams,
      savedAt: new Date().toISOString(),
      useCount: 0
    };

    savedQueries.unshift(newQuery);
    if (savedQueries.length > this.MAX_SAVED_QUERIES) {
      savedQueries.pop();
    }

    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(savedQueries));
  }

  // 获取保存的查询
  static getSavedQueries(): SavedQueryLocal[] {
    const stored = localStorage.getItem(this.STORAGE_KEY);
    return stored ? JSON.parse(stored) : [];
  }

  // 加载查询条件
  static loadQuery(queryId: string): OutboxQueryParams | null {
    const queries = this.getSavedQueries();
    const query = queries.find(q => q.id === queryId);
    if (query) {
      query.useCount++;
      localStorage.setItem(this.STORAGE_KEY, JSON.stringify(queries));
      return query.queryParams;
    }
    return null;
  }

  // 删除查询配置
  static deleteQuery(queryId: string): void {
    const queries = this.getSavedQueries().filter(q => q.id !== queryId);
    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(queries));
  }
}

interface SavedQueryLocal {
  id: string;
  name: string;
  queryParams: OutboxQueryParams;
  savedAt: string;
  useCount: number;
}
```

**4.2.4 记录卡片组件**
```typescript
// components/RecordCard.tsx
export const RecordCard: React.FC<{record: OutboxRecord}> = ({record}) => {
  return (
    <div className={`record-card ${getCardClassName(record)}`}>
      <RecordHeader record={record} />
      <ContentRow content={record.content} isSplit={record.isSplitMessage} />
      <DetailRow record={record} />
      <SplitMessageSection record={record} />
      <ActionsRow record={record} />
    </div>
  );
};

// 组件子结构
const RecordHeader: React.FC = ({record}) => (
  <div className="record-header">
    <SelectCheckbox />
    <StatusIndicator status={record.statusIndicator} />
    <AccountInfo account={record.accountName} />
    <PhoneInfo phone={record.phoneNumber} />
    <SendTimeInfo time={record.sendTime} />
    <CountryInfo country={record.country} />
  </div>
);

const SplitMessageSection: React.FC = ({record}) => {
  if (!record.isSplitMessage) return null;

  return (
    <div className="split-message-section">
      <SplitStatusSummary summary={record.splitInfo.statusSummary} />
      <SplitMessageIndicator
        sequence={record.splitInfo.segmentSequence}
        total={record.splitInfo.totalSegments}
      />
    </div>
  );
};
```

**4.2.4 详情弹窗组件**
```typescript
// components/DetailModal.tsx
export const DetailModal: React.FC = () => {
  return (
    <Modal
      title="短信详情"
      width={1200}
      className="outbox-detail-modal"
    >
      <Tabs defaultActiveKey="basic">
        <TabPane tab="基础信息" key="basic">
          <BasicInfoSection />
        </TabPane>
        <TabPane tab="拆分短信" key="split">
          <SplitMessagesSection />
        </TabPane>
        <TabPane tab="统一时间线" key="timeline">
          <UnifiedTimelineSection />
        </TabPane>
        <TabPane tab="计费信息" key="billing">
          <BillingInfoSection />
        </TabPane>
      </Tabs>
      <ModalActions />
    </Modal>
  );
};

// 统一时间线组件
const UnifiedTimelineSection: React.FC = () => (
  <div className="unified-timeline">
    <TimelineDescription />
    <Timeline mode="left">
      {timelineEvents.map(event => (
        <Timeline.Item
          key={event.id}
          dot={<TimelineIcon status={event.status} />}
          label={event.timestamp}
        >
          <TimelineContent event={event} />
          <SplitMessageIndicator messageId={event.messageId} />
        </Timeline.Item>
      ))}
    </Timeline>
  </div>
);
```

**4.2.5 导出功能组件**
```typescript
// components/ExportModal.tsx
export const ExportModal: React.FC = () => {
  return (
    <Modal title="导出数据" className="export-modal">
      <ExportModeSection />
      <FieldSelectionSection />
      <ExportInfoSection />
      <FileNamingSection />
      <ExportProgress />
    </Modal>
  );
};

const ExportModeSection: React.FC = () => (
  <Card title="导出模式" className="export-mode-section">
    <Radio.Group defaultValue="merge">
      <Radio value="merge">
        <div className="mode-option">
          <div className="mode-title">拼接模式</div>
          <div className="mode-description">
            拆分短信合并为一条记录，状态以最终状态为准
          </div>
        </div>
      </Radio>
      <Radio value="split">
        <div className="mode-option">
          <div className="mode-title">拆分模式</div>
          <div className="mode-description">
            每条拆分短信独立显示，保持原始发送记录
          </div>
        </div>
      </Radio>
    </Radio.Group>
  </Card>
);
```

#### 4.3 工具组件库
**文件位置**：`pigeon_web/frontend/src/components/sms/outbox/`

```typescript
// StatusIndicator.tsx - 状态指示器组件
export const StatusIndicator: React.FC<{status: StatusInfo}> = ({status}) => (
  <span className={`status-indicator status-${status.type}`}>
    <Icon type={status.icon} style={{color: status.color}} />
    <span className="status-text">{status.description}</span>
  </span>
);

// TimelineViewer.tsx - 时间线查看器
export const TimelineViewer: React.FC<{events: TimelineEvent[]}> = ({events}) => (
  <div className="timeline-viewer">
    {events.map(event => (
      <TimelineItem key={event.id} event={event} />
    ))}
  </div>
);

// SplitMessageViewer.tsx - 拆分短信查看器
export const SplitMessageViewer: React.FC<{messages: SplitMessage[]}> = ({messages}) => (
  <div className="split-message-viewer">
    <SplitSummary total={messages.length} />
    <SplitMessageList messages={messages} />
  </div>
);
```

### 第五阶段：权限与安全集成

#### 5.1 权限系统集成
**文件位置**：`pigeon_web/app/services/auth/outbox_permissions.py`

```python
class OutboxPermissionService:
    def get_user_accessible_accounts(self, user: AdminUser) -> List[str]
    def can_view_outbox(self, user: AdminUser) -> bool
    def can_export_outbox(self, user: AdminUser, field_list: List[str]) -> bool
    def can_resend_receipt(self, user: AdminUser, message: ShortMessage) -> bool
    def filter_sensitive_fields(self, data: dict, user: AdminUser) -> dict
```

#### 5.2 数据权限过滤
- 基于用户角色的发送账号权限过滤
- 企业级数据隔离
- 敏感字段的脱敏处理

#### 5.3 操作审计日志
- 所有查询操作的日志记录
- 导出操作的详细审计
- 回执重推的操作记录

### 第六阶段：性能优化与测试

#### 6.1 数据库性能优化
```sql
-- 复合索引优化
CREATE INDEX idx_outbox_composite_query ON sms.short_messages
(account_id, outbox_status, send_time DESC)
WHERE is_visible_in_outbox = true;

-- 分区表设计（按月分区）
CREATE TABLE sms.short_messages_y2025m01 PARTITION OF sms.short_messages
FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

#### 6.2 应用层性能优化
- 查询结果缓存（Redis）
- 分页查询优化
- 导出功能的异步处理和进度跟踪
- 前端列表虚拟化

#### 6.3 全面测试
**测试用例设计**：
- 单条短信的完整流程测试
- 拆分短信的各种组合测试（2-10条拆分）
- 大数据量性能测试（100万条记录）
- 并发操作测试
- 权限边界测试

### 第七阶段：部署准备与文档

#### 7.1 部署配置
- 数据库迁移脚本的生产环境验证
- 配置文件更新
- 权限初始化脚本

#### 7.2 文档编写
- API文档更新
- 用户操作手册
- 运维部署指南
- 故障排查手册

## 开发阶段概览

| 阶段 | 主要任务 | 主要风险 | 风险控制措施 |
|------|----------|----------|-------------|
| 第一阶段 | 架构设计与技术决策 | 过度设计 | ✅ 已完成，采用极简MVP方案 |
| 第二阶段 | 核心服务层开发 | 业务逻辑复杂 | 分模块开发、单元测试 |
| 第三阶段 | API接口层开发 | 性能问题 | 查询优化、缓存策略 |
| 第四阶段 | 前端实现 | UI复杂度高 | 组件化设计、逐步集成 |
| 第五阶段 | 权限与安全集成 | 权限遗漏 | 权限矩阵验证 |
| 第六阶段 | 性能优化与测试 | 性能不达标 | 提前性能测试 |
| 第七阶段 | 部署准备与文档 | 部署风险 | 零数据库变更，风险最小 |

## 关键里程碑

1. **极简架构设计完成** ✅ 已完成
2. **核心服务开发完成**
3. **API接口联调完成**
4. **前端基础功能完成**
5. **完整功能集成测试**
6. **性能优化完成**
7. **生产环境部署**（零数据库变更）

## 验收标准

### 功能验收
- **查询功能**：支持8种查询条件的任意组合，响应时间<3秒
- **拆分短信**：正确展示拆分关系，状态聚合准确率100%
- **时间线功能**：统一展示所有状态变更，时间排序准确
- **导出功能**：支持双模式导出，10万条记录<5分钟
- **重推功能**：成功率>99%，操作日志完整

### 性能验收
- **查询性能**：普通查询<2秒，复杂查询<5秒，分页查询<1秒
- **展示性能**：列表加载<1秒，详情展示<500ms
- **导出性能**：1万条<30秒，10万条<5分钟，进度实时更新

### 安全验收
- **权限控制**：数据权限准确率100%，无越权访问
- **操作审计**：所有操作完整记录，日志格式规范
- **数据安全**：敏感信息正确脱敏，传输加密

## 风险控制措施

### 技术风险
1. **数据库性能风险**
   - 提前进行大数据量测试
   - 准备查询优化方案
   - 考虑分库分表策略

2. **复杂业务逻辑风险**
   - 详细的单元测试覆盖
   - 端到端测试验证
   - 代码审查机制

3. **前端性能风险**
   - 虚拟列表技术
   - 懒加载策略
   - 组件优化

### 项目风险
1. **开发风险**
   - 关键功能优先开发
   - 并行开发策略
   - 定期进度评审

2. **质量风险**
   - 代码审查流程
   - 持续集成测试
   - 用户验收测试

## 交付物清单

### 代码交付物
1. **后端代码**：模型扩展、服务层、API接口、测试代码
2. **前端代码**：页面、组件、状态管理、测试代码
3. **配置文件**：权限配置、系统配置、部署配置
4. **注**: 零数据库变更，无需数据库脚本交付物

### 文档交付物
1. **技术文档**：API文档、数据库设计文档、架构设计文档
2. **用户文档**：操作手册、功能说明、FAQ
3. **运维文档**：部署指南、监控配置、故障处理手册

### 测试交付物
1. **测试用例**：功能测试用例、性能测试用例、安全测试用例
2. **测试报告**：测试执行报告、性能测试报告、安全测试报告
3. **测试数据**：测试数据集、Mock数据、压力测试数据

## 总结

本工作计划基于需求文档制定，重点实现发件箱的核心功能：多维度查询、拆分短信统一管理、统一时间线展示、灵活导出和回执重推。

**🎯 最终架构决定**：
- **暂时不实现任何补发相关功能** - 专注核心查询和展示能力
- **完全不新建任何数据库表** - 基于现有表结构实现所有功能
- **回执重推基于现有表** - 利用 sms.delivers 的 status、send_count、sent_time 字段
- **查询配置用localStorage** - 前端简单存储，避免后端复杂度
- **极简MVP架构** - 零数据库变更，最小化开发和维护成本

**价值评估**：
- ✅ 功能完整度：95%以上的需求可以实现
- ✅ 开发效率：大幅提升，周期缩短
- ✅ 维护成本：最低化，架构简洁
- ✅ 部署风险：零数据库变更，风险最小

这是一个真正的"极简MVP"方案，体现了软件工程中"做正确的事比正确地做事更重要"的理念。