# FEAT-1-1 企业账号管理功能开发计划

## 📋 项目概述

**需求编号**: FEAT-1-1
**功能名称**: 企业账号管理
**优先级**: P0 (最高)
**开发周期**: 预计 8-10 个工作日
**创建时间**: 2025-01-23

### 功能概述
基于现有pigeon_web系统架构，扩展企业账号管理功能，为平台管理员提供完整的企业客户账号生命周期管理能力。

## 🏗️ 现有架构分析

### 已具备的基础架构
✅ **数据库层**:
- `enterprises` 表 - 企业基本信息管理
- `accounts` 表 - 发送账号管理（已有enterprise_id关联）
- `admin_users` 表 - 管理员用户系统
- 完整的RBAC权限管理系统

✅ **后端架构**:
- Flask + SQLAlchemy + Flask-RESTful
- 三层架构：API层 -> Service层 -> Model层
- 统一的响应格式和错误处理
- JWT认证和权限验证装饰器

✅ **前端架构**:
- React 18 + TypeScript + RTK Query
- Ant Design 组件库
- Redux Toolkit 状态管理
- 模块化组件设计

### 需要扩展的部分
🔧 **数据库Schema扩展**
🔧 **API端点开发**
🔧 **前端管理界面**

## 📊 数据库设计方案

### 1. enterprises表扩展

需要直接修改 `pigeon_web/sql/modules/enterprises.sql` 初始化脚本，在CREATE TABLE语句中新增以下字段：

```sql
-- 在现有CREATE TABLE enterprises语句中新增字段
-- 企业账号管理字段
admin_id INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,  -- 归属管理员
account_code VARCHAR(100) UNIQUE,                               -- 企业账号代码
login_password VARCHAR(255),                                    -- 登录密码
account_status VARCHAR(20) DEFAULT 'enabled' NOT NULL           -- 账号状态(enabled/disabled)
    CHECK (account_status IN ('enabled', 'disabled')),
desensitization_strategy VARCHAR(30) DEFAULT 'plain' NOT NULL   -- 脱敏策略
    CHECK (desensitization_strategy IN ('plain', 'phone_only', 'phone_content'));

-- 同时新增对应的索引
CREATE INDEX IF NOT EXISTS idx_enterprises_admin_id ON enterprises(admin_id);
CREATE INDEX IF NOT EXISTS idx_enterprises_account_code ON enterprises(account_code);
CREATE INDEX IF NOT EXISTS idx_enterprises_account_status ON enterprises(account_status);
CREATE INDEX IF NOT EXISTS idx_enterprises_desensitization ON enterprises(desensitization_strategy);
CREATE INDEX IF NOT EXISTS idx_enterprises_admin_status ON enterprises(admin_id, account_status);
```

### 2. 企业账号与发送账号绑定记录表（可选）

如需要详细的绑定历史记录，可新增：

```sql
-- 企业账号发送账号绑定记录表
CREATE TABLE IF NOT EXISTS enterprise_account_bindings (
    id SERIAL PRIMARY KEY,
    enterprise_id UUID NOT NULL REFERENCES enterprises(id) ON DELETE CASCADE,
    account_id VARCHAR(255) NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    bound_by INTEGER REFERENCES admin_users(id) ON DELETE SET NULL,
    bound_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    unbound_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,

    UNIQUE(enterprise_id, account_id, is_active)
);

CREATE INDEX IF NOT EXISTS idx_enterprise_bindings_enterprise ON enterprise_account_bindings(enterprise_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_bindings_account ON enterprise_account_bindings(account_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_bindings_active ON enterprise_account_bindings(is_active);
```

### 3. Mock数据扩展

需要修改 `pigeon_web/sql/mock_data/enterprises.sql` 文件，在INSERT语句中包含新增字段：

```sql
-- 修改现有的INSERT语句，包含新增字段
INSERT INTO enterprises (
    name, legal_name, primary_email, admin_id, account_code,
    login_password, account_status, desensitization_strategy,
    -- 其他现有字段...
) VALUES
('测试_企业账号', '测试企业有限公司', 'test@enterprise.com', 1, 'ceshi_001',
 'hashed_password', 'enabled', 'phone_only'),
('MACO测试账号1', 'MACO International Ltd.', 'maco@test.com', 2, 'client_MACO',
 'hashed_password', 'enabled', 'plain'),
('KS LINK Telecomm', 'KS LINK通信有限公司', 'kslink@telecomm.com', 3, 'KSLINK123',
 'hashed_password', 'enabled', 'phone_content');

-- 同时需要更新 pigeon_web/sql/pigeon_web.sql 中的对应数据
```

## 🔧 后端API开发计划

### 1. 模型层扩展 (Model Layer)

**文件**: `app/models/customers/enterprise.py`

```python
class DesensitizationStrategy(Enum):
    """脱敏策略枚举"""
    PLAIN = 'plain'              # 明文显示
    PHONE_ONLY = 'phone_only'    # 号码脱敏
    PHONE_CONTENT = 'phone_content'  # 号码+内容脱敏

class AccountStatus(Enum):
    """企业账号状态枚举"""
    ENABLED = 'enabled'   # 开启
    DISABLED = 'disabled' # 关闭

# 在Enterprise类中新增字段和方法
class Enterprise(db.Model, TimestampMixin, I18nMixin):
    # 新增字段
    admin_id = db.Column(db.Integer, db.ForeignKey('admin_users.id'),
                        comment='归属管理员ID')
    account_code = db.Column(db.String(100), unique=True,
                           comment='企业账号代码')
    login_password = db.Column(db.String(255), comment='登录密码')
    account_status = db.Column(db.Enum(AccountStatus, values_callable=lambda obj: [e.value for e in obj]),
                              default=AccountStatus.ENABLED, nullable=False)
    desensitization_strategy = db.Column(db.Enum(DesensitizationStrategy, values_callable=lambda obj: [e.value for e in obj]),
                                       default=DesensitizationStrategy.PLAIN, nullable=False)

    # 关系
    admin_user = db.relationship('AdminUser', foreign_keys=[admin_id])

    # 新增方法
    def set_password(self, password: str):
        """设置密码（加密存储）"""
        pass

    def check_password(self, password: str) -> bool:
        """验证密码"""
        pass

    def get_bound_accounts(self):
        """获取绑定的发送账号"""
        pass
```

### 2. 服务层扩展 (Service Layer)

**文件**: `app/services/enterprises/enterprise_service.py`

新增方法：
- `get_enterprises_by_admin(admin_id)` - 按管理员筛选企业账号
- `bind_sending_accounts(enterprise_id, account_ids)` - 绑定发送账号
- `unbind_sending_account(enterprise_id, account_id)` - 解绑发送账号
- `get_bound_accounts(enterprise_id)` - 获取已绑定的发送账号
- `update_password(enterprise_id, new_password)` - 修改密码
- `toggle_account_status(enterprise_id)` - 切换账号状态

### 3. API层开发 (API Layer)

#### 3.1 路由规划

基于现有 `/api/v1/enterprises` 路径扩展：

```python
# app/api/v1/enterprises/route/account_management.py
class EnterpriseAccountManagementResource(Resource):
    @login_required
    @permission_required('enterprise_account_read')
    def get(self):
        """企业账号列表查询（支持管理员筛选）"""
        pass

    @login_required
    @permission_required('enterprise_account_create')
    def post(self):
        """新增企业账号"""
        pass

class EnterpriseAccountDetailResource(Resource):
    @login_required
    @permission_required('enterprise_account_read')
    def get(self, enterprise_id):
        """企业账号详情"""
        pass

    @login_required
    @permission_required('enterprise_account_update')
    def put(self, enterprise_id):
        """修改企业账号"""
        pass

    @login_required
    @permission_required('enterprise_account_delete')
    def delete(self, enterprise_id):
        """删除企业账号"""
        pass

class EnterpriseAccountBindingResource(Resource):
    @login_required
    @permission_required('enterprise_account_bind')
    def get(self, enterprise_id):
        """获取绑定的发送账号列表"""
        pass

    @login_required
    @permission_required('enterprise_account_bind')
    def post(self, enterprise_id):
        """绑定发送账号"""
        pass

    @login_required
    @permission_required('enterprise_account_bind')
    def delete(self, enterprise_id, account_id):
        """解绑发送账号"""
        pass

class EnterpriseAccountPasswordResource(Resource):
    @login_required
    @permission_required('enterprise_account_password')
    def put(self, enterprise_id):
        """修改企业账号密码"""
        pass
```

#### 3.2 API端点列表

| 方法 | 路径 | 功能 | 权限 |
|------|------|------|------|
| GET | `/api/v1/enterprises/accounts` | 企业账号列表 | enterprise_account_read |
| POST | `/api/v1/enterprises/accounts` | 新增企业账号 | enterprise_account_create |
| GET | `/api/v1/enterprises/accounts/{id}` | 企业账号详情 | enterprise_account_read |
| PUT | `/api/v1/enterprises/accounts/{id}` | 修改企业账号 | enterprise_account_update |
| DELETE | `/api/v1/enterprises/accounts/{id}` | 删除企业账号 | enterprise_account_delete |
| GET | `/api/v1/enterprises/accounts/{id}/bindings` | 获取绑定的发送账号 | enterprise_account_bind |
| POST | `/api/v1/enterprises/accounts/{id}/bindings` | 绑定发送账号 | enterprise_account_bind |
| DELETE | `/api/v1/enterprises/accounts/{id}/bindings/{account_id}` | 解绑发送账号 | enterprise_account_bind |
| PUT | `/api/v1/enterprises/accounts/{id}/password` | 修改密码 | enterprise_account_password |

#### 3.3 Schema定义

**文件**: `app/api/v1/enterprises/schema/enterprise_account.py`

```python
class EnterpriseAccountCreateSchema(Schema):
    """企业账号创建Schema"""
    admin_id = fields.Integer(required=True)
    account_code = fields.Str(required=True, validate=Length(min=1, max=100))
    name = fields.Str(required=True, validate=Length(min=1, max=255))
    login_password = fields.Str(required=True, validate=Length(min=8))
    account_status = fields.Str(validate=OneOf(['enabled', 'disabled']))
    desensitization_strategy = fields.Str(validate=OneOf(['plain', 'phone_only', 'phone_content']))

class EnterpriseAccountListSchema(Schema):
    """企业账号列表查询Schema"""
    page = fields.Integer(missing=1, validate=Range(min=1))
    per_page = fields.Integer(missing=20, validate=Range(min=1, max=100))
    admin_id = fields.Integer()
    account_status = fields.Str(validate=OneOf(['enabled', 'disabled']))
    search = fields.Str()  # 企业账号或账号名称模糊查询

class AccountBindingSchema(Schema):
    """发送账号绑定Schema"""
    account_ids = fields.List(fields.Str(), required=True, validate=Length(min=1))
```

## 🎨 前端组件开发计划

### 1. 页面架构设计

**主路径**: `/customer-management/enterprise-accounts`

```
src/pages/CustomerManagement/EnterpriseAccounts/
├── index.tsx                          # 主页面入口
├── EnterpriseAccountListPage.tsx      # 企业账号列表页面
├── components/
│   ├── EnterpriseAccountTable.tsx     # 企业账号列表表格
│   ├── EnterpriseAccountFormModal.tsx # 新增/编辑表单弹窗
│   ├── SearchFilterSection.tsx        # 搜索筛选区域
│   ├── ActionToolbar.tsx              # 操作工具栏
│   ├── StatusBadge.tsx                # 状态标签组件
│   ├── BindingAccountModal.tsx        # 绑定发送账号弹窗
│   ├── PasswordModifyModal.tsx        # 密码修改弹窗
│   └── index.ts                       # 组件统一导出
```

### 2. 状态管理设计

**文件**: `src/store/slices/enterpriseAccountSlice.ts`

```typescript
interface EnterpriseAccountState {
  // 列表状态
  list: EnterpriseAccount[];
  loading: boolean;
  pagination: PaginationInfo;
  filters: FilterParams;

  // 弹窗状态
  formModalVisible: boolean;
  bindingModalVisible: boolean;
  passwordModalVisible: boolean;

  // 当前操作的企业账号
  currentAccount: EnterpriseAccount | null;

  // 绑定的发送账号
  boundAccounts: SendingAccount[];
}
```

### 3. API集成设计

**文件**: `src/api/enterpriseAccountApi.ts`

```typescript
export const enterpriseAccountApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // 企业账号CRUD
    getEnterpriseAccounts: builder.query<EnterpriseAccountListResponse, EnterpriseAccountListParams>({
      query: (params) => ({
        url: '/enterprises/accounts',
        params,
      }),
      providesTags: ['EnterpriseAccount'],
    }),

    createEnterpriseAccount: builder.mutation<EnterpriseAccount, CreateEnterpriseAccountData>({
      query: (data) => ({
        url: '/enterprises/accounts',
        method: 'POST',
        body: data,
      }),
      invalidatesTags: ['EnterpriseAccount'],
    }),

    // 绑定管理
    getAccountBindings: builder.query<BindingListResponse, string>({
      query: (enterpriseId) => `/enterprises/accounts/${enterpriseId}/bindings`,
      providesTags: ['AccountBinding'],
    }),

    bindAccounts: builder.mutation<void, BindAccountsData>({
      query: ({ enterpriseId, accountIds }) => ({
        url: `/enterprises/accounts/${enterpriseId}/bindings`,
        method: 'POST',
        body: { account_ids: accountIds },
      }),
      invalidatesTags: ['AccountBinding'],
    }),

    // 密码管理
    updatePassword: builder.mutation<void, UpdatePasswordData>({
      query: ({ enterpriseId, password }) => ({
        url: `/enterprises/accounts/${enterpriseId}/password`,
        method: 'PUT',
        body: { password },
      }),
    }),
  }),
});
```

### 4. 核心组件设计

#### 4.1 搜索筛选组件

```typescript
// SearchFilterSection.tsx
interface SearchFilterProps {
  onSearch: (filters: FilterParams) => void;
  loading?: boolean;
}

const SearchFilterSection: React.FC<SearchFilterProps> = ({ onSearch, loading }) => {
  return (
    <Card size="small" className="mb-4">
      <Form layout="inline" onFinish={onSearch}>
        <Form.Item name="admin_id" label="管理员">
          <Select placeholder="选择管理员" allowClear style={{ width: 200 }}>
            {/* 管理员选项 */}
          </Select>
        </Form.Item>

        <Form.Item name="account_status" label="账号状态">
          <Select placeholder="全部状态" allowClear style={{ width: 150 }}>
            <Option value="">全部状态</Option>
            <Option value="enabled">开启</Option>
            <Option value="disabled">关闭</Option>
          </Select>
        </Form.Item>

        <Form.Item name="account_code" label="企业账号">
          <Input placeholder="输入企业账号" style={{ width: 200 }} />
        </Form.Item>

        <Form.Item name="name" label="账号名称">
          <Input placeholder="输入账号名称" style={{ width: 200 }} />
        </Form.Item>

        <Form.Item>
          <Button type="primary" htmlType="submit" loading={loading}>
            查询
          </Button>
          <Button onClick={() => form.resetFields()} style={{ marginLeft: 8 }}>
            重置
          </Button>
        </Form.Item>
      </Form>
    </Card>
  );
};
```

#### 4.2 绑定发送账号弹窗

```typescript
// BindingAccountModal.tsx
interface BindingAccountModalProps {
  visible: boolean;
  enterpriseAccount: EnterpriseAccount;
  onClose: () => void;
  onBind: (accountIds: string[]) => void;
}

const BindingAccountModal: React.FC<BindingAccountModalProps> = ({
  visible,
  enterpriseAccount,
  onClose,
  onBind,
}) => {
  return (
    <Modal
      title={`企业账号"${enterpriseAccount?.name}"绑定发送账号列表`}
      open={visible}
      onCancel={onClose}
      width={800}
      footer={[
        <Button key="cancel" onClick={onClose}>取消</Button>,
        <Button key="bind" type="primary" onClick={handleBind}>绑定</Button>,
      ]}
    >
      {/* 搜索区域 */}
      <div className="mb-4">
        <Input.Search
          placeholder="按发送账号筛选"
          onSearch={handleSearch}
          style={{ width: 300 }}
        />
      </div>

      {/* 发送账号列表 */}
      <Table
        rowSelection={{
          type: 'checkbox',
          selectedRowKeys,
          onChange: setSelectedRowKeys,
        }}
        columns={columns}
        dataSource={accounts}
        pagination={{ pageSize: 10 }}
        scroll={{ y: 400 }}
      />
    </Modal>
  );
};
```

### 5. UI/UX设计要点

#### 5.1 界面布局
- **主界面**: 参考现有企业管理页面设计
- **弹窗宽度**: 新增/编辑弹窗 600px，绑定弹窗 800px
- **表格列**: 序号、企业账号、账号名称、状态、归属、操作
- **操作按钮**: 修改、绑定账号、密码修改、删除

#### 5.2 状态显示
- **开启状态**: 绿色Badge，文字"开启"
- **关闭状态**: 红色Badge，文字"关闭"
- **脱敏策略**: 下拉选择，带说明文字

#### 5.3 交互体验
- **实时搜索**: 输入防抖，避免频繁请求
- **批量操作**: 支持多选和批量绑定
- **操作确认**: 删除操作需要二次确认
- **加载状态**: 所有异步操作显示loading

## 📋 开发任务分解

### Phase 1: 数据库扩展 (1-2天)
- [ ] 修改 `pigeon_web/sql/modules/enterprises.sql` 初始化脚本，添加新字段
- [ ] 更新 `pigeon_web/sql/mock_data/enterprises.sql` Mock数据
- [ ] 更新 `pigeon_web/sql/pigeon_web.sql` 综合脚本
- [ ] 验证数据完整性

### Phase 2: 后端开发 (3-4天)

#### 2.1 模型层扩展
- [ ] 扩展Enterprise模型
- [ ] 新增DesensitizationStrategy枚举
- [ ] 新增密码相关方法
- [ ] 添加关联关系

#### 2.2 服务层开发
- [ ] 扩展EnterpriseService
- [ ] 新增企业账号管理方法
- [ ] 新增绑定管理方法
- [ ] 新增密码管理方法

#### 2.3 API层开发
- [ ] 新增企业账号管理路由
- [ ] 实现查询筛选接口
- [ ] 实现绑定管理接口
- [ ] 实现密码管理接口
- [ ] 编写API文档

### Phase 3: 前端开发 (3-4天)

#### 3.1 基础组件开发
- [ ] 企业账号列表表格
- [ ] 搜索筛选组件
- [ ] 状态显示组件
- [ ] 操作工具栏

#### 3.2 弹窗组件开发
- [ ] 新增/编辑表单弹窗
- [ ] 绑定发送账号弹窗
- [ ] 密码修改弹窗
- [ ] 删除确认弹窗

#### 3.3 状态管理和API
- [ ] Redux状态管理
- [ ] RTK Query API集成
- [ ] 错误处理和反馈

#### 3.4 页面集成和路由
- [ ] 主页面集成
- [ ] 路由配置
- [ ] 权限控制
- [ ] 导航菜单

### Phase 4: 测试验证 (1天)
- [ ] 单元测试编写
- [ ] 接口测试验证
- [ ] 前后端联调
- [ ] 用户体验测试

## 🎯 验收标准

### 功能验收标准
- [ ] 支持按管理员筛选企业账号
- [ ] 支持企业账号和账号名称模糊查询
- [ ] 企业账号CRUD操作正常
- [ ] 绑定/解绑发送账号功能正常
- [ ] 密码修改功能正常
- [ ] 状态切换功能正常
- [ ] 脱敏策略设置正常

### 性能验收标准
- [ ] 列表查询响应时间 < 3秒
- [ ] 支持分页和大数据量处理
- [ ] 前端组件渲染流畅

### 安全验收标准
- [ ] 所有操作需要相应权限
- [ ] 密码安全存储和验证
- [ ] 数据脱敏功能正确

### 用户体验验收标准
- [ ] 界面响应式设计适配
- [ ] 操作反馈及时准确
- [ ] 错误提示友好清晰

## 🔧 技术实现要点

### 1. 密码安全
- 使用bcrypt或类似算法加密存储
- 密码强度验证
- 密码修改需要验证当前密码

### 2. 权限控制
- 新增相关权限定义
- API端点权限验证
- 前端组件权限控制

### 3. 脱敏策略实现
- 前端数据显示脱敏
- 导出数据脱敏处理
- API响应数据脱敏

### 4. 性能优化
- 数据库查询索引优化
- 前端虚拟滚动（大数据量）
- API响应数据缓存

## 📚 相关文档

- [FEAT-1-1 企业账号管理需求文档](../pigeon_requirements/features/FEAT-1-1%20企业账号管理.md)
- [FEAT-1-1 UI/UX设计方案](../pigeon_requirements/features/FEAT-1-1%20企业账号管理%20UI-UX%20设计方案.md)
- [pigeon_web 编码习惯规范](./编码习惯.md)
- [代码提交规范](./代码提交规范.md)

## 🚨 风险点和注意事项

### 技术风险
1. **数据库Schema变更风险**:
   - 需要保证向后兼容性
   - 建议先在测试环境验证

2. **权限系统集成风险**:
   - 需要确保权限定义完整
   - 避免权限漏洞

3. **数据脱敏功能风险**:
   - 需要全面测试各种数据场景
   - 确保脱敏逻辑正确

### 业务风险
1. **现有数据兼容性**:
   - 确保现有企业数据不受影响
   - 新增字段使用默认值保证兼容性

2. **用户体验风险**:
   - 新功能需要与现有界面保持一致性
   - 避免破坏现有用户习惯

### 建议缓解措施
- 分阶段开发和测试
- 充分的单元测试和集成测试
- 代码Review确保质量
- 用户验收测试

---

**文档版本**: v1.0
**创建时间**: 2025-01-23
**最后更新**: 2025-01-23
**创建人**: Claude Code Assistant