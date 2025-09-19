# FEAT-6-2-8 国家短信价格功能开发计划

## 📋 项目概述

**功能名称**: 通道国际短信价格管理
**需求编号**: FEAT-6-2-8
**优先级**: P0 (高优先级)
**预估工期**: 5-7个工作日
**开发模式**: 全栈开发 (数据库 + 后端API + 前端界面)

### 功能目标
为通道管理系统增加国际短信价格配置功能，支持价格新增、列表查看、批量导入等核心操作，为平台管理员和商务运营提供完整的价格管理工具。

## 🏗️ 技术架构设计

### 架构概述
基于现有pigeon_web系统架构，采用三层分离设计：
- **数据层**: PostgreSQL + 新增国家价格相关表
- **服务层**: Flask + RESTful API
- **展示层**: React + TypeScript + Ant Design

### 核心实体设计
```sql
-- 核心数据表
ChannelCountryPrice: 通道国家价格配置表
CountryRegion: 国家地区基础数据表 (复用现有)
PriceImportLog: 价格导入日志表
```

## 📊 数据库设计方案

### 阶段1: 数据库Schema设计

#### 1.1 通道国家价格表设计
```sql
CREATE TABLE channel_country_prices (
    price_id BIGSERIAL PRIMARY KEY,
    channel_id VARCHAR(255) NOT NULL REFERENCES channels(channel_id) ON DELETE CASCADE,
    country_code VARCHAR(3) NOT NULL,                    -- ISO国家代码 (PH, CN等)
    country_name_cn VARCHAR(100) NOT NULL,               -- 国家中文名称
    area_code VARCHAR(10) NOT NULL,                      -- 国际区号
    price DECIMAL(10,5) NOT NULL CHECK (price > 0),      -- 价格(¥), 保留5位小数
    currency VARCHAR(3) DEFAULT 'CNY',                   -- 货币单位
    admin_id INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- 唯一约束: 同一通道同一国家只能有一个价格配置
    UNIQUE(channel_id, country_code)
);
```

#### 1.2 价格导入日志表设计
```sql
CREATE TABLE price_import_logs (
    log_id BIGSERIAL PRIMARY KEY,
    channel_id VARCHAR(255) NOT NULL REFERENCES channels(channel_id),
    admin_id INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size INTEGER,
    total_count INTEGER DEFAULT 0,
    success_count INTEGER DEFAULT 0,
    failed_count INTEGER DEFAULT 0,
    error_details JSONB DEFAULT '[]',
    import_status VARCHAR(20) DEFAULT 'processing' CHECK (import_status IN ('processing', 'completed', 'failed')),
    import_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_time TIMESTAMP
);
```

#### 1.3 索引设计
```sql
-- 查询性能优化索引
CREATE INDEX idx_channel_country_prices_channel_id ON channel_country_prices(channel_id);
CREATE INDEX idx_channel_country_prices_country_code ON channel_country_prices(country_code);
CREATE INDEX idx_channel_country_prices_admin_id ON channel_country_prices(admin_id);
CREATE INDEX idx_channel_country_prices_created_at ON channel_country_prices(created_at DESC);
CREATE INDEX idx_price_import_logs_channel_id ON price_import_logs(channel_id);
CREATE INDEX idx_price_import_logs_admin_id ON price_import_logs(admin_id);
```

#### 1.4 Mock测试数据
```sql
-- 为通道25090501增加测试价格数据
INSERT INTO channel_country_prices (channel_id, country_code, country_name_cn, area_code, price, admin_id) VALUES
('25090501', 'PH', '菲律宾', '63', 1.36355, 1),
('25090501', 'CN', '中国', '86', 0.05000, 1),
('25090501', 'US', '美国', '1', 0.85000, 1),
('25090501', 'JP', '日本', '81', 1.20000, 1),
('25090501', 'SG', '新加坡', '65', 0.95000, 1);
```

## 🔧 后端API开发方案

### 阶段2: 后端服务层开发

#### 2.1 数据模型开发
**文件**: `app/models/customers/channel_country_price.py`

```python
# Copyright(c) 2025
# All rights reserved.
#
# Author: yukun.xing <xingyukun@gmail.com>
# Date:   2025/09/18

class ChannelCountryPrice(db.Model, TimestampMixin):
    __tablename__ = 'channel_country_prices'

    price_id = db.Column(db.BigInteger, primary_key=True)
    channel_id = db.Column(db.String(255), db.ForeignKey('channels.channel_id'), nullable=False)
    country_code = db.Column(db.String(3), nullable=False)
    country_name_cn = db.Column(db.String(100), nullable=False)
    area_code = db.Column(db.String(10), nullable=False)
    price = db.Column(db.Numeric(10, 5), nullable=False)
    currency = db.Column(db.String(3), default='CNY')
    admin_id = db.Column(db.Integer, db.ForeignKey('admin_users.id'))
    is_active = db.Column(db.Boolean, default=True)

    # 关联关系
    channel = db.relationship('Channel', backref='country_prices')
    admin = db.relationship('AdminUser', backref='created_prices')

    # 唯一约束
    __table_args__ = (
        db.UniqueConstraint('channel_id', 'country_code', name='uk_channel_country'),
        db.CheckConstraint('price > 0', name='ck_price_positive'),
    )
```

#### 2.2 Marshmallow Schema设计
**文件**: `app/api/v1/channels/schema/country_price.py`

```python
class ChannelCountryPriceSchema(BaseSchema):
    price_id = fields.Integer(dump_only=True)
    channel_id = fields.String(required=True)
    country_code = fields.String(required=True, validate=validate.Length(2, 3))
    country_name_cn = fields.String(required=True, validate=validate.Length(1, 100))
    area_code = fields.String(required=True, validate=validate.Length(1, 10))
    price = fields.Decimal(required=True, validate=validate.Range(min=0.00001))
    currency = fields.String(missing='CNY')
    admin_id = fields.Integer(dump_only=True)
    is_active = fields.Boolean(missing=True)
    created_at = fields.DateTime(dump_only=True)
    updated_at = fields.DateTime(dump_only=True)

class CountryPriceImportSchema(BaseSchema):
    country_name_cn = fields.String(required=True)
    area_code = fields.String(required=True)
    country_code = fields.String(required=True)
    price = fields.Decimal(required=True)
```

#### 2.3 业务服务层开发
**文件**: `app/services/customers/channel_country_price_service.py`

核心业务方法：
- `get_price_list()`: 获取价格列表 (支持分页、搜索)
- `create_price()`: 创建价格配置
- `update_price()`: 更新价格配置
- `delete_price()`: 删除价格配置
- `bulk_import_prices()`: 批量导入价格
- `export_price_template()`: 生成导入模板
- `validate_import_data()`: 导入数据验证

#### 2.4 API路由开发
**文件**: `app/api/v1/channels/route/country_price.py`

API端点设计：
```python
# 价格列表和创建
GET/POST /api/v1/channels/{channel_id}/country-prices

# 价格详情、更新、删除
GET/PUT/DELETE /api/v1/channels/{channel_id}/country-prices/{price_id}

# 批量导入
POST /api/v1/channels/{channel_id}/country-prices/import

# 模板下载
GET /api/v1/channels/country-prices/template

# 国家地区列表 (基础数据)
GET /api/v1/common/countries
```

## 🎨 前端UI开发方案

### 阶段3: 前端界面开发

#### 3.1 页面组件架构
```
src/pages/ChannelManagement/components/
├── CountryPriceManagementModal.tsx      # 主管理弹窗 (1200px宽度)
├── CountryPriceTable.tsx                # 价格列表表格
├── CountryPriceForm.tsx                 # 价格表单 (新增/编辑)
├── CountryPriceBatchImport.tsx          # 批量导入组件
├── CountryPriceSearchFilter.tsx         # 搜索筛选组件
└── CountryPriceStatistics.tsx          # 统计面板组件
```

#### 3.2 核心组件功能

**主管理弹窗特性**:
- 1200px宽度，符合UI/UX设计规范
- Tab切换：价格列表、导入历史
- 统计面板：总价格数、配置国家数、平均价格
- 响应式布局，支持移动端适配

**价格列表表格特性**:
- 表格列：序号、国家中文名、区号、国家代码、价格(¥)、创建时间、操作
- 支持排序：按价格、创建时间排序
- 支持搜索：国家名称、国家代码模糊搜索
- 批量操作：批量删除选中价格

**价格表单特性**:
- 国家地区选择器（支持搜索）
- 价格输入（实时验证，最多5位小数）
- 表单验证：必填项、格式验证、重复检查
- 支持新增和编辑两种模式

**批量导入特性**:
- 4步骤导入流程：选择文件 → 验证数据 → 执行导入 → 查看结果
- Excel文件验证和解析
- 导入进度条显示
- 错误数据报告下载
- 导入模板下载

#### 3.3 API和状态管理
**文件**: `src/api/countryPriceApi.ts`

```typescript
export const countryPriceApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // 价格列表查询
    getCountryPrices: builder.query<CountryPriceListResponse, CountryPriceListRequest>({
      query: ({ channelId, ...params }) => ({
        url: `/channels/${channelId}/country-prices`,
        params,
      }),
      providesTags: ['CountryPrice'],
    }),

    // 创建价格
    createCountryPrice: builder.mutation<CountryPrice, CreateCountryPriceRequest>({
      query: ({ channelId, ...data }) => ({
        url: `/channels/${channelId}/country-prices`,
        method: 'POST',
        body: data,
      }),
      invalidatesTags: ['CountryPrice'],
    }),

    // 批量导入
    importCountryPrices: builder.mutation<ImportResult, ImportRequest>({
      query: ({ channelId, file }) => {
        const formData = new FormData();
        formData.append('file', file);
        return {
          url: `/channels/${channelId}/country-prices/import`,
          method: 'POST',
          body: formData,
        };
      },
      invalidatesTags: ['CountryPrice'],
    }),

    // 模板下载
    downloadTemplate: builder.query<Blob, void>({
      query: () => ({
        url: '/channels/country-prices/template',
        responseHandler: (response) => response.blob(),
      }),
    }),
  }),
});
```

**状态管理**: `src/store/slices/countryPriceSlice.ts`
- 弹窗显示状态管理
- 表单数据状态管理
- 导入流程状态管理
- 搜索筛选状态管理

#### 3.4 类型定义
**文件**: `src/types/countryPrice.ts`

```typescript
export interface CountryPrice {
  priceId: number;
  channelId: string;
  countryCode: string;
  countryNameCn: string;
  areaCode: string;
  price: number;
  currency: string;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CountryPriceFormData {
  countryCode: string;
  countryNameCn: string;
  areaCode: string;
  price: number;
}

export interface ImportTemplate {
  countryNameCn: string;
  areaCode: string;
  countryCode: string;
  price: number;
}

export interface ImportResult {
  totalCount: number;
  successCount: number;
  failedCount: number;
  errors: ImportError[];
}
```

## 📋 集成方案设计

### 阶段4: 系统集成

#### 4.1 通道管理页面集成
**修改文件**: `src/pages/ChannelManagement/components/ChannelActionButtons.tsx`

在"更多"下拉菜单中添加"国家价格管理"选项：
```typescript
const moreMenuItems = [
  {
    key: 'sender',
    label: 'Sender管理',
    icon: <MessageOutlined />,
    onClick: () => setShowSenderModal(true),
  },
  {
    key: 'country-price',
    label: '国家价格管理',
    icon: <DollarOutlined />,
    onClick: () => setShowCountryPriceModal(true),
  },
  // ... 其他菜单项
];
```

#### 4.2 路由注册
**修改文件**: `app/api/v1/channels/route/routes.py`

```python
# 注册国家价格管理路由
from .country_price import country_price_bp
app.register_blueprint(country_price_bp, url_prefix='/api/v1/channels')
```

#### 4.3 权限控制集成
基于现有RBAC权限系统，新增权限：
- `channel:country_price:view`: 查看国家价格
- `channel:country_price:create`: 创建国家价格
- `channel:country_price:update`: 更新国家价格
- `channel:country_price:delete`: 删除国家价格
- `channel:country_price:import`: 批量导入价格

## 🧪 测试验证方案

### 阶段5: 功能测试

#### 5.1 后端API测试
- 单元测试：模型、服务层方法测试
- 集成测试：API端点功能测试
- 性能测试：批量导入性能测试
- 安全测试：权限控制、数据验证测试

#### 5.2 前端组件测试
- 组件渲染测试
- 用户交互测试
- 表单验证测试
- 文件上传测试

#### 5.3 端到端测试
- 价格管理完整流程测试
- 批量导入完整流程测试
- 权限控制有效性测试
- 跨浏览器兼容性测试

## 📅 开发时间安排

### 第1-2天: 数据库层开发
- **数据库Schema设计和创建** (4小时)
- **Mock测试数据准备** (2小时)
- **数据模型开发和验证** (2小时)

### 第3-4天: 后端API开发
- **Marshmallow Schema设计** (2小时)
- **业务服务层开发** (6小时)
- **API路由层开发** (4小时)
- **单元测试和集成测试** (4小时)

### 第5-6天: 前端界面开发
- **API接口和类型定义** (3小时)
- **核心组件开发** (8小时)
- **状态管理和集成** (3小时)
- **样式调整和优化** (2小时)

### 第7天: 系统集成和测试
- **系统集成和路由注册** (2小时)
- **权限控制集成** (2小时)
- **端到端测试和Bug修复** (3小时)
- **代码review和文档完善** (1小时)

## ⚠️ 风险评估和应对

### 技术风险
- **Excel文件解析复杂性**: 采用成熟的SheetJS库，预先验证文件格式
- **大数据量导入性能**: 实现分批处理和进度反馈机制
- **国家地区数据一致性**: 建立标准的国家代码映射表

### 业务风险
- **价格数据准确性**: 实现严格的数据验证和操作审计
- **并发操作冲突**: 使用数据库唯一约束和乐观锁机制
- **用户权限控制**: 基于现有RBAC系统，确保细粒度权限控制

### 应对措施
- 充分的单元测试和集成测试覆盖
- 详细的错误日志和监控机制
- 完善的操作审计和回滚机制
- 分阶段开发和验证，降低集成风险

## 🎯 验收标准

### 功能验收
- ✅ 价格列表显示功能正常，支持分页、搜索、排序
- ✅ 新增价格功能正常，表单验证完整
- ✅ 编辑删除价格功能正常，权限控制有效
- ✅ 批量导入功能正常，支持Excel文件处理
- ✅ 模板下载功能正常，模板格式标准
- ✅ 权限控制严格有效，操作日志完整

### 性能验收
- ✅ 价格列表查询响应时间 < 2秒
- ✅ 价格操作响应时间 < 3秒
- ✅ 批量导入处理性能合理 (1000条数据 < 30秒)
- ✅ 界面交互流畅，无明显卡顿

### 安全验收
- ✅ 文件上传安全验证有效
- ✅ 数据验证完整，防止恶意数据
- ✅ 操作审计完整，可追踪所有变更
- ✅ 权限控制细粒度，符合业务要求

## 📚 技术文档和交付物

### 开发文档
- **数据库设计文档**: Schema设计和索引优化说明
- **API接口文档**: RESTful API规范和使用示例
- **前端组件文档**: 组件架构和使用指南
- **部署指南**: 数据库迁移和系统配置说明

### 用户文档
- **功能使用手册**: 价格管理功能操作指南
- **导入模板说明**: Excel模板格式和填写规范
- **常见问题解答**: 用户常见操作问题和解决方案

---

## 📝 总结

FEAT-6-2-8国家短信价格功能开发项目将为pigeon_web系统增加完整的国际短信价格管理能力。项目采用标准的三层架构设计，确保与现有系统的良好集成。

**核心价值**:
- 🎯 **业务价值**: 提供完整的价格管理工具，支持国际化业务发展
- 🏗️ **技术价值**: 标准化的开发模式，为后续功能开发奠定基础
- 👥 **用户价值**: 直观友好的操作界面，显著提升工作效率
- 🛡️ **安全价值**: 完善的权限控制和审计机制，确保数据安全

**最终成果**: 企业级的通道国际短信价格管理系统，支持完整的价格配置生命周期管理。

**当前状态**: 📋 **开发计划已完成，等待开发执行阶段**