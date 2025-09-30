# FEAT-6-7 敏感词库管理功能开发计划

## 项目概述

基于pigeon_web现有架构，开发敏感词库管理功能，包括全局敏感词库管理、自定义敏感词库管理和敏感词库应用管理三个核心模块。

## 技术架构

### 后端架构（Flask）
- **Models层**：数据模型定义，使用SQLAlchemy ORM
- **Services层**：业务逻辑封装，继承BaseService
- **Routes层**：API路由处理，使用Flask-RESTful
- **Schema层**：数据验证和序列化，使用Marshmallow

### 前端架构（React + TypeScript）
- **Pages层**：页面主体组件
- **Components层**：可复用UI组件
- **Store层**：Redux状态管理
- **API层**：接口调用封装

## 开发任务分解

### 第一阶段：数据库设计与模型层开发

#### 1.1 数据库表设计
**涉及文件：**
- `pigeon_web/sql/modules/sensitive_words.sql`
- `pigeon_web/sql/mock_data/sensitive_words.sql`
- `pigeon_web/sql/pigeon_web.sql`

**数据表：**
```sql
-- 全局敏感词库表
CREATE TABLE mgmt.global_sensitive_word_libraries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200) NOT NULL UNIQUE,
    description TEXT,
    word_count INTEGER DEFAULT 0,
    is_enabled BOOLEAN DEFAULT true,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    created_by INTEGER REFERENCES mgmt.admin_users(id),
    updated_by INTEGER REFERENCES mgmt.admin_users(id),
    deleted_by INTEGER REFERENCES mgmt.admin_users(id)
);

-- 自定义敏感词库表
CREATE TABLE mgmt.custom_sensitive_word_libraries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200) NOT NULL,
    description TEXT,
    word_count INTEGER DEFAULT 0,
    is_enabled BOOLEAN DEFAULT true,
    is_deleted BOOLEAN DEFAULT false,
    enterprise_id UUID REFERENCES mgmt.enterprises(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    created_by INTEGER REFERENCES mgmt.admin_users(id),
    updated_by INTEGER REFERENCES mgmt.admin_users(id),
    deleted_by INTEGER REFERENCES mgmt.admin_users(id),
    UNIQUE(name, enterprise_id)
);

-- 全局敏感词汇表
CREATE TABLE mgmt.global_sensitive_words (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    word VARCHAR(500) NOT NULL,
    library_id UUID NOT NULL REFERENCES mgmt.global_sensitive_word_libraries(id) ON DELETE CASCADE,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    created_by INTEGER REFERENCES mgmt.admin_users(id),
    deleted_by INTEGER REFERENCES mgmt.admin_users(id),
    UNIQUE(word, library_id)
);

-- 自定义敏感词汇表
CREATE TABLE mgmt.custom_sensitive_words (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    word VARCHAR(500) NOT NULL,
    library_id UUID NOT NULL REFERENCES mgmt.custom_sensitive_word_libraries(id) ON DELETE CASCADE,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    created_by INTEGER REFERENCES mgmt.admin_users(id),
    deleted_by INTEGER REFERENCES mgmt.admin_users(id),
    UNIQUE(word, library_id)
);

-- 自定义敏感词库应用配置表（注意：全局词库不需要应用配置，自动全局生效）
CREATE TABLE mgmt.custom_sensitive_word_applications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    library_id UUID NOT NULL REFERENCES mgmt.custom_sensitive_word_libraries(id) ON DELETE CASCADE,
    sending_account_id VARCHAR(255) NOT NULL REFERENCES mgmt.accounts(account_id) ON DELETE CASCADE,
    is_deleted BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    created_by INTEGER REFERENCES mgmt.admin_users(id),
    deleted_by INTEGER REFERENCES mgmt.admin_users(id),
    UNIQUE(library_id, sending_account_id)
);

-- 敏感词批量导入历史表
CREATE TABLE mgmt.sensitive_word_import_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    library_id UUID NOT NULL,
    library_type VARCHAR(20) NOT NULL CHECK (library_type IN ('global', 'custom')),
    file_name VARCHAR(500) NOT NULL,
    total_count INTEGER NOT NULL,
    success_count INTEGER NOT NULL,
    failed_count INTEGER NOT NULL,
    error_details JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by INTEGER REFERENCES mgmt.admin_users(id)
);
```

#### 1.2 数据模型开发
**涉及文件：**
- `pigeon_web/app/models/sensitive_words/__init__.py`
- `pigeon_web/app/models/sensitive_words/global_library.py`
- `pigeon_web/app/models/sensitive_words/custom_library.py`
- `pigeon_web/app/models/sensitive_words/sensitive_word.py`
- `pigeon_web/app/models/sensitive_words/application_config.py`

**核心模型类：**
```python
# GlobalSensitiveWordLibrary - 全局敏感词库模型
# CustomSensitiveWordLibrary - 自定义敏感词库模型
# GlobalSensitiveWord - 全局敏感词汇模型
# CustomSensitiveWord - 自定义敏感词汇模型
# CustomSensitiveWordApplication - 自定义词库应用配置模型
# SensitiveWordImportHistory - 导入历史记录模型
```

### 第二阶段：业务服务层开发

#### 2.1 业务服务类
**涉及文件：**
- `pigeon_web/app/services/sensitive_words/__init__.py`
- `pigeon_web/app/services/sensitive_words/global_library_service.py`
- `pigeon_web/app/services/sensitive_words/custom_library_service.py`
- `pigeon_web/app/services/sensitive_words/word_management_service.py`
- `pigeon_web/app/services/sensitive_words/application_config_service.py`

**核心功能：**
- 词库CRUD操作
- 敏感词批量导入导出
- 应用配置管理
- 敏感词检测服务

### 第三阶段：API路由层开发

#### 3.1 API路由结构
**涉及文件：**
- `pigeon_web/app/api/v1/sensitive_words/__init__.py`
- `pigeon_web/app/api/v1/sensitive_words/route/__init__.py`
- `pigeon_web/app/api/v1/sensitive_words/route/global_libraries.py`
- `pigeon_web/app/api/v1/sensitive_words/route/custom_libraries.py`
- `pigeon_web/app/api/v1/sensitive_words/route/word_management.py`
- `pigeon_web/app/api/v1/sensitive_words/route/application_config.py`
- `pigeon_web/app/api/v1/sensitive_words/route/import_export.py`
- `pigeon_web/app/api/v1/sensitive_words/route/routes.py`

**API端点设计：**
```
# 全局敏感词库管理
GET    /api/v1/sensitive-words/global-libraries          # 获取全局词库列表
POST   /api/v1/sensitive-words/global-libraries          # 创建全局词库
GET    /api/v1/sensitive-words/global-libraries/{id}     # 获取全局词库详情
PUT    /api/v1/sensitive-words/global-libraries/{id}     # 更新全局词库
DELETE /api/v1/sensitive-words/global-libraries/{id}     # 删除全局词库

# 自定义敏感词库管理
GET    /api/v1/sensitive-words/custom-libraries          # 获取自定义词库列表
POST   /api/v1/sensitive-words/custom-libraries          # 创建自定义词库
GET    /api/v1/sensitive-words/custom-libraries/{id}     # 获取自定义词库详情
PUT    /api/v1/sensitive-words/custom-libraries/{id}     # 更新自定义词库
DELETE /api/v1/sensitive-words/custom-libraries/{id}     # 删除自定义词库

# 全局敏感词管理
GET    /api/v1/sensitive-words/global-libraries/{id}/words      # 获取全局词库中的敏感词
POST   /api/v1/sensitive-words/global-libraries/{id}/words      # 添加全局敏感词
PUT    /api/v1/sensitive-words/global-words/{id}                # 更新全局敏感词
DELETE /api/v1/sensitive-words/global-words/{id}                # 删除全局敏感词

# 自定义敏感词管理
GET    /api/v1/sensitive-words/custom-libraries/{id}/words      # 获取自定义词库中的敏感词
POST   /api/v1/sensitive-words/custom-libraries/{id}/words      # 添加自定义敏感词
PUT    /api/v1/sensitive-words/custom-words/{id}                # 更新自定义敏感词
DELETE /api/v1/sensitive-words/custom-words/{id}                # 删除自定义敏感词

# 导入导出
POST   /api/v1/sensitive-words/global-libraries/{id}/import     # 导入全局敏感词
GET    /api/v1/sensitive-words/global-libraries/{id}/export     # 导出全局敏感词
POST   /api/v1/sensitive-words/custom-libraries/{id}/import     # 导入自定义敏感词
GET    /api/v1/sensitive-words/custom-libraries/{id}/export     # 导出自定义敏感词

# 导入历史
GET    /api/v1/sensitive-words/import-history                   # 获取导入历史列表
GET    /api/v1/sensitive-words/import-history/{id}              # 获取导入历史详情

# 自定义词库应用配置管理（注意：全局词库无需配置，自动全局生效）
GET    /api/v1/sensitive-words/application-configs              # 获取应用配置列表
POST   /api/v1/sensitive-words/application-configs              # 创建应用配置
DELETE /api/v1/sensitive-words/application-configs/{id}         # 删除应用配置
```

#### 3.2 数据验证Schema
**涉及文件：**
- `pigeon_web/app/api/v1/sensitive_words/schema/__init__.py`
- `pigeon_web/app/api/v1/sensitive_words/schema/library_schema.py`
- `pigeon_web/app/api/v1/sensitive_words/schema/word_schema.py`
- `pigeon_web/app/api/v1/sensitive_words/schema/application_schema.py`

### 第四阶段：前端页面开发

#### 4.1 页面组件结构
**涉及文件：**
- `pigeon_web/frontend/src/pages/SensitiveWordManagement/index.tsx`
- `pigeon_web/frontend/src/pages/SensitiveWordManagement/SensitiveWordPage.tsx`

#### 4.2 组件开发
**涉及目录：**
`pigeon_web/frontend/src/pages/SensitiveWordManagement/components/`

**核心组件：**
- `GlobalLibraryPanel.tsx` - 全局词库管理面板
- `CustomLibraryPanel.tsx` - 自定义词库管理面板
- `ApplicationConfigPanel.tsx` - 应用配置管理面板
- `LibraryFormModal.tsx` - 词库创建/编辑弹窗
- `WordManagementModal.tsx` - 词条管理弹窗
- `ImportWordsModal.tsx` - 批量导入弹窗
- `ApplicationConfigModal.tsx` - 应用配置弹窗
- `SearchFilterSection.tsx` - 搜索筛选组件
- `LibraryTable.tsx` - 词库列表表格
- `WordTable.tsx` - 敏感词列表表格

#### 4.3 状态管理
**涉及文件：**
- `pigeon_web/frontend/src/store/slices/sensitiveWordSlice.ts`

**状态结构：**
```typescript
interface SensitiveWordState {
  globalLibraries: GlobalLibrary[];
  customLibraries: CustomLibrary[];
  applicationConfigs: ApplicationConfig[];
  currentWords: SensitiveWord[];
  modals: {
    isLibraryModalOpen: boolean;
    isWordModalOpen: boolean;
    isImportModalOpen: boolean;
    isApplicationConfigModalOpen: boolean;
    selectedLibrary: Library | null;
    selectedWord: SensitiveWord | null;
  };
  filters: {
    libraryName: string;
    creator: string;
    status: string;
  };
  loading: {
    libraries: boolean;
    words: boolean;
    configs: boolean;
  };
}
```

#### 4.4 API接口封装
**涉及文件：**
- `pigeon_web/frontend/src/api/sensitiveWordsApi.ts`

**RTK Query API设计：**
```typescript
export const sensitiveWordsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // 全局词库管理
    getGlobalLibraries: builder.query<GlobalLibraryListResponse, GlobalLibraryListParams>({
      query: (params) => ({
        url: '/api/v1/sensitive-words/global-libraries',
        params,
      }),
      providesTags: ['GlobalLibrary'],
    }),

    createGlobalLibrary: builder.mutation<GlobalLibrary, CreateGlobalLibraryRequest>({
      query: (data) => ({
        url: '/api/v1/sensitive-words/global-libraries',
        method: 'POST',
        body: data,
      }),
      invalidatesTags: ['GlobalLibrary'],
    }),

    // 自定义词库管理
    getCustomLibraries: builder.query<CustomLibraryListResponse, CustomLibraryListParams>({
      query: (params) => ({
        url: '/api/v1/sensitive-words/custom-libraries',
        params,
      }),
      providesTags: ['CustomLibrary'],
    }),

    // 敏感词管理
    getGlobalWords: builder.query<WordListResponse, GetWordsParams>({
      query: ({ libraryId, ...params }) => ({
        url: `/api/v1/sensitive-words/global-libraries/${libraryId}/words`,
        params,
      }),
      providesTags: ['GlobalWord'],
    }),

    getCustomWords: builder.query<WordListResponse, GetWordsParams>({
      query: ({ libraryId, ...params }) => ({
        url: `/api/v1/sensitive-words/custom-libraries/${libraryId}/words`,
        params,
      }),
      providesTags: ['CustomWord'],
    }),

    // 导入导出
    importGlobalWords: builder.mutation<ImportResponse, ImportWordsRequest>({
      query: ({ libraryId, file }) => {
        const formData = new FormData();
        formData.append('file', file);
        return {
          url: `/api/v1/sensitive-words/global-libraries/${libraryId}/import`,
          method: 'POST',
          body: formData,
        };
      },
      invalidatesTags: ['GlobalWord', 'GlobalLibrary'],
    }),

    // 导入历史
    getImportHistory: builder.query<ImportHistoryListResponse, ImportHistoryParams>({
      query: (params) => ({
        url: '/api/v1/sensitive-words/import-history',
        params,
      }),
      providesTags: ['ImportHistory'],
    }),

    // 应用配置管理
    getApplicationConfigs: builder.query<ApplicationConfigListResponse, ApplicationConfigParams>({
      query: (params) => ({
        url: '/api/v1/sensitive-words/application-configs',
        params,
      }),
      providesTags: ['ApplicationConfig'],
    }),
  }),
  overrideExisting: false,
});

export const {
  useGetGlobalLibrariesQuery,
  useCreateGlobalLibraryMutation,
  useGetCustomLibrariesQuery,
  useGetGlobalWordsQuery,
  useGetCustomWordsQuery,
  useImportGlobalWordsMutation,
  useGetImportHistoryQuery,
  useGetApplicationConfigsQuery,
  // ... 其他hooks
} = sensitiveWordsApi;
```

### 第五阶段：路由配置与集成

#### 5.1 后端路由注册
**涉及文件：**
- `pigeon_web/app/api/v1/__init__.py` （添加敏感词管理路由）

#### 5.2 前端路由配置
**涉及文件：**
- `pigeon_web/frontend/src/router/index.tsx` （添加敏感词管理页面路由）

#### 5.3 菜单配置
**涉及文件：**
- 相应的菜单配置文件（添加敏感词库管理菜单项）

### 第六阶段：测试与优化

#### 6.1 单元测试
**涉及文件：**
- `pigeon_web/tests/services/test_sensitive_word_services.py`
- `pigeon_web/tests/api/test_sensitive_word_api.py`

#### 6.2 前端组件测试
**涉及目录：**
- `pigeon_web/frontend/src/pages/SensitiveWordManagement/__tests__/`

## 开发顺序建议

### 第1周：数据库与模型层
1. 设计并创建数据库表
2. 开发数据模型类
3. 添加模拟数据

### 第2周：业务服务层
1. 开发全局词库服务
2. 开发自定义词库服务
3. 开发敏感词管理服务
4. 开发应用配置服务

### 第3周：API路由层
1. 开发API路由处理器
2. 创建数据验证Schema
3. 测试API接口功能

### 第4周：前端基础组件
1. 创建页面主体结构
2. 开发基础UI组件
3. 实现状态管理逻辑

### 第5周：前端交互功能
1. 实现词库管理功能
2. 实现敏感词管理功能
3. 实现导入导出功能

### 第6周：应用配置与集成
1. 实现应用配置功能
2. 路由集成和菜单配置
3. 系统集成测试

### 第7周：测试与优化
1. 完善单元测试
2. 进行集成测试
3. 性能优化和用户体验改进

## 关键技术要点

### 1. 数据库设计
- 使用UUID作为主键，created_by/updated_by/deleted_by使用INTEGER引用admin_users
- 全局词库与自定义词库完全分离，各自使用独立的词汇表
- 严格的外键约束确保数据一致性，避免孤立行
- 支持软删除和完整的审计日志（is_deleted, deleted_at, deleted_by）
- 导入历史表记录所有批量操作

### 2. 业务逻辑
- 继承现有BaseService模式
- 支持批量导入导出Excel格式
- 实现敏感词精确匹配算法
- 缓存常用词库提升检测性能

### 3. API设计
- 遵循RESTful设计原则
- 使用Marshmallow进行数据验证
- 支持分页、搜索、筛选功能
- 统一的错误处理和响应格式
- 全局词库与自定义词库API完全分离

### 4. 前端开发
- 采用Ant Design组件库
- 使用TypeScript确保类型安全
- Redux管理复杂状态逻辑
- RTK Query统一API调用和缓存管理
- 响应式设计支持多设备

### 5. 性能优化
- 数据库查询优化
- 前端虚拟滚动处理大量数据
- API接口缓存策略
- 异步处理导入导出操作

## 风险控制

### 架构设计风险解决方案
- **外键类型一致性**：已修正created_by等字段为INTEGER类型，与admin_users.id一致
- **账号表引用正确性**：应用配置表使用VARCHAR引用accounts.account_id，而非不存在的integer id
- **数据孤立行问题**：分离全局和自定义敏感词表，使用严格的外键约束和CASCADE删除
- **全局词库应用逻辑**：移除全局词库的应用配置功能，确保自动全局生效的业务逻辑
- **审计和软删除**：在所有表中正确实现软删除和审计字段
- **导入历史追踪**：设计专门的导入历史表满足审计要求
- **前端API一致性**：采用RTK Query模式保持与现有代码风格一致

### 技术风险
- **数据库性能**：大量敏感词可能影响检索性能
  - 解决方案：建立适当索引，使用缓存，考虑分区表

- **内存占用**：全量加载敏感词可能占用大量内存
  - 解决方案：按需加载，使用分页，实现智能缓存

### 业务风险
- **数据一致性**：全局词库与自定义词库的应用优先级
  - 解决方案：明确业务规则，实现严格的数据校验

- **权限控制**：不同角色对词库的操作权限
  - 解决方案：继承现有权限系统，实现细粒度权限控制

## 验收标准

### 功能验收
1. ✅ 全局敏感词库CRUD操作（自动全局生效）
2. ✅ 自定义敏感词库CRUD操作
3. ✅ 敏感词管理（增删改查），支持全局和自定义分离
4. ✅ Excel批量导入导出功能
5. ✅ 自定义词库应用配置管理（全局词库无需配置）
6. ✅ 导入历史记录和查询功能
7. ✅ 搜索和筛选功能
8. ✅ 分页显示支持
9. ✅ 软删除和审计日志功能

### 性能验收
1. ✅ 词库列表查询响应时间 < 200ms
2. ✅ 敏感词搜索响应时间 < 100ms
3. ✅ 支持单个词库10万敏感词
4. ✅ 批量导入1万词汇时间 < 30秒

### 用户体验验收
1. ✅ 界面操作直观友好
2. ✅ 错误提示清晰准确
3. ✅ 支持批量操作提升效率
4. ✅ 响应式设计适配多设备

## 部署清单

### 数据库变更
- [ ] 执行敏感词管理数据表创建脚本
- [ ] 添加初始化数据和权限配置
- [ ] 更新数据库版本记录

### 后端部署
- [ ] 部署新增的模型、服务、API模块
- [ ] 更新路由配置
- [ ] 重启应用服务

### 前端部署
- [ ] 构建包含敏感词管理功能的前端资源
- [ ] 更新路由和菜单配置
- [ ] 部署到生产环境

### 配置更新
- [ ] 更新权限配置
- [ ] 添加相关系统配置项
- [ ] 更新监控和日志配置

---

## 更新记录

### v2.0 - 架构设计修正版
**根据技术review反馈修正的关键问题：**

1. **外键类型修正**：created_by/updated_by/deleted_by字段改为INTEGER类型，正确引用admin_users.id
2. **账号表引用修正**：应用配置表使用VARCHAR(255)引用accounts.account_id主键
3. **数据隔离设计**：全局和自定义敏感词使用独立表，避免孤立行和数据混乱
4. **业务逻辑澄清**：移除全局词库的应用配置功能，确保全局自动生效
5. **审计功能完善**：所有表添加完整的软删除和审计字段
6. **导入历史追踪**：新增import_history表满足批量操作审计需求
7. **前端架构一致**：采用RTK Query模式保持代码风格统一

**感谢技术review提供的宝贵建议，所有identified risks已在此版本中得到解决。**

