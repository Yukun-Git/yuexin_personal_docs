# Week 1-2: 项目架构搭建 - 详细任务分解

## 任务1: 完善Flask应用结构设计

### 1.1 分析现有项目结构
**预估时间**: 0.5天  
**具体任务**:
- [ ] 深入分析pigeon_web现有代码结构
- [ ] 识别需要重构和优化的部分
- [ ] 对比需求文档，确定缺失的模块
- [ ] 制定结构优化方案

**验证清单**:
- [ ] 完成现有代码结构分析报告
- [ ] 列出所有需要新增的模块
- [ ] 列出需要重构的现有模块
- [ ] 确定模块间的依赖关系

### 1.2 设计标准化目录结构
**预估时间**: 0.5天  
**具体任务**:
- [ ] 按照业务域重新组织目录结构
- [ ] 设计分层架构(API→Service→Model)
- [ ] 规划配置文件和环境管理
- [ ] 设计测试目录结构

**目标结构**:
```
pigeon_web/
├── app/
│   ├── __init__.py
│   ├── extensions.py          # 扩展初始化
│   ├── config.py              # 配置管理
│   ├── api/                   # API路由层
│   │   ├── __init__.py
│   │   ├── v1/
│   │   │   ├── __init__.py
│   │   │   ├── auth/          # 认证相关API
│   │   │   ├── customers/     # 客户管理API
│   │   │   ├── monitoring/    # 监控相关API
│   │   │   ├── review/        # 审核相关API
│   │   │   └── common.py      # 公共API处理
│   ├── models/                # 数据模型层
│   │   ├── __init__.py
│   │   ├── base.py           # 基础模型类
│   │   ├── auth.py           # 认证相关模型
│   │   ├── customer.py       # 客户管理模型
│   │   ├── message.py        # 短信相关模型
│   │   └── system.py         # 系统配置模型
│   ├── services/              # 业务逻辑层
│   │   ├── __init__.py
│   │   ├── base.py           # 基础服务类
│   │   ├── auth_service.py   # 认证业务逻辑
│   │   ├── customer_service.py # 客户管理业务
│   │   ├── review_service.py # 审核业务逻辑
│   │   └── monitoring_service.py # 监控业务逻辑
│   ├── schemas/               # 数据验证层
│   │   ├── __init__.py
│   │   ├── base.py           # 基础Schema
│   │   ├── auth.py           # 认证相关Schema
│   │   ├── customer.py       # 客户管理Schema
│   │   └── common.py         # 公共Schema
│   ├── utils/                 # 工具函数
│   │   ├── __init__.py
│   │   ├── decorators.py     # 装饰器
│   │   ├── validators.py     # 验证器
│   │   ├── exceptions.py     # 异常定义
│   │   ├── response.py       # 统一响应格式
│   │   └── helpers.py        # 辅助函数
│   └── tasks/                # 异步任务
│       ├── __init__.py
│       └── celery_app.py     # Celery配置
├── migrations/                # 数据库迁移
├── tests/                     # 测试目录
│   ├── unit/                 # 单元测试
│   ├── integration/          # 集成测试
│   └── conftest.py           # 测试配置
├── docs/                      # 项目文档
├── scripts/                   # 脚本工具
├── requirements/              # 依赖管理
│   ├── base.txt              # 基础依赖
│   ├── development.txt       # 开发依赖
│   └── production.txt        # 生产依赖
├── .env.example              # 环境变量示例
├── config.py                 # 配置文件
├── wsgi.py                   # WSGI入口
└── run.py                    # 开发服务器入口
```

**验证清单**:
- [ ] 目录结构符合Flask最佳实践
- [ ] 模块职责划分清晰
- [ ] 支持多环境配置
- [ ] 便于扩展和维护

### 1.3 实现模块重构
**预估时间**: 1天  
**具体任务**:
- [ ] 将现有代码按新结构重新组织
- [ ] 实现基础类和工具函数
- [ ] 建立模块间的标准化接口
- [ ] 更新导入引用关系

**验证清单**:
- [ ] 所有模块能正常导入
- [ ] 现有功能不受影响
- [ ] 代码符合PEP8规范
- [ ] 通过基础功能测试

## 任务2: 数据库模型设计和迁移脚本

### 2.1 数据模型设计
**预估时间**: 1天  
**具体任务**:
- [ ] 基于ER设计图创建SQLAlchemy模型
- [ ] 设计模型基础类和公共字段
- [ ] 实现模型关系映射
- [ ] 添加数据验证和约束

**核心模型设计**:
```python
# 企业账号模型
class EnterpriseAccount(BaseModel):
    __tablename__ = 'enterprise_accounts'
    
    company_name = db.Column(db.String(200), nullable=False)
    contact_person = db.Column(db.String(100))
    contact_phone = db.Column(db.String(20))
    contact_email = db.Column(db.String(100))
    status = db.Column(db.Integer, default=1)
    
    # 关系映射
    sending_accounts = db.relationship('SendingAccount', backref='enterprise')

# 发送账号模型  
class SendingAccount(BaseModel):
    __tablename__ = 'sending_accounts'
    
    enterprise_id = db.Column(db.String(36), db.ForeignKey('enterprise_accounts.id'))
    account_name = db.Column(db.String(100), nullable=False)
    api_key = db.Column(db.String(128), unique=True)
    status = db.Column(db.Integer, default=1)
    daily_limit = db.Column(db.Integer, default=10000)

# 用户认证模型
class User(BaseModel):
    __tablename__ = 'users'
    
    username = db.Column(db.String(50), unique=True, nullable=False)
    email = db.Column(db.String(100), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    is_active = db.Column(db.Boolean, default=True)
    role_id = db.Column(db.String(36), db.ForeignKey('roles.id'))
```

**验证清单**:
- [ ] 所有必要的模型类已创建
- [ ] 模型关系正确映射
- [ ] 字段约束设置合理
- [ ] 模型能正确序列化/反序列化

### 2.2 数据库迁移脚本
**预估时间**: 0.5天  
**具体任务**:
- [ ] 配置Flask-Migrate
- [ ] 生成初始迁移脚本
- [ ] 创建索引和约束
- [ ] 添加初始数据脚本

**验证清单**:
- [ ] 迁移脚本能成功运行
- [ ] 数据库表结构正确创建
- [ ] 索引和约束生效
- [ ] 初始数据正确插入

### 2.3 模型测试和验证
**预估时间**: 0.5天  
**具体任务**:
- [ ] 编写模型单元测试
- [ ] 测试CRUD操作
- [ ] 验证关系映射
- [ ] 测试数据约束

**验证清单**:
- [ ] 所有模型测试通过
- [ ] CRUD操作正常
- [ ] 关系查询正确
- [ ] 数据约束有效

## 任务3: 认证授权系统实现

### 3.1 JWT认证系统
**预估时间**: 1天  
**具体任务**:
- [ ] 配置Flask-JWT-Extended
- [ ] 实现用户登录/注册接口
- [ ] 实现Token生成和验证
- [ ] 实现Token刷新机制

**核心功能实现**:
```python
# 认证服务
class AuthService:
    @staticmethod
    def login(username, password):
        """用户登录"""
        user = User.query.filter_by(username=username).first()
        if user and user.verify_password(password):
            access_token = create_access_token(identity=user.id)
            refresh_token = create_refresh_token(identity=user.id)
            return {'access_token': access_token, 'refresh_token': refresh_token}
        return None
    
    @staticmethod
    def refresh_token(refresh_token):
        """刷新Token"""
        pass
```

**验证清单**:
- [ ] 用户能成功登录获取Token
- [ ] Token验证机制正常工作
- [ ] Token刷新功能正常
- [ ] 登录状态能正确维护

### 3.2 权限管理系统
**预估时间**: 1天  
**具体任务**:
- [ ] 设计RBAC权限模型
- [ ] 实现角色和权限管理
- [ ] 实现权限检查装饰器
- [ ] 实现资源级别权限控制

**权限系统设计**:
```python
# 权限装饰器
def require_permission(permission):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # 检查用户权限
            if not current_user_has_permission(permission):
                return {'message': 'Permission denied'}, 403
            return f(*args, **kwargs)
        return decorated_function
    return decorator

# 使用示例
@require_permission('customer.create')
def create_customer():
    pass
```

**验证清单**:
- [ ] RBAC模型正确实现
- [ ] 权限检查装饰器工作正常
- [ ] 不同角色权限隔离有效
- [ ] 权限管理接口功能完整

## 任务4: API基础框架搭建

### 4.1 API路由结构设计
**预估时间**: 0.5天  
**具体任务**:
- [ ] 设计RESTful API路由规范
- [ ] 实现API蓝图结构
- [ ] 配置API版本管理
- [ ] 实现统一错误处理

**API结构设计**:
```python
# API蓝图注册
def register_blueprints(app):
    from app.api.v1 import bp as api_v1_bp
    app.register_blueprint(api_v1_bp, url_prefix='/api/v1')

# v1版本API结构
api_v1/
├── __init__.py
├── auth/
│   ├── __init__.py
│   └── views.py
├── customers/
│   ├── __init__.py  
│   └── views.py
└── common.py
```

**验证清单**:
- [ ] API路由结构清晰
- [ ] 蓝图注册正确
- [ ] 版本管理机制有效
- [ ] 错误处理统一

### 4.2 统一响应格式
**预估时间**: 0.5天  
**具体任务**:
- [ ] 设计标准API响应格式
- [ ] 实现响应包装器
- [ ] 实现分页响应格式
- [ ] 实现错误响应格式

**响应格式标准**:
```python
# 成功响应格式
{
    "code": 200,
    "message": "success", 
    "data": {},
    "timestamp": "2024-01-01T00:00:00Z"
}

# 分页响应格式
{
    "code": 200,
    "message": "success",
    "data": [],
    "pagination": {
        "page": 1,
        "size": 20, 
        "total": 100,
        "pages": 5
    },
    "timestamp": "2024-01-01T00:00:00Z"
}
```

**验证清单**:
- [ ] 响应格式标准化
- [ ] 分页功能正常
- [ ] 错误信息清晰
- [ ] 时间戳格式统一

### 4.3 数据验证框架
**预估时间**: 0.5天  
**具体任务**:
- [ ] 配置Marshmallow数据验证
- [ ] 实现基础Schema类
- [ ] 实现常用验证器
- [ ] 集成到API接口中

**验证清单**:
- [ ] 数据验证正常工作
- [ ] 验证错误信息清晰
- [ ] Schema复用性好
- [ ] 性能表现良好

## 任务5: 开发环境配置和文档

### 5.1 开发环境配置
**预估时间**: 0.5天  
**具体任务**:
- [ ] 更新requirements.txt依赖
- [ ] 配置开发/测试/生产环境
- [ ] 设置环境变量管理
- [ ] 配置代码质量工具

**环境配置清单**:
```python
# requirements/base.txt
Flask>=2.3.0
Flask-RESTful>=0.3.10
Flask-SQLAlchemy>=3.0.0
Flask-JWT-Extended>=4.5.0
Flask-Migrate>=4.0.0
marshmallow>=3.19.0
redis>=4.5.0
psycopg2-binary>=2.9.0

# requirements/development.txt
-r base.txt
pytest>=7.0.0
pytest-cov>=4.0.0
black>=23.0.0
flake8>=6.0.0
pre-commit>=3.0.0
```

**验证清单**:
- [ ] 依赖安装无冲突
- [ ] 环境变量配置正确
- [ ] 代码格式化工具工作正常
- [ ] 开发服务器能正常启动

### 5.2 项目文档编写
**预估时间**: 0.5天  
**具体任务**:
- [ ] 编写项目README
- [ ] 编写开发环境搭建文档
- [ ] 编写API使用文档
- [ ] 编写代码规范文档

**文档清单**:
- [ ] README.md - 项目概述和快速开始
- [ ] docs/setup.md - 开发环境搭建
- [ ] docs/api.md - API接口文档
- [ ] docs/coding-style.md - 代码规范

**验证清单**:
- [ ] 文档内容完整准确
- [ ] 按文档能成功搭建环境
- [ ] API文档与实际接口一致
- [ ] 代码规范清晰可执行

### 5.3 CI/CD基础配置
**预估时间**: 0.5天  
**具体任务**:
- [ ] 配置pre-commit hooks
- [ ] 设置GitHub Actions基础流程
- [ ] 配置自动化测试
- [ ] 配置代码覆盖率检查

**验证清单**:
- [ ] pre-commit检查正常工作
- [ ] CI流程能成功运行
- [ ] 测试覆盖率达到预期
- [ ] 代码质量检查通过

## 总体验收标准

### Week 1-2 完成标准
- [ ] 项目结构清晰，符合最佳实践
- [ ] 数据库模型完整，迁移脚本正常
- [ ] 认证授权系统功能完整
- [ ] API基础框架搭建完成
- [ ] 开发环境配置完整，文档齐全
- [ ] 所有单元测试通过
- [ ] 代码覆盖率 ≥ 80%
- [ ] 代码质量检查通过

### 关键里程碑检查点
1. **Day 3**: 项目结构重构完成
2. **Day 6**: 数据库模型和认证系统完成
3. **Day 9**: API基础框架完成
4. **Day 10**: 开发环境和文档完成

这个任务分解确保了每个子任务都有明确的交付物和验证标准，便于跟踪进度和质量控制。