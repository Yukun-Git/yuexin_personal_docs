# FEAT-7-10 平台错误码管理 - 详细设计与开发计划

## 文档信息
- **功能编号**: FEAT-7-10
- **功能名称**: 平台错误码管理
- **创建日期**: 2025-10-14
- **作者**: Claude Code
- **版本**: v1.0

## 1. 需求概述

### 1.1 功能目标
平台错误码管理系统用于统一管理国际短信平台中所有内部错误码的定义和维护，包括：
- 通道错误码（200系列）：处理通道层面的消息推送和队列操作错误
- 调度错误码（100系列）：处理短信调度过程中的业务逻辑错误
- 网关错误码（十六进制）：处理SMPP协议层面的通信错误

### 1.2 核心功能
1. 错误码信息展示和查询
2. 错误码分类筛选和搜索
3. 错误码描述和处理建议编辑
4. 批量导入导出（Excel格式）
5. 统计信息展示

### 1.3 业务关系说明
- **平台错误码** (FEAT-7-10): 管理pigeon平台内部的错误码定义
- **通道状态码** (FEAT-6-10): 管理通道供应商返回的状态码，未来会通过映射规则转换为平台错误码
- 最终返回给用户的是平台内部错误码

## 2. 数据库设计

### 2.1 表结构设计

#### 2.1.1 错误码类别表 (platform_error_categories)

**表名**: `mgmt.platform_error_categories`

**用途**: 存储错误码分类信息，支持未来扩展

**字段定义**:
```sql
CREATE TABLE mgmt.platform_error_categories (
    -- 主键
    category_code VARCHAR(50) PRIMARY KEY,

    -- 基本信息
    category_name VARCHAR(100) NOT NULL,
    description TEXT,
    sort_order INTEGER DEFAULT 0,

    -- 状态
    is_active BOOLEAN DEFAULT TRUE,

    -- 时间戳
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE mgmt.platform_error_categories IS '平台错误码分类表';
COMMENT ON COLUMN mgmt.platform_error_categories.category_code IS '分类代码（如: channel, dispatch, gateway）';
COMMENT ON COLUMN mgmt.platform_error_categories.category_name IS '分类名称（中文）';
COMMENT ON COLUMN mgmt.platform_error_categories.description IS '分类描述';
COMMENT ON COLUMN mgmt.platform_error_categories.sort_order IS '排序顺序';
COMMENT ON COLUMN mgmt.platform_error_categories.is_active IS '是否启用';
```

**初始数据**:
```sql
INSERT INTO mgmt.platform_error_categories (category_code, category_name, description, sort_order) VALUES
('dispatch', '调度错误码', '短信调度过程中的业务逻辑错误（100-199系列）', 1),
('channel', '通道错误码', '通道层面的消息推送和队列操作错误（200-299系列）', 2),
('gateway', '网关错误码', 'SMPP协议层面的通信错误（十六进制格式）', 3);
```

#### 2.1.2 平台错误码表 (platform_errors)

**表名**: `mgmt.platform_errors`

**用途**: 存储平台所有错误码的完整信息

**字段定义**:
```sql
CREATE TABLE mgmt.platform_errors (
    -- 主键：错误码编号（字符串格式，支持整数和十六进制）
    error_code VARCHAR(20) PRIMARY KEY,

    -- 基本信息
    error_name VARCHAR(200) NOT NULL,
    category_code VARCHAR(50) NOT NULL,

    -- 描述信息
    description TEXT,
    detailed_explanation TEXT,
    processing_suggestion TEXT,

    -- 元数据
    metadata JSONB DEFAULT '{}',

    -- 时间戳
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- 外键约束
    CONSTRAINT fk_error_category
        FOREIGN KEY (category_code)
        REFERENCES mgmt.platform_error_categories(category_code)
        ON DELETE RESTRICT
);

-- 索引
CREATE INDEX idx_platform_errors_category ON mgmt.platform_errors(category_code);
CREATE INDEX idx_platform_errors_name ON mgmt.platform_errors USING gin(to_tsvector('simple', error_name));
CREATE INDEX idx_platform_errors_description ON mgmt.platform_errors USING gin(to_tsvector('simple', description));

COMMENT ON TABLE mgmt.platform_errors IS '平台错误码表';
COMMENT ON COLUMN mgmt.platform_errors.error_code IS '错误码编号（支持整数和十六进制字符串）';
COMMENT ON COLUMN mgmt.platform_errors.error_name IS '错误码名称';
COMMENT ON COLUMN mgmt.platform_errors.category_code IS '错误码类别';
COMMENT ON COLUMN mgmt.platform_errors.description IS '中文描述（简短）';
COMMENT ON COLUMN mgmt.platform_errors.detailed_explanation IS '详细说明（包括产生原因等）';
COMMENT ON COLUMN mgmt.platform_errors.processing_suggestion IS '处理建议（具体的解决步骤）';
COMMENT ON COLUMN mgmt.platform_errors.metadata IS '扩展元数据（JSON格式）';
```

### 2.2 Mock数据设计

创建文件 `pigeon_web/sql/mock_data/error_codes_mock.sql`，包含：
- 至少10个调度错误码示例（100-110）
- 至少10个通道错误码示例（200-210）
- 至少5个网关错误码示例（0x00000000-0x00000005）

### 2.3 数据库更新触发器

```sql
-- 自动更新 updated_at 字段
CREATE OR REPLACE FUNCTION update_platform_errors_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_platform_errors_updated_at
    BEFORE UPDATE ON mgmt.platform_errors
    FOR EACH ROW
    EXECUTE FUNCTION update_platform_errors_updated_at();

CREATE TRIGGER trigger_update_platform_error_categories_updated_at
    BEFORE UPDATE ON mgmt.platform_error_categories
    FOR EACH ROW
    EXECUTE FUNCTION update_platform_errors_updated_at();
```

## 3. 后端设计

### 3.1 项目结构

```
pigeon_web/
├── app/
│   ├── models/
│   │   └── base/
│   │       ├── platform_error.py          # 错误码模型
│   │       └── platform_error_category.py  # 错误码分类模型
│   ├── services/
│   │   └── platform_errors/
│   │       ├── __init__.py
│   │       ├── platform_error_service.py   # 错误码业务服务
│   │       └── category_service.py         # 分类业务服务
│   └── api/
│       └── v1/
│           └── platform_errors/
│               ├── __init__.py
│               ├── route/
│               │   ├── __init__.py
│               │   ├── error_list.py       # 错误码列表和创建
│               │   ├── error_detail.py     # 错误码详情和更新
│               │   ├── error_batch.py      # 批量导入导出
│               │   ├── error_statistics.py # 统计信息
│               │   ├── category_list.py    # 分类列表
│               │   └── routes.py           # 路由注册
│               └── schema/
│                   ├── __init__.py
│                   ├── error_schema.py     # 错误码schema
│                   └── category_schema.py  # 分类schema
```

### 3.2 Model层设计

#### 3.2.1 PlatformErrorCategory Model

**文件**: `pigeon_web/app/models/base/platform_error_category.py`

**主要属性**:
- `category_code`: 分类代码（主键）
- `category_name`: 分类名称
- `description`: 描述
- `sort_order`: 排序
- `is_active`: 是否启用

**主要方法**:
- `to_dict()`: 转换为字典
- `get_active_categories()`: 获取所有启用的分类（类方法）

#### 3.2.2 PlatformError Model

**文件**: `pigeon_web/app/models/base/platform_error.py`

**主要属性**:
- `error_code`: 错误码（主键）
- `error_name`: 错误码名称
- `category_code`: 分类代码（外键）
- `description`: 中文描述
- `detailed_explanation`: 详细说明
- `processing_suggestion`: 处理建议
- `metadata`: 元数据（JSON）

**关系**:
- `category`: 关联到 PlatformErrorCategory

**主要方法**:
- `to_dict()`: 转换为字典
- `update_from_dict(data)`: 从字典更新
- `get_by_code(error_code)`: 根据错误码获取（类方法）

### 3.3 Service层设计

#### 3.3.1 PlatformErrorService

**文件**: `pigeon_web/app/services/platform_errors/platform_error_service.py`

**继承**: `BaseService`

**主要方法**:

1. **查询相关**:
   - `get_errors_with_filters(page, per_page, search, category_code, order_by, order_dir)`: 分页查询，支持筛选
   - `get_error_by_code(error_code)`: 根据错误码查询
   - `search_errors(search_term, limit)`: 搜索错误码

2. **创建和更新**:
   - `create_error(data)`: 创建错误码
   - `update_error(error_code, data)`: 更新错误码
   - `delete_error(error_code)`: 删除错误码

3. **批量操作**:
   - `batch_import_errors(file_path)`: 批量导入
   - `batch_export_errors(params)`: 批量导出
   - `generate_import_template()`: 生成导入模板

4. **统计信息**:
   - `get_statistics()`: 获取统计信息

#### 3.3.2 CategoryService

**文件**: `pigeon_web/app/services/platform_errors/category_service.py`

**主要方法**:
- `get_all_categories()`: 获取所有分类
- `get_active_categories()`: 获取启用的分类
- `get_category_by_code(category_code)`: 根据代码获取分类

### 3.4 API层设计

#### 3.4.1 路由定义

**基础路径**: `/api/v1/platform-errors`

| 方法 | 路径 | 功能 | 权限 |
|------|------|------|------|
| GET | `/` | 获取错误码列表 | `platform_error_read` |
| POST | `/` | 创建错误码 | `platform_error_create` |
| GET | `/<error_code>` | 获取错误码详情 | `platform_error_read` |
| PUT | `/<error_code>` | 更新错误码 | `platform_error_update` |
| DELETE | `/<error_code>` | 删除错误码 | `platform_error_delete` |
| GET | `/statistics` | 获取统计信息 | `platform_error_read` |
| POST | `/import` | 批量导入 | `platform_error_create` |
| POST | `/export` | 批量导出 | `platform_error_read` |
| GET | `/import/template` | 下载导入模板 | `platform_error_read` |
| GET | `/categories` | 获取分类列表 | `platform_error_read` |

#### 3.4.2 请求和响应Schema

**查询参数**:
```python
{
    "page": 1,
    "per_page": 20,
    "search": "",           # 搜索关键词
    "category_code": "",    # 分类筛选
    "order_by": "error_code",
    "order_dir": "asc"
}
```

**错误码对象**:
```python
{
    "error_code": "101",
    "error_name": "账号不存在",
    "category_code": "dispatch",
    "category_name": "调度错误码",
    "description": "指定的发送账号不存在",
    "detailed_explanation": "在短信调度过程中，系统无法找到指定的发送账号记录...",
    "processing_suggestion": "1. 检查发送账号是否存在且状态正常\n2. 验证账号ID是否正确...",
    "created_at": "2025-01-01T00:00:00",
    "updated_at": "2025-01-01T00:00:00"
}
```

**统计信息**:
```python
{
    "total_errors": 100,
    "by_category": {
        "dispatch": 50,
        "channel": 40,
        "gateway": 10
    },
    "recent_updates": 5  # 最近7天更新数量
}
```

## 4. 前端设计

### 4.1 项目结构

```
pigeon_web/frontend/src/
├── types/
│   └── entities/
│       └── platformError.ts        # 类型定义
├── api/
│   └── platformErrorApi.ts         # API接口
├── store/
│   └── slices/
│       └── platformErrorSlice.ts   # Redux状态管理
└── pages/
    └── SystemSettings/
        └── PlatformErrorManagement/
            ├── index.tsx                           # 主页面
            ├── PlatformErrorManagementPage.tsx     # 页面组件
            └── components/
                ├── index.ts
                ├── StatisticsPanel.tsx             # 统计面板
                ├── SearchFilterSection.tsx         # 搜索筛选区
                ├── PlatformErrorTable.tsx          # 错误码表格
                ├── PlatformErrorDetailModal.tsx    # 详情弹窗
                ├── PlatformErrorEditModal.tsx      # 编辑弹窗
                ├── BatchImportModal.tsx            # 批量导入弹窗
                └── BatchExportModal.tsx            # 批量导出弹窗
```

### 4.2 页面组件设计

#### 4.2.1 主页面布局

**文件**: `PlatformErrorManagementPage.tsx`

**布局结构**:
```
┌─────────────────────────────────────────────┐
│ 页面标题 + 操作按钮（刷新、导入、导出）      │
├─────────────────────────────────────────────┤
│ 统计面板（总数、各分类数量）                 │
├─────────────────────────────────────────────┤
│ 搜索筛选区                                   │
│ - 错误码类别下拉框                           │
│ - 错误码编号搜索框                           │
│ - 错误码描述搜索框                           │
│ - 查询/重置按钮                              │
├─────────────────────────────────────────────┤
│ 错误码列表表格                               │
│ - 序号、错误码、错误码名称、类别、描述、操作 │
│ - 分页控件                                   │
└─────────────────────────────────────────────┘
```

#### 4.2.2 核心组件

1. **StatisticsPanel** - 统计面板
   - 显示总数和分类统计
   - 使用 Ant Design Card 和 Statistic 组件
   - 支持加载状态

2. **SearchFilterSection** - 搜索筛选区
   - 类别下拉选择（包含"全部类别"选项）
   - 错误码编号输入框
   - 错误码描述输入框
   - 查询和重置按钮

3. **PlatformErrorTable** - 错误码表格
   - 列定义：序号、错误码、错误码名称、类别、中文描述、操作
   - 类别列使用 Badge 组件展示，不同类别不同颜色
   - 操作列：查看、编辑按钮
   - 支持排序和分页

4. **PlatformErrorEditModal** - 编辑弹窗
   - 基础信息区（只读）：错误码、错误码名称、类别
   - 可编辑区：
     - 中文描述（单行文本框）
     - 详细说明（多行文本框）
     - 处理建议（多行文本框）
   - 取消/保存按钮

5. **BatchImportModal** - 批量导入弹窗
   - 模板下载区
   - 文件上传区（支持拖拽）
   - 导入预览表格
   - 验证结果显示
   - 取消/导入按钮

6. **BatchExportModal** - 批量导出弹窗
   - 类别筛选复选框组
   - 字段选择复选框组
   - 取消/导出按钮

### 4.3 状态管理

**Redux Slice**: `platformErrorSlice`

**State结构**:
```typescript
{
  // 列表数据
  errors: PlatformError[],
  categories: PlatformErrorCategory[],
  pagination: {
    page: number,
    per_page: number,
    total: number,
    pages: number
  },

  // 筛选条件
  filters: {
    search: string,
    category_code: string,
    order_by: string,
    order_dir: 'asc' | 'desc'
  },

  // UI状态
  isDetailModalOpen: boolean,
  isEditModalOpen: boolean,
  isImportModalOpen: boolean,
  isExportModalOpen: boolean,
  selectedError: PlatformError | null,

  // 加载状态
  loading: boolean,
  error: string | null
}
```

### 4.4 API接口定义

**文件**: `src/api/platformErrorApi.ts`

**主要接口**:
```typescript
// 查询列表
getPlatformErrors(params: QueryParams): Promise<PaginatedResponse<PlatformError>>

// 获取详情
getPlatformError(errorCode: string): Promise<PlatformError>

// 创建/更新/删除
createPlatformError(data: CreateErrorData): Promise<PlatformError>
updatePlatformError(errorCode: string, data: UpdateErrorData): Promise<PlatformError>
deletePlatformError(errorCode: string): Promise<void>

// 统计信息
getPlatformErrorStatistics(): Promise<ErrorStatistics>

// 批量操作
importPlatformErrors(file: File): Promise<ImportResult>
exportPlatformErrors(params: ExportParams): Promise<Blob>
downloadImportTemplate(): Promise<Blob>

// 分类相关
getPlatformErrorCategories(): Promise<PlatformErrorCategory[]>
```

### 4.5 类型定义

**文件**: `src/types/entities/platformError.ts`

```typescript
export interface PlatformErrorCategory {
  category_code: string;
  category_name: string;
  description: string;
  sort_order: number;
  is_active: boolean;
}

export interface PlatformError {
  error_code: string;
  error_name: string;
  category_code: string;
  category_name?: string;
  description: string;
  detailed_explanation?: string;
  processing_suggestion?: string;
  created_at: string;
  updated_at: string;
}

export interface ErrorStatistics {
  total_errors: number;
  by_category: Record<string, number>;
  recent_updates: number;
}

export interface QueryParams {
  page: number;
  per_page: number;
  search?: string;
  category_code?: string;
  order_by?: string;
  order_dir?: 'asc' | 'desc';
}

export interface ImportResult {
  success_count: number;
  error_count: number;
  errors: Array<{
    row: number;
    error_code: string;
    message: string;
  }>;
}
```

## 5. 开发计划

### 阶段一：数据库和Model层（第1-2步）

#### 第1步：数据库Schema创建
- [ ] 创建 `pigeon_web/sql/modules/error_codes.sql`
  - [ ] 创建 `platform_error_categories` 表
  - [ ] 创建 `platform_errors` 表
  - [ ] 创建索引和触发器
  - [ ] 插入初始分类数据
- [ ] 创建 `pigeon_web/sql/mock_data/error_codes_mock.sql`
  - [ ] 插入调度错误码示例数据（至少10条）
  - [ ] 插入通道错误码示例数据（至少10条）
  - [ ] 插入网关错误码示例数据（至少5条）
- [ ] 更新 `pigeon_web/sql/pigeon_web.sql`
  - [ ] 引入 error_codes 模块
- [ ] 测试数据库初始化脚本

#### 第2步：Model层实现
- [ ] 创建 `app/models/base/platform_error_category.py`
  - [ ] 定义 PlatformErrorCategory 模型
  - [ ] 实现 to_dict() 方法
  - [ ] 实现 get_active_categories() 类方法
- [ ] 创建 `app/models/base/platform_error.py`
  - [ ] 定义 PlatformError 模型
  - [ ] 定义与 category 的关系
  - [ ] 实现 to_dict() 方法
  - [ ] 实现 update_from_dict() 方法
  - [ ] 实现 get_by_code() 类方法
- [ ] 更新 `app/models/base/__init__.py` 导出新模型
- [ ] 编写Model层单元测试

### 阶段二：Service层实现（第3-4步）

#### 第3步：CategoryService实现
- [ ] 创建 `app/services/platform_errors/__init__.py`
- [ ] 创建 `app/services/platform_errors/category_service.py`
  - [ ] 实现 get_all_categories()
  - [ ] 实现 get_active_categories()
  - [ ] 实现 get_category_by_code()
- [ ] 编写CategoryService单元测试

#### 第4步：PlatformErrorService实现
- [ ] 创建 `app/services/platform_errors/platform_error_service.py`
  - [ ] 继承 BaseService
  - [ ] 实现查询方法：
    - [ ] get_errors_with_filters()
    - [ ] get_error_by_code()
    - [ ] search_errors()
  - [ ] 实现创建和更新方法：
    - [ ] create_error()
    - [ ] update_error()
    - [ ] delete_error()
  - [ ] 实现批量操作方法：
    - [ ] batch_import_errors()
    - [ ] batch_export_errors()
    - [ ] generate_import_template()
  - [ ] 实现统计方法：
    - [ ] get_statistics()
- [ ] 编写PlatformErrorService单元测试

### 阶段三：API层实现（第5-7步）

#### 第5步：Schema定义
- [ ] 创建 `app/api/v1/platform_errors/__init__.py`
- [ ] 创建 `app/api/v1/platform_errors/schema/__init__.py`
- [ ] 创建 `app/api/v1/platform_errors/schema/category_schema.py`
  - [ ] 定义分类响应schema
- [ ] 创建 `app/api/v1/platform_errors/schema/error_schema.py`
  - [ ] 定义错误码查询schema
  - [ ] 定义错误码创建schema
  - [ ] 定义错误码更新schema
  - [ ] 定义统计响应schema

#### 第6步：路由实现 - 基础CRUD
- [ ] 创建 `app/api/v1/platform_errors/route/__init__.py`
- [ ] 创建 `app/api/v1/platform_errors/route/error_list.py`
  - [ ] 实现 GET / (获取列表)
  - [ ] 实现 POST / (创建错误码)
- [ ] 创建 `app/api/v1/platform_errors/route/error_detail.py`
  - [ ] 实现 GET /<error_code> (获取详情)
  - [ ] 实现 PUT /<error_code> (更新错误码)
  - [ ] 实现 DELETE /<error_code> (删除错误码)
- [ ] 创建 `app/api/v1/platform_errors/route/category_list.py`
  - [ ] 实现 GET /categories (获取分类列表)

#### 第7步：路由实现 - 批量操作和统计
- [ ] 创建 `app/api/v1/platform_errors/route/error_statistics.py`
  - [ ] 实现 GET /statistics (获取统计信息)
- [ ] 创建 `app/api/v1/platform_errors/route/error_batch.py`
  - [ ] 实现 POST /import (批量导入)
  - [ ] 实现 POST /export (批量导出)
  - [ ] 实现 GET /import/template (下载导入模板)
- [ ] 创建 `app/api/v1/platform_errors/route/routes.py`
  - [ ] 注册所有路由
- [ ] 在 `app/api/v1/__init__.py` 中注册blueprint
- [ ] 使用Postman测试所有API接口

### 阶段四：前端基础设施（第8-9步）

#### 第8步：类型定义和API接口
- [ ] 创建 `frontend/src/types/entities/platformError.ts`
  - [ ] 定义 PlatformErrorCategory 接口
  - [ ] 定义 PlatformError 接口
  - [ ] 定义 ErrorStatistics 接口
  - [ ] 定义 QueryParams 接口
  - [ ] 定义 ImportResult 接口
- [ ] 创建 `frontend/src/api/platformErrorApi.ts`
  - [ ] 实现所有API接口调用
  - [ ] 使用RTK Query定义endpoints

#### 第9步：Redux状态管理
- [ ] 创建 `frontend/src/store/slices/platformErrorSlice.ts`
  - [ ] 定义初始状态
  - [ ] 定义reducers
  - [ ] 定义async thunks
  - [ ] 导出actions和selectors
- [ ] 在 `frontend/src/store/store.ts` 中注册reducer

### 阶段五：前端组件实现（第10-14步）

#### 第10步：统计面板和搜索筛选组件
- [ ] 创建组件目录 `frontend/src/pages/SystemSettings/PlatformErrorManagement/`
- [ ] 创建 `components/index.ts`
- [ ] 创建 `components/StatisticsPanel.tsx`
  - [ ] 使用Card和Statistic组件
  - [ ] 展示总数和分类统计
  - [ ] 支持加载状态
- [ ] 创建 `components/SearchFilterSection.tsx`
  - [ ] 类别下拉选择器
  - [ ] 错误码编号搜索框
  - [ ] 错误码描述搜索框
  - [ ] 查询和重置按钮

#### 第11步：错误码表格组件
- [ ] 创建 `components/PlatformErrorTable.tsx`
  - [ ] 定义表格列
  - [ ] 类别列使用Badge展示不同颜色
  - [ ] 实现操作列（查看、编辑按钮）
  - [ ] 支持分页
  - [ ] 支持加载状态
  - [ ] 处理空数据状态

#### 第12步：详情和编辑弹窗
- [ ] 创建 `components/PlatformErrorDetailModal.tsx`
  - [ ] 展示完整的错误码信息
  - [ ] 只读展示
  - [ ] 关闭按钮
- [ ] 创建 `components/PlatformErrorEditModal.tsx`
  - [ ] 基础信息区（只读）
  - [ ] 可编辑区（描述、详细说明、处理建议）
  - [ ] 表单验证
  - [ ] 取消/保存按钮
  - [ ] 保存成功后刷新列表

#### 第13步：批量导入导出弹窗
- [ ] 创建 `components/BatchImportModal.tsx`
  - [ ] 模板下载区
  - [ ] 文件上传组件（支持拖拽）
  - [ ] 导入预览表格
  - [ ] 验证结果展示
  - [ ] 取消/导入按钮
  - [ ] 导入进度提示
- [ ] 创建 `components/BatchExportModal.tsx`
  - [ ] 类别筛选复选框组
  - [ ] 字段选择复选框组
  - [ ] 取消/导出按钮
  - [ ] 导出进度提示

#### 第14步：主页面组件
- [ ] 创建 `PlatformErrorManagementPage.tsx`
  - [ ] 页面标题和描述
  - [ ] 操作按钮（刷新、导入、导出）
  - [ ] 组合所有子组件
  - [ ] 处理页面级交互逻辑
- [ ] 创建 `index.tsx` 导出主组件
- [ ] 在路由配置中添加页面路由
- [ ] 在侧边栏菜单中添加导航项

### 阶段六：测试和优化（第15-17步）

#### 第15步：集成测试
- [ ] 测试完整的错误码管理流程：
  - [ ] 查看错误码列表
  - [ ] 使用筛选和搜索功能
  - [ ] 查看错误码详情
  - [ ] 编辑错误码信息
  - [ ] 批量导入错误码
  - [ ] 批量导出错误码
  - [ ] 查看统计信息
- [ ] 测试边界条件和异常情况
- [ ] 测试权限控制（如果已实现）

#### 第16步：前端样式优化和响应式适配
- [ ] 优化各组件的样式和布局
- [ ] 确保响应式设计适配不同屏幕尺寸
- [ ] 优化加载状态和错误提示
- [ ] 优化用户交互体验
- [ ] 添加必要的过渡动画

#### 第17步：性能优化和代码审查
- [ ] 前端性能优化：
  - [ ] 检查不必要的重渲染
  - [ ] 优化API调用
  - [ ] 添加必要的缓存
- [ ] 后端性能优化：
  - [ ] 检查数据库查询性能
  - [ ] 添加必要的索引
  - [ ] 优化批量操作性能
- [ ] 代码审查和重构
- [ ] 更新相关文档
- [ ] 运行 `npm run build` 确保无错误

### 阶段七：文档和发布（第18步）

#### 第18步：文档完善和功能发布
- [ ] 编写用户使用文档
- [ ] 更新API文档
- [ ] 准备演示数据
- [ ] 与用户确认功能完整性
- [ ] 准备发布说明

## 6. 技术实现要点

### 6.1 后端要点

1. **数据验证**
   - 错误码编号格式验证（整数或十六进制）
   - 类别代码合法性验证
   - 重复错误码检查

2. **批量导入处理**
   - 使用openpyxl库读取Excel
   - 逐行验证数据
   - 已存在的错误码进行更新
   - 返回详细的导入结果

3. **批量导出处理**
   - 根据筛选条件导出
   - Excel格式化（标题行加粗、背景色）
   - 支持大量数据导出

4. **异常处理**
   - 统一的错误响应格式
   - 详细的错误日志记录
   - 数据库事务回滚

### 6.2 前端要点

1. **状态管理**
   - 使用Redux管理全局状态
   - 使用RTK Query管理API调用和缓存
   - 合理的状态更新策略

2. **用户体验**
   - 操作反馈（Loading、Success、Error）
   - 确认对话框（删除、导入覆盖等）
   - 友好的错误提示
   - 合理的默认值

3. **性能优化**
   - 表格虚拟滚动（如果数据量大）
   - 防抖搜索
   - 懒加载和按需渲染
   - 合理的缓存策略

4. **代码规范**
   - 遵循项目现有的代码风格
   - 组件职责单一
   - 合理的代码注释
   - 类型安全

## 7. 注意事项

### 7.1 开发规范
- 所有文件添加文件头注释（版权信息、作者、日期）
- 代码注释使用英文
- 避免过度注释
- 遵循pigeon_web现有的代码架构和命名规范

### 7.2 数据库相关
- 不创建迁移脚本，直接修改初始化脚本
- 修改schema时同步更新mock_data
- 修改schema时同步更新pigeon_web.sql

### 7.3 测试相关
- 修改代码后必须测试
- 确保前端build无错误
- 用户亲自测试确认后才能提交代码

### 7.4 Git提交规范
- 提交类型：feat (新功能)
- Scope：platform-errors
- 提交信息示例：`feat(platform-errors): implement error list API`
- 每个阶段完成后提交一次代码

## 8. 验收标准

### 8.1 功能验收
- [ ] 错误码列表展示完整，支持分页
- [ ] 分类筛选功能正常工作
- [ ] 搜索功能准确，支持模糊匹配
- [ ] 错误码详情查看正常
- [ ] 错误码编辑功能正常，保存成功
- [ ] 批量导入功能正常，支持Excel格式
- [ ] 批量导出功能正常，Excel格式正确
- [ ] 统计信息准确展示
- [ ] 所有操作都有适当的反馈提示

### 8.2 性能验收
- [ ] 列表加载时间 < 3秒
- [ ] 搜索响应时间 < 1秒
- [ ] 编辑保存响应时间 < 2秒
- [ ] 批量导入处理及时，有进度提示
- [ ] 支持展示100+条错误码

### 8.3 界面验收
- [ ] 界面布局清晰，符合UI设计方案
- [ ] 类别标识清晰，不同类别有不同颜色
- [ ] 操作按钮位置合理，便于使用
- [ ] 响应式设计，适配不同屏幕尺寸
- [ ] 无明显的样式问题

### 8.4 代码质量验收
- [ ] 代码符合项目规范
- [ ] 无明显的代码异味
- [ ] 关键逻辑有注释
- [ ] 前端build无错误和警告
- [ ] 后端无SQL注入和XSS漏洞

## 9. 风险和依赖

### 9.1 风险
1. **数据量风险**: 如果错误码数量非常大（1000+），需要考虑性能优化
2. **格式兼容性**: Excel导入导出需要处理各种格式异常
3. **并发冲突**: 多人同时编辑同一错误码可能导致冲突

### 9.2 依赖
1. **后端依赖**:
   - openpyxl: Excel处理
   - SQLAlchemy: ORM
   - Flask-RESTful: API框架

2. **前端依赖**:
   - Ant Design: UI组件库
   - Redux Toolkit: 状态管理
   - RTK Query: API调用

3. **外部依赖**:
   - 数据库支持全文搜索索引
   - 文件系统支持临时文件存储

## 10. 后续优化方向

1. **功能增强**:
   - 错误码版本管理
   - 操作日志记录
   - 权限细分控制
   - 错误码使用统计

2. **性能优化**:
   - 引入缓存机制
   - 批量操作异步处理
   - 导出任务队列化

3. **用户体验**:
   - 快捷键支持
   - 批量编辑功能
   - 自定义列显示
   - 高级搜索功能

---

**文档结束**
