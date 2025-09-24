# FEAT-2-2 国际客户账单管理功能开发计划

## 📋 项目概述

**功能名称**: 国际客户账单管理
**需求ID**: FEAT-2-2
**开发目标**: 为平台管理员提供多维度的国际客户消费账单查询、统计和管理功能
**优先级**: P0
**计划开发时间**: 5-7个工作日

## 🎯 功能需求总结

基于需求文档分析，核心功能包括：
- **多维度筛选**: 管理员、企业账号、发送账号、国家地区、付费类型等
- **时间聚合**: 合计、按天、按月三种聚合方式
- **账单列表**: 完整的账单信息展示和排序
- **数据汇总**: 实时统计汇总信息
- **数据导出**: Excel格式导出功能
- **分页展示**: 支持大数据量的分页处理

## 🏗️ 现有架构分析

### 后端架构特点
- **框架**: Flask 3.0 + SQLAlchemy + Marshmallow + PostgreSQL
- **架构模式**: 三层架构 (API层 + Service层 + Model层)
- **基础服务**: BaseService提供通用CRUD操作
- **路由管理**: Blueprint + Flask-RESTful
- **数据验证**: Marshmallow Schema验证和序列化
- **权限控制**: 基于装饰器的RBAC权限系统

### 前端架构特点
- **框架**: React 18 + TypeScript + Vite
- **UI组件**: Ant Design 5.x
- **状态管理**: Redux Toolkit + RTK Query
- **路由**: React Router v6
- **样式**: CSS Modules + Ant Design主题
- **代码规范**: ESLint + Prettier + 文件头注释

### 现有相似功能参考
- **企业管理**: 完整的CRUD + 搜索筛选 + 分页
- **通道管理**: 复杂的多维度筛选 + 操作按钮
- **账号管理**: 表格展示 + 模态框编辑
- **角色管理**: 权限树 + 批量操作

## 📊 技术实现架构设计

### 数据库设计
基于现有数据库分析，账单数据来源可能涉及：
- `sms_test_records` - SMS测试记录
- `enterprise` - 企业信息
- `accounts` - 发送账号信息
- `admin_users` - 管理员信息
- `country_regions` - 国家地区信息

**建议创建视图或查询聚合表**:
```sql
-- 账单查询视图(建议)
CREATE VIEW v_customer_bills AS
SELECT
    sr.id,
    sr.account_id as send_account,
    acc.account_name,
    ent.name as enterprise_name,
    au.username as admin_name,
    cr.name as country_region,
    sr.start_time,
    sr.end_time,
    sr.billing_method,
    sr.payment_method,
    sr.bill_count,
    sr.account_price,
    sr.account_fee,
    sr.created_at,
    sr.updated_at
FROM sms_test_records sr
JOIN accounts acc ON sr.account_id = acc.id
JOIN enterprise ent ON acc.enterprise_id = ent.id
JOIN admin_users au ON ent.admin_id = au.id
JOIN country_regions cr ON sr.country_id = cr.id;
```

### 后端API设计

#### 1. 数据模型层 (Model)
```python
# app/models/billing/customer_bill.py
class CustomerBillView(db.Model):
    """客户账单视图模型"""
    __tablename__ = 'v_customer_bills'

    id = db.Column(db.String(36), primary_key=True)
    send_account = db.Column(db.String(100))
    account_name = db.Column(db.String(255))
    enterprise_name = db.Column(db.String(255))
    admin_name = db.Column(db.String(100))
    country_region = db.Column(db.String(100))
    start_time = db.Column(db.DateTime)
    end_time = db.Column(db.DateTime)
    billing_method = db.Column(db.String(50))
    payment_method = db.Column(db.String(50))
    bill_count = db.Column(db.Integer)
    account_price = db.Column(db.Numeric(10, 5))
    account_fee = db.Column(db.Numeric(12, 2))
    created_at = db.Column(db.DateTime)
    updated_at = db.Column(db.DateTime)
```

#### 2. 服务层 (Service)
```python
# app/services/billing/customer_bill_service.py
class CustomerBillService(BaseService):
    """客户账单服务"""

    def search_bills(self, params):
        """多维度搜索账单"""

    def get_bill_statistics(self, params):
        """获取账单统计汇总"""

    def export_bills(self, params, format='excel'):
        """导出账单数据"""

    def aggregate_by_time(self, params, aggregation_type):
        """按时间聚合账单数据"""
```

#### 3. API层 (API)
```python
# app/api/v1/billing/customer_bills.py
class CustomerBillListResource(Resource):
    """客户账单列表API"""

    @permission_required('customer_bill_read')
    def get(self):
        """查询账单列表"""

    @permission_required('customer_bill_export')
    def post(self):
        """导出账单数据"""

class CustomerBillStatisticsResource(Resource):
    """账单统计API"""

    @permission_required('customer_bill_read')
    def get(self):
        """获取统计数据"""
```

#### 4. Schema验证
```python
# app/api/v1/billing/schema/customer_bill.py
class CustomerBillQuerySchema(Schema):
    """账单查询参数验证"""

    # 分页参数
    page = fields.Int(validate=validate.Range(min=1), missing=1)
    per_page = fields.Int(validate=validate.Range(min=1, max=100), missing=20)

    # 筛选参数
    admin_id = fields.Int()
    enterprise_id = fields.Str()
    send_account_id = fields.Str()
    country_region = fields.Str()
    payment_type = fields.Str()

    # 时间范围
    start_date = fields.DateTime()
    end_date = fields.DateTime()

    # 聚合方式
    aggregation_type = fields.Str(validate=validate.OneOf(['total', 'daily', 'monthly']))

    # 排序
    order_by = fields.Str()
    order_dir = fields.Str(validate=validate.OneOf(['asc', 'desc']))
```

### 前端实现设计

#### 1. API接口层
```typescript
// frontend/src/api/customerBillApi.ts
export interface CustomerBillParams {
  page?: number;
  per_page?: number;
  admin_id?: number;
  enterprise_id?: string;
  send_account_id?: string;
  country_region?: string;
  payment_type?: string;
  start_date?: string;
  end_date?: string;
  aggregation_type?: 'total' | 'daily' | 'monthly';
  order_by?: string;
  order_dir?: 'asc' | 'desc';
}

export interface CustomerBillRecord {
  id: string;
  serialNumber: number;
  sendAccount: string;
  accountName: string;
  enterpriseName: string;
  countryRegion: string;
  startTime: string;
  endTime: string;
  billingMethod: string;
  paymentMethod: string;
  billCount: number;
  accountPrice: number;
  accountFee: number;
  createdAt: string;
}

export const customerBillApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    searchCustomerBills: builder.query<CustomerBillResponse, CustomerBillParams>({
      query: (params) => ({
        url: '/billing/customer-bills',
        method: 'GET',
        params: cleanEmptyParams(params),
      }),
      providesTags: ['CustomerBill'],
    }),

    exportCustomerBills: builder.mutation<ExportResponse, CustomerBillParams>({
      query: (params) => ({
        url: '/billing/customer-bills/export',
        method: 'POST',
        body: params,
      }),
    }),

    getCustomerBillStatistics: builder.query<StatisticsData, CustomerBillParams>({
      query: (params) => ({
        url: '/billing/customer-bills/statistics',
        method: 'GET',
        params: cleanEmptyParams(params),
      }),
      providesTags: ['CustomerBillStats'],
    }),
  }),
});
```

#### 2. 状态管理
```typescript
// frontend/src/store/slices/customerBillSlice.ts
interface CustomerBillState {
  searchParams: CustomerBillParams;
  isExporting: boolean;
  exportProgress: number;
  selectedRowKeys: string[];
  tableLoading: boolean;
}

const customerBillSlice = createSlice({
  name: 'customerBill',
  initialState,
  reducers: {
    setSearchParams: (state, action) => {
      state.searchParams = { ...state.searchParams, ...action.payload };
    },
    setExporting: (state, action) => {
      state.isExporting = action.payload;
    },
    setSelectedRowKeys: (state, action) => {
      state.selectedRowKeys = action.payload;
    },
    // ...其他reducers
  },
});
```

#### 3. 组件架构
```
CustomerBillManagementPage (主页面)
├── PageHeader (页面头部)
│   ├── Breadcrumb (面包屑导航)
│   └── PageTitle (页面标题)
├── DataNoticeSection (数据说明)
│   ├── DataSourceInfo (数据来源说明)
│   ├── UpdateTimeInfo (更新时间)
│   └── ReferenceNotice (参考提示)
├── SearchFilterSection (搜索筛选区)
│   ├── MultiDimensionFilters (多维度筛选器)
│   │   ├── AdminFilter (管理员筛选)
│   │   ├── EnterpriseFilter (企业筛选)
│   │   ├── SendAccountFilter (发送账号筛选)
│   │   ├── CountryRegionFilter (国家地区筛选)
│   │   └── PaymentTypeFilter (付费类型筛选)
│   ├── TimeRangeSelector (时间范围选择器)
│   ├── AggregationSelector (聚合方式选择器)
│   ├── QuickFilterButtons (快速筛选按钮)
│   ├── SearchButton (搜索按钮)
│   └── ResetButton (重置按钮)
├── ActionToolbar (操作工具栏)
│   ├── ExportExcelButton (导出Excel按钮)
│   └── RefreshButton (刷新按钮)
├── CustomerBillTable (账单数据表格)
│   ├── TableHeader (表格头部)
│   ├── TableBody (表格主体)
│   └── SummaryFooter (汇总底部)
├── PaginationSection (分页组件)
└── LoadingComponents (加载组件)
    ├── TableLoadingSkeleton (表格加载骨架)
    ├── ExportProgressModal (导出进度弹窗)
    └── DataRefreshIndicator (数据刷新指示器)
```

## 📝 详细开发任务分解

### 阶段1: 后端基础开发 (2天)

#### 任务1.1: 数据库设计与初始化 (0.5天)
- [ ] 分析现有表结构，确定账单数据来源
- [ ] 设计账单查询视图或聚合表
- [ ] 编写数据库初始化脚本
- [ ] 创建测试数据

**交付物**:
- `sql/modules/billing.sql` - 账单相关表结构
- `sql/init_mock_data.sql` - 测试数据更新

#### 任务1.2: 模型层开发 (0.5天)
- [ ] 创建CustomerBillView模型
- [ ] 实现模型基础方法
- [ ] 添加模型关联关系
- [ ] 编写单元测试

**交付物**:
- `app/models/billing/customer_bill.py`
- `app/models/billing/__init__.py`

#### 任务1.3: 服务层开发 (1天)
- [ ] 实现CustomerBillService基础服务
- [ ] 开发多维度搜索功能
- [ ] 实现时间聚合功能
- [ ] 开发统计汇总功能
- [ ] 实现数据导出功能
- [ ] 编写服务层测试

**交付物**:
- `app/services/billing/customer_bill_service.py`
- `app/services/billing/__init__.py`
- `tests/services/test_customer_bill_service.py`

### 阶段2: 后端API开发 (1.5天)

#### 任务2.1: Schema验证开发 (0.5天)
- [ ] 创建CustomerBillQuerySchema
- [ ] 创建CustomerBillResponseSchema
- [ ] 创建ExportRequestSchema
- [ ] 添加数据验证规则

**交付物**:
- `app/api/v1/billing/schema/customer_bill.py`
- `app/api/v1/billing/schema/__init__.py`

#### 任务2.2: API资源开发 (1天)
- [ ] 实现CustomerBillListResource
- [ ] 实现CustomerBillStatisticsResource
- [ ] 实现CustomerBillExportResource
- [ ] 添加权限控制装饰器
- [ ] 编写API测试

**交付物**:
- `app/api/v1/billing/route/customer_bill_list.py`
- `app/api/v1/billing/route/customer_bill_statistics.py`
- `app/api/v1/billing/route/customer_bill_export.py`
- `app/api/v1/billing/route/routes.py`
- `tests/api/test_customer_bill_api.py`

### 阶段3: 前端基础开发 (2天)

#### 任务3.1: API和类型定义 (0.5天)
- [ ] 创建customerBillApi.ts
- [ ] 定义TypeScript接口类型
- [ ] 实现RTK Query端点
- [ ] 配置缓存策略

**交付物**:
- `frontend/src/api/customerBillApi.ts`
- `frontend/src/types/customerBill.ts`

#### 任务3.2: 状态管理开发 (0.5天)
- [ ] 创建customerBillSlice.ts
- [ ] 实现状态管理reducer
- [ ] 集成到store配置
- [ ] 创建自定义hooks

**交付物**:
- `frontend/src/store/slices/customerBillSlice.ts`
- `frontend/src/hooks/useCustomerBill.ts`

#### 任务3.3: 基础组件开发 (1天)
- [ ] 创建CustomerBillManagementPage主页面
- [ ] 实现PageHeader组件
- [ ] 实现DataNoticeSection组件
- [ ] 实现ActionToolbar组件
- [ ] 添加基础样式

**交付物**:
- `frontend/src/pages/FinancialManagement/CustomerBills.tsx`
- `frontend/src/pages/FinancialManagement/components/PageHeader.tsx`
- `frontend/src/pages/FinancialManagement/components/DataNoticeSection.tsx`
- `frontend/src/pages/FinancialManagement/components/ActionToolbar.tsx`

### 阶段4: 前端核心功能开发 (2天)

#### 任务4.1: 搜索筛选组件开发 (1天)
- [ ] 实现SearchFilterSection主组件
- [ ] 开发MultiDimensionFilters组件
- [ ] 实现TimeRangeSelector组件
- [ ] 实现AggregationSelector组件
- [ ] 添加QuickFilterButtons组件

**交付物**:
- `frontend/src/pages/FinancialManagement/components/SearchFilterSection.tsx`
- `frontend/src/pages/FinancialManagement/components/MultiDimensionFilters.tsx`
- `frontend/src/pages/FinancialManagement/components/TimeRangeSelector.tsx`
- `frontend/src/pages/FinancialManagement/components/AggregationSelector.tsx`

#### 任务4.2: 数据表格组件开发 (1天)
- [ ] 实现CustomerBillTable主表格
- [ ] 开发表格列定义和渲染
- [ ] 实现SummaryFooter汇总组件
- [ ] 添加排序和筛选功能
- [ ] 实现数据高亮和状态显示

**交付物**:
- `frontend/src/pages/FinancialManagement/components/CustomerBillTable.tsx`
- `frontend/src/pages/FinancialManagement/components/SummaryFooter.tsx`
- `frontend/src/pages/FinancialManagement/components/BillStatusBadge.tsx`

### 阶段5: 前端高级功能开发 (1.5天)

#### 任务5.1: 数据导出功能 (0.5天)
- [ ] 实现ExportExcelButton组件
- [ ] 开发ExportProgressModal进度弹窗
- [ ] 实现异步导出处理
- [ ] 添加导出状态反馈

**交付物**:
- `frontend/src/pages/FinancialManagement/components/ExportExcelButton.tsx`
- `frontend/src/pages/FinancialManagement/components/ExportProgressModal.tsx`

#### 任务5.2: 用户体验优化 (0.5天)
- [ ] 实现TableLoadingSkeleton加载骨架
- [ ] 添加DataRefreshIndicator刷新指示器
- [ ] 优化分页和响应式设计
- [ ] 添加错误处理和提示

**交付物**:
- `frontend/src/pages/FinancialManagement/components/LoadingComponents.tsx`
- `frontend/src/pages/FinancialManagement/components/PaginationSection.tsx`

#### 任务5.3: 集成测试和优化 (0.5天)
- [ ] 集成所有组件到主页面
- [ ] 前后端联调测试
- [ ] 性能优化和代码优化
- [ ] 添加单元测试

### 阶段6: 测试和文档 (1天)

#### 任务6.1: 功能测试 (0.5天)
- [ ] 端到端功能测试
- [ ] 多维度筛选测试
- [ ] 数据导出测试
- [ ] 权限控制测试
- [ ] 性能和兼容性测试

#### 任务6.2: 文档和部署准备 (0.5天)
- [ ] 编写API文档
- [ ] 更新用户使用文档
- [ ] 代码注释完善
- [ ] 部署配置检查

## 🔧 技术实现要点

### 性能优化策略
1. **数据库优化**
   - 创建合适的索引
   - 使用数据库视图预聚合
   - 分页查询优化

2. **前端优化**
   - 虚拟滚动处理大数据量
   - 防抖搜索优化
   - 组件懒加载
   - RTK Query缓存策略

3. **导出优化**
   - 异步导出处理
   - 分批导出大数据量
   - 进度反馈机制

### 安全考虑
1. **数据权限**
   - 基于角色的数据访问控制
   - 按管理员范围限制数据
   - 敏感信息脱敏处理

2. **操作安全**
   - 权限验证装饰器
   - 输入参数验证
   - SQL注入防护
   - 导出操作审计

### 代码规范遵循
1. **后端规范**
   - 文件头注释规范
   - 三层架构模式
   - 错误处理统一
   - 日志记录规范

2. **前端规范**
   - TypeScript严格模式
   - 组件命名规范
   - 状态管理规范
   - 样式组织规范

## 📋 测试计划

### 单元测试
- [ ] Model层测试
- [ ] Service层测试
- [ ] API层测试
- [ ] 前端组件测试

### 集成测试
- [ ] 前后端API联调
- [ ] 数据流完整性测试
- [ ] 权限系统集成测试

### 用户验收测试
- [ ] 多维度筛选功能
- [ ] 时间聚合功能
- [ ] 数据导出功能
- [ ] 汇总统计功能
- [ ] 分页和排序功能

## 🚀 部署和发布

### 部署前检查
- [ ] 数据库迁移脚本
- [ ] 权限配置更新
- [ ] 环境变量配置
- [ ] 依赖包版本检查

### 发布计划
1. **开发环境验证** (1天)
2. **测试环境部署** (0.5天)
3. **用户验收测试** (1天)
4. **生产环境发布** (0.5天)

## 🎯 验收标准

### 功能验收
- [x] 支持多维度筛选查询
- [x] 支持三种时间聚合方式
- [x] 账单列表完整展示
- [x] 实时汇总统计准确
- [x] Excel导出功能正常
- [x] 分页性能满足要求

### 性能验收
- [x] 查询响应时间 ≤ 5秒
- [x] 支持100+并发查询
- [x] 大数据量导出 ≤ 30秒
- [x] 前端交互响应流畅

### 安全验收
- [x] 权限控制正确生效
- [x] 数据脱敏规则正确
- [x] 操作审计日志完整
- [x] 输入验证安全可靠

## 📊 风险评估和应对

### 技术风险
1. **数据量过大导致查询慢**
   - 应对: 数据分区、索引优化、缓存策略

2. **导出功能内存溢出**
   - 应对: 分批导出、异步处理、流式导出

3. **前端性能问题**
   - 应对: 虚拟滚动、分页加载、组件优化

### 业务风险
1. **数据准确性问题**
   - 应对: 完善的数据验证、对账机制

2. **权限控制不当**
   - 应对: 严格的权限测试、数据隔离验证

## 📈 后续扩展规划

### 短期扩展 (1-2个月)
- [ ] 增加图表可视化分析
- [ ] 添加自动报告生成
- [ ] 实现数据预警机制

### 长期扩展 (3-6个月)
- [ ] 移动端支持
- [ ] API接口开放
- [ ] 高级分析功能
- [ ] 机器学习分析

---

**文档版本**: v1.0
**创建日期**: 2025-09-23
**最后更新**: 2025-09-23
**负责人**: Claude Code Assistant

**备注**: 此开发计划基于FEAT-2-2需求文档和pigeon_web现有架构制定，具体实施时间可根据实际情况调整。