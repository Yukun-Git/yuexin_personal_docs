# Account多协议支持重构方案

**文档版本**: v1.0  
**创建日期**: 2025-09-11  
**负责人**: Claude Code Assistant  
**项目**: pigeon_web 国际短信服务Web管理系统

## 🔍 问题分析总结

### 1. 数据库Schema设计问题 ✅
**当前错误设计**：
```sql
-- 错误：只允许账号支持单一协议
protocol_type protocol_type DEFAULT 'smpp' NOT NULL,
```

**核心问题**：
- `protocol_type`字段假设每个account只能支持一种协议
- 无法表达一个账号同时支持SMPP+HTTP+Custom的需求
- 配置字段分散：`smpp_config`, `http_config`仍然按单协议设计

### 2. 业务逻辑代码实现问题 ✅
**Service层问题**：
```python
# account_service.py:451-456 - 错误的单协议假设
if account.protocol_type == ProtocolType.SMPP:
    self._validate_smpp_config(config_data.get('smpp_config', {}))
elif account.protocol_type == ProtocolType.HTTP:
    self._validate_http_config(config_data.get('http_config', {}))
```

**API层问题**：
- 筛选逻辑假设单协议：`filter(Account.protocol_type == protocol_enum)`
- 配置管理基于单协议：`account.protocol_type.value == 'smpp'`
- 前端类型定义也是单协议：`protocol_type: ProtocolType`

## 🎯 正确的多协议架构设计

### 核心设计原则

1. **协议无关性**：Account实体与具体协议解耦
2. **配置隔离**：每种协议独立配置和管理
3. **动态扩展**：新协议零代码添加到系统
4. **向后兼容**：已有数据平滑迁移

## 📋 重构方案详细设计

### 方案A：关联表模式 (推荐)

#### 数据库Schema重构
```sql
-- 1. 新增协议配置表
CREATE TABLE account_protocol_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id VARCHAR(255) NOT NULL,
    protocol_type protocol_type NOT NULL,
    enabled BOOLEAN DEFAULT TRUE,
    config_data JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- 复合唯一索引：确保一个账号的每种协议只有一条配置
    UNIQUE(account_id, protocol_type),
    FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
);

-- 2. 移除accounts表的单协议字段
ALTER TABLE accounts DROP COLUMN protocol_type;
ALTER TABLE accounts DROP COLUMN smpp_config;
ALTER TABLE accounts DROP COLUMN http_config;

-- 3. 添加支持的协议视图（便于查询）
CREATE OR REPLACE VIEW account_supported_protocols AS
SELECT 
    account_id,
    array_agg(protocol_type) as supported_protocols,
    array_agg(protocol_type) FILTER (WHERE enabled = true) as enabled_protocols
FROM account_protocol_configs
GROUP BY account_id;
```

#### 数据迁移策略
```sql
-- 数据迁移脚本
INSERT INTO account_protocol_configs (account_id, protocol_type, enabled, config_data)
SELECT 
    account_id,
    protocol_type as protocol_type,
    true as enabled,
    CASE 
        WHEN protocol_type = 'smpp' THEN smpp_config
        WHEN protocol_type = 'http' THEN http_config
        ELSE '{}'::jsonb
    END as config_data
FROM accounts 
WHERE protocol_type IS NOT NULL;
```

### 方案B：JSON数组模式 (备选)

#### 数据库Schema重构
```sql
-- 使用JSONB存储多协议配置
ALTER TABLE accounts 
DROP COLUMN protocol_type,
DROP COLUMN smpp_config,
DROP COLUMN http_config,
ADD COLUMN protocol_configs JSONB DEFAULT '[]';

-- 示例数据结构
-- protocol_configs: [
--   {
--     "type": "smpp",
--     "enabled": true,
--     "config": { "host": "...", "port": 2775, ... }
--   },
--   {
--     "type": "http", 
--     "enabled": true,
--     "config": { "url": "...", "method": "POST", ... }
--   }
-- ]
```

## 🛠️ 代码重构实施计划

### Phase 1: 数据模型重构 (4小时)

#### 1.1 新增Protocol配置模型
```python
# app/models/customers/account_protocol_config.py
class AccountProtocolConfig(db.Model, TimestampMixin):
    """Account protocol configuration model."""
    
    __tablename__ = 'account_protocol_configs'
    
    id = db.Column(db.String(36), primary_key=True, default=db.func.uuid_generate_v4())
    account_id = db.Column(db.String(255), db.ForeignKey('accounts.account_id'), nullable=False)
    protocol_type = db.Column(db.Enum(ProtocolType, values_callable=lambda obj: [e.value for e in obj]), nullable=False)
    enabled = db.Column(db.Boolean, default=True, nullable=False)
    config_data = db.Column(db.JSON, default={}, nullable=False)
    
    # 关系
    account = db.relationship('Account', back_populates='protocol_configs')
    
    # 复合唯一约束
    __table_args__ = (
        db.UniqueConstraint('account_id', 'protocol_type', name='uk_account_protocol'),
    )
```

#### 1.2 修改Account模型
```python
# app/models/customers/account.py 关键修改
class Account(db.Model, TimestampMixin):
    # 移除单协议字段
    # protocol_type = db.Column(...)  # 删除
    # smpp_config = db.Column(...)    # 删除  
    # http_config = db.Column(...)    # 删除
    
    # 新增多协议关系
    protocol_configs = db.relationship('AccountProtocolConfig', 
                                     back_populates='account',
                                     cascade='all, delete-orphan')
    
    @property
    def supported_protocols(self) -> List[ProtocolType]:
        """获取支持的所有协议."""
        return [config.protocol_type for config in self.protocol_configs]
    
    @property
    def enabled_protocols(self) -> List[ProtocolType]:
        """获取启用的协议."""
        return [config.protocol_type for config in self.protocol_configs if config.enabled]
    
    def get_protocol_config(self, protocol: ProtocolType) -> Optional[Dict]:
        """获取指定协议的配置."""
        config = next((c for c in self.protocol_configs if c.protocol_type == protocol), None)
        return config.config_data if config else None
    
    def has_protocol(self, protocol: ProtocolType) -> bool:
        """检查是否支持指定协议."""
        return protocol in self.supported_protocols
```

### Phase 2: Service层重构 (3小时)

#### 2.1 AccountService核心方法重构
```python
# app/services/accounts/account_service.py 关键重构

def get_accounts_by_protocol(self, protocol: ProtocolType, enabled_only: bool = True) -> List[Account]:
    """根据协议类型查询账号."""
    query = db.session.query(Account).join(AccountProtocolConfig).filter(
        AccountProtocolConfig.protocol_type == protocol
    )
    if enabled_only:
        query = query.filter(AccountProtocolConfig.enabled == True)
    return query.all()

def update_protocol_config(self, account_id: str, protocol: ProtocolType, 
                          config_data: Dict, enabled: bool = True) -> bool:
    """更新或创建协议配置."""
    account = Account.query.filter_by(account_id=account_id).first()
    if not account:
        return False
    
    # 查找或创建协议配置
    protocol_config = AccountProtocolConfig.query.filter_by(
        account_id=account_id, protocol_type=protocol
    ).first()
    
    if not protocol_config:
        protocol_config = AccountProtocolConfig(
            account_id=account_id,
            protocol_type=protocol
        )
        db.session.add(protocol_config)
    
    # 验证配置
    self._validate_protocol_config(protocol, config_data)
    
    # 更新配置
    protocol_config.config_data = config_data
    protocol_config.enabled = enabled
    
    db.session.commit()
    return True

def enable_protocol(self, account_id: str, protocol: ProtocolType) -> bool:
    """启用账号的指定协议."""
    config = AccountProtocolConfig.query.filter_by(
        account_id=account_id, protocol_type=protocol
    ).first()
    if config:
        config.enabled = True
        db.session.commit()
        return True
    return False

def disable_protocol(self, account_id: str, protocol: ProtocolType) -> bool:
    """禁用账号的指定协议."""
    config = AccountProtocolConfig.query.filter_by(
        account_id=account_id, protocol_type=protocol
    ).first()
    if config:
        config.enabled = False
        db.session.commit()
        return True
    return False
```

#### 2.2 筛选逻辑重构
```python
def list_accounts(self, 
                 supported_protocols: List[str] = None,  # 新增：支持的协议筛选
                 enabled_protocols: List[str] = None,    # 新增：启用的协议筛选
                 **other_filters) -> Dict:
    """重构后的账号列表查询."""
    
    query = Account.query
    
    # 协议筛选逻辑
    if supported_protocols:
        protocol_enums = [ProtocolType(p) for p in supported_protocols]
        query = query.join(AccountProtocolConfig).filter(
            AccountProtocolConfig.protocol_type.in_(protocol_enums)
        )
    
    if enabled_protocols:
        protocol_enums = [ProtocolType(p) for p in enabled_protocols]
        query = query.join(AccountProtocolConfig).filter(
            AccountProtocolConfig.protocol_type.in_(protocol_enums),
            AccountProtocolConfig.enabled == True
        )
    
    # 其他筛选逻辑...
    return self._build_paginated_response(query, page, per_page)
```

### Phase 3: API层重构 (2小时)

#### 3.1 新增多协议管理API
```python
# app/api/v1/accounts/route/account_protocols.py (新文件)
class AccountProtocolsResource(Resource):
    """账号协议管理API."""
    
    @login_required
    def get(self, account_id):
        """获取账号支持的所有协议配置."""
        account = Account.query.filter_by(account_id=account_id).first_or_404()
        
        protocols_data = []
        for config in account.protocol_configs:
            protocols_data.append({
                'protocol_type': config.protocol_type.value,
                'enabled': config.enabled,
                'config': config.config_data,
                'updated_at': config.updated_at
            })
        
        return success_response({
            'account_id': account_id,
            'protocols': protocols_data,
            'supported_protocols': [p.value for p in account.supported_protocols],
            'enabled_protocols': [p.value for p in account.enabled_protocols]
        })
    
    @login_required 
    def post(self, account_id):
        """为账号添加新协议支持."""
        data = request.get_json()
        protocol_type = data.get('protocol_type')
        config_data = data.get('config', {})
        enabled = data.get('enabled', True)
        
        success = account_service.update_protocol_config(
            account_id, ProtocolType(protocol_type), config_data, enabled
        )
        
        if success:
            return success_response({'message': 'Protocol added successfully'})
        else:
            return error_response('Failed to add protocol', 400)

class AccountProtocolResource(Resource):
    """单个协议配置管理."""
    
    @login_required
    def put(self, account_id, protocol_type):
        """更新指定协议配置."""
        # 实现协议配置更新逻辑
        pass
    
    @login_required
    def delete(self, account_id, protocol_type):
        """移除协议支持."""
        # 实现协议移除逻辑
        pass
```

#### 3.2 修改现有API筛选参数
```python
# app/api/v1/accounts/route/account_list.py 修改
def get(self):
    """账号列表查询 - 支持多协议筛选."""
    # 新的筛选参数
    supported_protocols = request.args.getlist('supported_protocols')  # 支持协议
    enabled_protocols = request.args.getlist('enabled_protocols')      # 启用协议
    
    result = account_service.list_accounts(
        supported_protocols=supported_protocols,
        enabled_protocols=enabled_protocols,
        # 其他现有参数...
    )
    return success_response(result)
```

### Phase 4: 前端重构 (3小时)

#### 4.1 类型定义重构
```typescript
// frontend/src/types/api/responses.ts
export interface AccountProtocolConfig {
  protocol_type: ProtocolType;
  enabled: boolean;
  config: Record<string, any>;
  updated_at: string;
}

export interface AccountResponse {
  account_id: string;
  name: string;
  // 移除：protocol_type: ProtocolType;
  // 新增：多协议支持
  protocols: AccountProtocolConfig[];
  supported_protocols: ProtocolType[];
  enabled_protocols: ProtocolType[];
}
```

#### 4.2 筛选组件重构
```typescript
// AccountSearchFilter.tsx 重构
interface FilterState {
  // 原有字段...
  // protocol_type: ProtocolType | '';  // 删除单协议筛选
  
  // 新增多协议筛选
  supported_protocols: ProtocolType[];    // 支持的协议
  enabled_protocols: ProtocolType[];      // 启用的协议
}

const AccountSearchFilter: React.FC = () => {
  const [filters, setFilters] = useState<FilterState>({
    supported_protocols: [],
    enabled_protocols: [],
  });

  return (
    <Form>
      {/* 支持协议多选 */}
      <Form.Item label="支持协议">
        <Select
          mode="multiple"
          placeholder="选择支持的协议"
          value={filters.supported_protocols}
          onChange={(value) => setFilters(prev => ({...prev, supported_protocols: value}))}
        >
          <Option value="smpp">SMPP</Option>
          <Option value="http">HTTP</Option>
          <Option value="custom">Custom</Option>
        </Select>
      </Form.Item>
      
      {/* 启用协议多选 */}
      <Form.Item label="启用协议">
        <Select
          mode="multiple"
          placeholder="选择启用的协议"
          value={filters.enabled_protocols}
          onChange={(value) => setFilters(prev => ({...prev, enabled_protocols: value}))}
        >
          <Option value="smpp">SMPP</Option>
          <Option value="http">HTTP</Option>
          <Option value="custom">Custom</Option>
        </Select>
      </Form.Item>
    </Form>
  );
};
```

#### 4.3 协议管理组件
```typescript
// AccountProtocolManager.tsx (新组件)
const AccountProtocolManager: React.FC<{account: AccountResponse}> = ({ account }) => {
  return (
    <Card title="协议配置管理">
      {AVAILABLE_PROTOCOLS.map(protocol => (
        <Card.Grid key={protocol} style={{ width: '33%' }}>
          <div>
            <h4>{protocol.toUpperCase()}</h4>
            <Space>
              <Tag color={account.enabled_protocols.includes(protocol) ? 'green' : 'red'}>
                {account.enabled_protocols.includes(protocol) ? '已启用' : '已禁用'}
              </Tag>
              <Button size="small" type="link">配置</Button>
              <Button size="small" type="link">
                {account.enabled_protocols.includes(protocol) ? '禁用' : '启用'}
              </Button>
            </Space>
          </div>
        </Card.Grid>
      ))}
    </Card>
  );
};
```

## 📋 实施时间估算

| 阶段 | 任务 | 预估时间 |
|------|------|----------|
| Phase 1 | 数据模型重构 | 4小时 |
| Phase 2 | Service层重构 | 3小时 |
| Phase 3 | API层重构 | 2小时 |
| Phase 4 | 前端重构 | 3小时 |
| Phase 5 | 数据迁移与测试 | 2小时 |
| **总计** | | **14小时** |

## ⚠️ 风险控制与注意事项

### 1. 数据迁移风险
- **备份策略**：重构前完整备份数据库
- **分步迁移**：先添加新表，再迁移数据，最后删除旧字段
- **回滚方案**：保留旧字段一周，确认无问题后删除

### 2. API兼容性
- **向后兼容**：保留`protocol_type`查询参数，内部转换为多协议查询
- **版本控制**：新API使用`v2`版本，逐步废弃`v1`相关端点

### 3. 性能考虑
- **索引优化**：`account_protocol_configs`表添加必要索引
- **查询优化**：避免N+1查询，使用JOIN查询

## 🎯 验收标准

### 功能验收
1. ✅ 一个账号可以同时配置SMPP、HTTP、Custom三种协议
2. ✅ 每种协议可以独立启用/禁用
3. ✅ 协议配置相互独立，修改SMPP不影响HTTP
4. ✅ 筛选支持"支持SMPP且启用HTTP"等复合条件
5. ✅ 新增协议类型不需要修改数据库Schema

### 技术验收
1. ✅ 数据迁移100%无损失
2. ✅ API响应时间不超过现有方案20%
3. ✅ 前端界面支持多协议管理
4. ✅ 向后兼容现有客户端调用

## 🚀 实施建议

### 推荐实施顺序
1. **Phase 1**: 数据模型重构 - 建立新的多协议数据结构
2. **Phase 5**: 数据迁移 - 将现有数据迁移到新结构
3. **Phase 2**: Service层重构 - 业务逻辑适配多协议
4. **Phase 3**: API层重构 - 接口层支持多协议操作
5. **Phase 4**: 前端重构 - 用户界面支持多协议管理

### 分支策略
- 创建 `feature/multi-protocol-support` 分支
- 每个Phase完成后创建子分支进行测试
- 确保可以随时回滚到当前稳定版本

### 测试策略
- **单元测试**：每个新增方法都需要单元测试覆盖
- **集成测试**：API层的多协议操作集成测试
- **数据迁移测试**：使用测试数据验证迁移脚本
- **性能测试**：对比重构前后的查询性能

---

**文档维护**：本文档将随着实施进度持续更新  
**反馈渠道**：实施过程中的问题和改进建议请及时反馈