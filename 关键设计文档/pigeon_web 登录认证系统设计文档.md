# Pigeon Web 登录认证系统设计文档

## 文档信息
- **创建日期**: 2025-10-15
- **作者**: Claude Code
- **版本**: v1.0
- **项目**: Pigeon Web SMS Management Platform

## 目录
1. [系统概述](#系统概述)
2. [认证架构](#认证架构)
3. [数据库设计](#数据库设计)
4. [后端认证实现](#后端认证实现)
5. [前端认证实现](#前端认证实现)
6. [安全机制](#安全机制)
7. [飞书集成认证](#飞书集成认证)
8. [权限控制系统](#权限控制系统)

---

## 系统概述

Pigeon Web 采用了基于 JWT (JSON Web Token) 的认证系统，支持本地用户名密码登录和飞书 OAuth2.0 单点登录两种认证方式。系统实现了完整的 RBAC (Role-Based Access Control) 权限控制模型。

### 主要特性
- **多种认证方式**: 本地认证、飞书OAuth2.0认证、混合认证
- **JWT Token管理**: Access Token + Refresh Token 双令牌机制
- **RBAC权限系统**: 角色-权限模型，支持细粒度权限控制
- **用户层级管理**: 支持管理员用户的层级结构
- **安全特性**: 密码哈希、Token黑名单、MFA支持、数据隔离
- **Token自动刷新**: 前端自动处理Token过期和刷新

---

## 认证架构

### 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                          前端应用层                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  LoginPage   │  │ AuthSlice    │  │ProtectedRoute│          │
│  │  (登录界面)   │  │ (状态管理)    │  │  (路由守卫)   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                  │                  │                  │
│         └──────────────────┴──────────────────┘                  │
│                            │                                     │
│                    ┌───────▼───────┐                            │
│                    │   AuthAPI     │                            │
│                    │ (API请求层)    │                            │
│                    └───────┬───────┘                            │
└────────────────────────────┼─────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  Flask Backend  │
                    └────────┬────────┘
                             │
        ┏━━━━━━━━━━━━━━━━━━━━▼━━━━━━━━━━━━━━━━━━━━┓
        ┃            认证服务层                     ┃
        ┃  ┌────────────────┐  ┌────────────────┐ ┃
        ┃  │  AuthService   │  │FeishuAuthService│ ┃
        ┃  │  (本地认证)     │  │  (飞书认证)      │ ┃
        ┃  └────────────────┘  └────────────────┘ ┃
        ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                             │
        ┏━━━━━━━━━━━━━━━━━━━━▼━━━━━━━━━━━━━━━━━━━━┓
        ┃            权限服务层                     ┃
        ┃  ┌────────────────────────────────────┐ ┃
        ┃  │      PermissionService             │ ┃
        ┃  │  (权限验证、角色管理、权限分配)      │ ┃
        ┃  └────────────────────────────────────┘ ┃
        ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
                             │
        ┏━━━━━━━━━━━━━━━━━━━━▼━━━━━━━━━━━━━━━━━━━━┓
        ┃            数据持久层                     ┃
        ┃  ┌────────┐ ┌────────┐ ┌────────────┐  ┃
        ┃  │ Users  │ │ Roles  │ │Permissions │  ┃
        ┃  └────────┘ └────────┘ └────────────┘  ┃
        ┃  ┌────────────┐  ┌──────────────────┐  ┃
        ┃  │ UserRoles  │  │ RolePermissions  │  ┃
        ┃  └────────────┘  └──────────────────┘  ┃
        ┃  ┌──────────────────┐                   ┃
        ┃  │ FeishuAuthUsers  │                   ┃
        ┃  └──────────────────┘                   ┃
        ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### 认证流程

#### 1. 本地认证流程

```
用户输入凭证
     │
     ▼
前端发起登录请求 (POST /api/v1/auth/login)
     │
     ▼
AuthService.authenticate_user()
     │
     ├─► 验证用户名/邮箱
     ├─► 检查用户是否激活
     ├─► 验证密码哈希
     │
     ▼
AuthService.generate_tokens()
     │
     ├─► 获取用户角色
     ├─► 获取用户权限
     ├─► 生成 Access Token (有效期: 1小时)
     ├─► 生成 Refresh Token (有效期: 24小时)
     │
     ▼
返回 Token 和用户信息
     │
     ▼
前端存储 Token 到 localStorage
     │
     ▼
更新 Redux 状态 (authSlice)
     │
     ▼
跳转到主页面
```

#### 2. 飞书OAuth2.0认证流程

```
用户点击飞书登录
     │
     ▼
获取飞书授权URL (GET /api/v1/feishu-auth/authorize)
     │
     ▼
跳转到飞书授权页面
     │
     ▼
用户在飞书完成授权
     │
     ▼
飞书回调 (带code和state参数)
     │
     ▼
前端处理回调 (POST /api/v1/feishu-auth/callback)
     │
     ▼
FeishuAuthService.authenticate_with_code()
     │
     ├─► 验证state参数 (防CSRF)
     ├─► 用code换取access_token
     ├─► 获取飞书用户信息
     ├─► 验证邮箱域名 (如果配置了限制)
     │
     ├─► 查找现有用户 (通过feishu_user_id)
     │   ├─► 存在: 同步用户信息
     │   └─► 不存在:
     │       ├─► 通过邮箱查找
     │       ├─► 存在: 关联飞书认证
     │       └─► 不存在: 自动创建用户 (如果启用)
     │
     ▼
生成JWT Token (同本地认证)
     │
     ▼
返回 Token 和用户信息
     │
     ▼
前端存储并跳转
```

---

## 数据库设计

### ER图

```
┌─────────────────────┐
│   admin_users       │
├─────────────────────┤
│ id (PK)             │
│ username            │◄───────┐
│ email               │        │
│ password_hash       │        │
│ full_name           │        │
│ is_active           │        │
│ is_super_admin      │        │
│ auth_provider       │        │  1:N
│ parent_id (FK)      │────────┘
│ level               │
│ hierarchy_path      │
│ mfa_enabled         │
│ data_isolation_level│
└─────────────────────┘
         │ 1
         │
         │ N
         ▼
┌─────────────────────┐
│   user_roles        │
├─────────────────────┤
│ id (PK)             │
│ user_id (FK)        │
│ role_id (FK)        │
└─────────────────────┘
         │ N
         │
         │ 1
         ▼
┌─────────────────────┐         ┌─────────────────────┐
│     roles           │    1    │  role_permissions   │
├─────────────────────┤─────────┤─────────────────────┤
│ id (PK)             │    N    │ id (PK)             │
│ name                │         │ role_id (FK)        │
│ code                │         │ permission_id (FK)  │
│ description         │         └─────────────────────┘
│ is_active           │                  │ N
└─────────────────────┘                  │
                                         │ 1
                                         ▼
                                ┌─────────────────────┐
                                │   permissions       │
                                ├─────────────────────┤
                                │ id (PK)             │
                                │ name                │
                                │ code                │
                                │ resource            │
                                │ action              │
                                │ description         │
                                │ is_active           │
                                └─────────────────────┘

┌─────────────────────┐
│ feishu_auth_users   │
├─────────────────────┤
│ id (PK)             │
│ admin_user_id (FK)  │────► admin_users.id
│ feishu_user_id      │
│ feishu_union_id     │
│ feishu_open_id      │
│ feishu_name         │
│ feishu_email        │
│ feishu_avatar_url   │
│ last_sync_at        │
│ sync_enabled        │
└─────────────────────┘

┌─────────────────────┐
│ feishu_app_configs  │
├─────────────────────┤
│ id (PK)             │
│ app_name            │
│ app_id              │
│ app_secret          │
│ is_active           │
│ auto_create_user    │
│ default_role_codes[]│
│ allowed_domains[]   │
└─────────────────────┘
```

### 核心表结构说明

#### 1. admin_users (管理员用户表)

```sql
CREATE TABLE mgmt.admin_users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    is_super_admin BOOLEAN DEFAULT FALSE,
    last_login_at TIMESTAMP,
    last_login_ip VARCHAR(45),

    -- 用户层级字段
    parent_id INTEGER REFERENCES mgmt.admin_users(id),
    level INTEGER DEFAULT 0 NOT NULL,
    hierarchy_path TEXT DEFAULT '',

    -- 安全策略字段
    data_isolation_level VARCHAR(20) DEFAULT 'none' NOT NULL,
    enable_data_masking BOOLEAN DEFAULT FALSE NOT NULL,
    mfa_enabled BOOLEAN DEFAULT FALSE NOT NULL,

    -- 认证提供方
    auth_provider VARCHAR(20) DEFAULT 'local' NOT NULL,
    -- 可选值: 'local', 'feishu', 'mixed'

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**关键字段说明**:
- `password_hash`: 使用 Werkzeug 的 `generate_password_hash` 加密
- `auth_provider`: 认证提供方，支持本地、飞书、混合认证
- `parent_id`: 支持管理员层级结构
- `hierarchy_path`: 层级路径，便于查询所有下级用户
- `data_isolation_level`: 数据隔离级别 (none/department/team/personal)
- `mfa_enabled`: 是否启用多因素认证

#### 2. roles (角色表)

```sql
CREATE TABLE mgmt.roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    code VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**特点**:
- `code`: 角色代码，用于程序化权限检查 (如: `super_admin`, `operator`)
- `name`: 角色显示名称
- `is_active`: 支持软删除，可禁用角色而不删除

#### 3. permissions (权限表)

```sql
CREATE TABLE mgmt.permissions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    code VARCHAR(100) NOT NULL UNIQUE,
    resource VARCHAR(50),    -- 资源类型
    action VARCHAR(50),      -- 操作类型
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**权限命名规范**:
- `code`: 格式为 `{resource}_{action}` (如: `customer_read`, `sms_send`)
- `resource`: 资源名称 (如: customer, sms, channel)
- `action`: 操作名称 (如: read, create, update, delete)

#### 4. feishu_auth_users (飞书认证用户表)

```sql
CREATE TABLE mgmt.feishu_auth_users (
    id SERIAL PRIMARY KEY,
    admin_user_id INTEGER NOT NULL REFERENCES mgmt.admin_users(id),
    feishu_user_id VARCHAR(64) NOT NULL UNIQUE,
    feishu_union_id VARCHAR(64),
    feishu_open_id VARCHAR(64),
    feishu_name VARCHAR(100),
    feishu_email VARCHAR(100),
    feishu_avatar_url VARCHAR(500),
    feishu_department_ids TEXT[],
    last_sync_at TIMESTAMP,
    sync_enabled BOOLEAN DEFAULT TRUE,
    sync_errors TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**关键字段**:
- `feishu_user_id`: 飞书用户唯一标识
- `feishu_union_id`: 飞书Union ID，跨应用统一用户标识
- `last_sync_at`: 最后同步时间，用于定期更新用户信息
- `sync_enabled`: 是否启用自动同步

---

## 后端认证实现

### 核心服务类

#### 1. AuthService (app/services/auth/service/auth.py)

**主要功能**:

##### 用户认证
```python
@staticmethod
def authenticate_user(username, password):
    """验证用户凭证"""
    # 支持用户名或邮箱登录
    user = AdminUser.query.filter(
        db.or_(
            AdminUser.username == username,
            AdminUser.email == username
        )
    ).first()

    if not user or not user.is_active:
        return None

    # 验证密码
    if not user.check_password(password):
        return None

    return user
```

##### Token生成
```python
@staticmethod
def generate_tokens(user):
    """生成访问令牌和刷新令牌"""
    # 构建Token payload
    identity = {
        'user_id': user.id,
        'username': user.username,
        'email': user.email,
        'is_super_admin': user.is_super_admin,
        'roles': [role.code for role in user.get_roles()],
        'permissions': [perm.code for perm in user.get_permissions()]
    }

    # 生成Access Token (1小时有效期)
    access_token = create_access_token(
        identity=str(user.id),
        additional_claims=identity,
        expires_delta=timedelta(seconds=3600)
    )

    # 生成Refresh Token (24小时有效期)
    refresh_token = create_refresh_token(
        identity=user.id,
        expires_delta=timedelta(seconds=86400)
    )

    return {
        'access_token': access_token,
        'refresh_token': refresh_token,
        'expires_in': 3600
    }
```

##### Token刷新
```python
@staticmethod
def refresh_access_token(refresh_token):
    """使用刷新令牌获取新的访问令牌"""
    decoded = decode_token(refresh_token)
    user_id = decoded['sub']

    # 检查Token是否被撤销
    jti = decoded['jti']
    if AuthService._is_token_blacklisted(jti):
        return None

    # 获取最新用户信息
    user = AdminUser.query.get(user_id)
    if not user or not user.is_active:
        return None

    # 生成新的Access Token
    # ... (同generate_tokens)
```

##### Token撤销 (黑名单机制)
```python
@staticmethod
def revoke_token(token_jti):
    """撤销Token (加入黑名单)"""
    access_expires = current_app.config.get('JWT_ACCESS_TOKEN_EXPIRES', 3600)
    cache.set(f'blacklisted_token_{token_jti}', True, timeout=access_expires)

@staticmethod
def _is_token_blacklisted(token_jti):
    """检查Token是否在黑名单中"""
    return cache.get(f'blacklisted_token_{token_jti}') is not None
```

#### 2. PermissionService (app/services/auth/service/auth.py)

**主要功能**:

##### 权限检查
```python
@staticmethod
def check_permission_by_code(user, permission_code):
    """检查用户是否拥有指定权限"""
    if not user or not user.is_active:
        return False

    # 超级管理员拥有所有权限
    if user.is_super_admin:
        return True

    # 从用户角色中获取权限
    user_permissions = user.get_permissions()
    user_codes = {p.code for p in user_permissions}

    return permission_code in user_codes
```

##### 角色管理
```python
@staticmethod
def assign_role_to_user(user_id, role_id):
    """为用户分配角色"""
    # 检查是否已存在
    existing = UserRole.query.filter_by(
        user_id=user_id,
        role_id=role_id
    ).first()

    if existing:
        return True

    # 创建关联
    user_role = UserRole(user_id=user_id, role_id=role_id)
    db.session.add(user_role)
    db.session.commit()

    # 清除权限缓存
    user = AdminUser.query.get(user_id)
    if user:
        user.clear_permissions_cache()

    return True
```

##### 权限树构建
```python
@staticmethod
def get_permission_tree():
    """获取权限树结构 (按资源分组)"""
    tree = Permission.build_permission_tree()

    return {
        'success': True,
        'data': tree,
        'total_resources': len(tree),
        'total_permissions': sum(len(r['permissions']) for r in tree)
    }
```

#### 3. FeishuAuthService (app/services/feishu/service/feishu_auth.py)

**主要功能**:

##### 获取授权URL
```python
@classmethod
def get_authorization_url(cls, app_id: str, redirect_uri: str, state: str = None):
    """生成飞书授权URL"""
    params = {
        'app_id': app_id,
        'redirect_uri': redirect_uri,
        'response_type': 'code',
        'scope': 'user:read'
    }

    if state:
        params['state'] = state
        # 缓存state用于回调验证 (防CSRF)
        cache_key = f"{cls.AUTH_STATE_CACHE_PREFIX}_{state}"
        cache.set(cache_key, app_id, timeout=600)  # 10分钟

    return f"{cls.FEISHU_AUTH_BASE}/index?{urlencode(params)}"
```

##### 完整认证流程
```python
@classmethod
def authenticate_with_code(cls, app_id: str, code: str, state: str = None):
    """使用授权码完成认证"""
    # 1. 获取应用配置
    app_config = cls.get_app_config(app_id)

    # 2. 验证state参数
    if state and not cls.verify_auth_state(state, app_id):
        raise FeishuAuthException("Invalid state parameter")

    # 3. 用code换取access_token
    token_data = cls.exchange_code_for_token(
        app_config.app_id,
        app_config.app_secret,
        code
    )

    # 4. 获取用户信息
    user_info = cls.get_user_info(token_data['access_token'])

    # 5. 验证邮箱域名
    email = user_info.get('email')
    if email and not cls.validate_user_domain(email, app_config.allowed_domains):
        raise FeishuAuthException("Email domain not allowed")

    # 6. 查找或创建用户
    feishu_user_id = user_info.get('user_id')
    admin_user = cls.find_user_by_feishu_id(feishu_user_id)

    if not admin_user:
        if app_config.auto_create_user:
            admin_user = cls.create_admin_user_from_feishu(user_info, app_config)
        else:
            raise FeishuAuthException("User not found")

    # 7. 同步用户信息
    cls.sync_user_info(admin_user, user_info)

    # 8. 生成JWT Token
    tokens = AuthService.generate_tokens(admin_user)

    return admin_user, tokens
```

### 认证装饰器

#### 位置: app/decorators/auth.py

##### 1. @login_required
```python
def login_required(f):
    """要求用户登录"""
    @wraps(f)
    @jwt_required()
    def decorated_function(*args, **kwargs):
        current_user = AuthService.get_current_user()
        if not current_user:
            return error_response('Authentication required', 401)

        kwargs.setdefault('current_user', current_user)
        return f(*args, **kwargs)

    return decorated_function
```

##### 2. @permission_required
```python
def permission_required(permission_code=None, resource=None, action=None):
    """要求特定权限"""
    def decorator(f):
        @wraps(f)
        @jwt_required()
        def decorated_function(*args, **kwargs):
            current_user = AuthService.get_current_user()

            # 超级管理员跳过权限检查
            if current_user.has_role('super_admin'):
                return f(*args, **kwargs)

            # 检查权限
            if permission_code:
                has_permission = PermissionService.check_permission_by_code(
                    current_user, permission_code
                )
            elif resource and action:
                has_permission = PermissionService.check_permission(
                    current_user, resource, action
                )
            else:
                return error_response('Invalid permission configuration', 500)

            if not has_permission:
                return error_response('Insufficient permissions', 403)

            return f(*args, **kwargs)

        return decorated_function
    return decorator
```

##### 3. @super_admin_required
```python
def super_admin_required(f):
    """要求超级管理员权限"""
    @wraps(f)
    @jwt_required()
    def decorated_function(*args, **kwargs):
        current_user = AuthService.get_current_user()

        if not current_user.has_role('super_admin'):
            return error_response('Super admin privilege required', 403)

        kwargs.setdefault('current_user', current_user)
        return f(*args, **kwargs)

    return decorated_function
```

##### 4. @role_required
```python
def role_required(role_code):
    """要求特定角色"""
    def decorator(f):
        @wraps(f)
        @jwt_required()
        def decorated_function(*args, **kwargs):
            current_user = AuthService.get_current_user()

            # 超级管理员拥有所有角色
            if current_user.has_role('super_admin'):
                return f(*args, **kwargs)

            # 检查角色
            user_roles = [role.code for role in current_user.get_roles()]
            if role_code not in user_roles:
                return error_response(f'Role "{role_code}" required', 403)

            return f(*args, **kwargs)

        return decorated_function
    return decorator
```

##### 5. @optional_auth
```python
def optional_auth(f):
    """可选认证 (允许匿名访问)"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        current_user = None

        try:
            verify_jwt_in_request(optional=True)
            current_user = AuthService.get_current_user()
        except Exception:
            pass

        kwargs.setdefault('current_user', current_user)
        return f(*args, **kwargs)

    return decorated_function
```

### API端点示例

```python
# app/api/v1/auth/routes/auth_routes.py

@auth_bp.route('/login', methods=['POST'])
def login():
    """用户登录"""
    data = request.get_json()

    # 验证用户凭证
    user = AuthService.authenticate_user(
        data.get('username'),
        data.get('password')
    )

    if not user:
        return error_response('Invalid credentials', 401)

    # 生成Token
    tokens = AuthService.generate_tokens(user)

    # 更新登录信息
    user.update_login_info(request.remote_addr)
    db.session.commit()

    return success_response(
        message='Login successful',
        data={
            'user': user.to_dict(),
            'access_token': tokens['access_token'],
            'refresh_token': tokens['refresh_token'],
            'expires_in': tokens['expires_in']
        }
    )

@auth_bp.route('/logout', methods=['POST'])
@login_required
def logout(current_user):
    """用户登出"""
    # 获取当前Token的JTI并加入黑名单
    jti = get_jwt()['jti']
    AuthService.revoke_token(jti)

    return success_response(message='Logout successful')

@auth_bp.route('/refresh', methods=['POST'])
def refresh_token():
    """刷新访问令牌"""
    data = request.get_json()
    refresh_token = data.get('refresh_token')

    result = AuthService.refresh_access_token(refresh_token)

    if not result:
        return error_response('Invalid or expired refresh token', 401)

    return success_response(
        message='Token refreshed successfully',
        data=result
    )

@auth_bp.route('/me', methods=['GET'])
@login_required
def get_current_user(current_user):
    """获取当前用户信息"""
    return success_response(data=current_user.to_dict())
```

---

## 前端认证实现

### 状态管理 (Redux)

#### authSlice.ts (frontend/src/store/slices/authSlice.ts)

**状态结构**:
```typescript
interface AuthState {
  user: User | null;
  accessToken: string | null;
  refreshToken: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  feishuAuth: {
    isLoading: boolean;
    error: string | null;
    authUrl: string | null;
    state: string | null;
  };
}
```

**核心Actions**:

##### 1. setCredentials
```typescript
setCredentials: (state, action: PayloadAction<{
  user: User;
  accessToken: string;
  refreshToken: string;
}>) => {
  const { user, accessToken, refreshToken } = action.payload;
  state.user = user;
  state.accessToken = accessToken;
  state.refreshToken = refreshToken;
  state.isAuthenticated = true;

  // 持久化到localStorage
  localStorage.setItem('access_token', accessToken);
  localStorage.setItem('refresh_token', refreshToken);
  localStorage.setItem('user_info', JSON.stringify(user));
}
```

##### 2. clearCredentials
```typescript
clearCredentials: (state) => {
  state.user = null;
  state.accessToken = null;
  state.refreshToken = null;
  state.isAuthenticated = false;

  // 清除localStorage
  localStorage.removeItem('access_token');
  localStorage.removeItem('refresh_token');
  localStorage.removeItem('user_info');
  sessionStorage.removeItem('feishu_oauth_state');
}
```

##### 3. initializeAuth
```typescript
initializeAuth: (state) => {
  const token = localStorage.getItem('access_token');
  const userInfo = localStorage.getItem('user_info');

  if (token && userInfo) {
    try {
      const parsedUser = JSON.parse(userInfo);
      state.user = parsedUser;
      state.accessToken = token;
      state.refreshToken = localStorage.getItem('refresh_token');
      state.isAuthenticated = true;
    } catch (error) {
      // 解析失败，清除无效数据
      authSlice.caseReducers.clearCredentials(state);
    }
  }
}
```

### API请求层

#### authApi.ts (frontend/src/api/authApi.ts)

使用 RTK Query 实现API请求:

```typescript
export const authApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    login: builder.mutation<LoginResponse, LoginRequest>({
      query: (credentials) => ({
        url: '/auth/login',
        method: 'POST',
        body: credentials,
      }),
      transformResponse: (response: LoginApiResponse): LoginResponse => {
        return transformLoginResponse(response);
      },
      invalidatesTags: ['Auth'],
    }),

    logout: builder.mutation<void, void>({
      query: () => ({
        url: '/auth/logout',
        method: 'POST',
      }),
      invalidatesTags: ['Auth'],
    }),

    refreshToken: builder.mutation<LoginResponse, RefreshTokenRequest>({
      query: (data) => ({
        url: '/auth/refresh',
        method: 'POST',
        body: data,
      }),
      invalidatesTags: ['Auth'],
    }),

    getCurrentUser: builder.query<User, void>({
      query: () => '/auth/me',
      providesTags: ['Auth'],
    }),
  }),
});
```

### 路由守卫

#### ProtectedRoute.tsx (frontend/src/components/ProtectedRoute.tsx)

```typescript
export const ProtectedRoute: React.FC<ProtectedRouteProps> = ({
  children,
  permissions = []
}) => {
  const location = useLocation();
  const dispatch = useDispatch();
  const { isAuthenticated, user, isLoading } = useSelector(
    (state: RootState) => state.auth
  );

  // 初始化认证状态
  useEffect(() => {
    if (!isAuthenticated && !isLoading) {
      dispatch(initializeAuth());
    }
  }, [dispatch, isAuthenticated, isLoading]);

  // 加载中显示
  if (isLoading) {
    return <Spin size="large" />;
  }

  // 未认证跳转登录页
  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  // 权限检查
  if (permissions.length > 0 && user) {
    const isSuperAdmin = user.roles?.includes('super_admin') || false;

    if (!isSuperAdmin) {
      const hasPermission = permissions.some(permission =>
        user.permissions.includes(permission)
      );

      if (!hasPermission) {
        return <Navigate to="/unauthorized" replace />;
      }
    }
  }

  return <>{children}</>;
};
```

### Token自动刷新机制

#### baseApi.ts 中实现

```typescript
const baseQuery = fetchBaseQuery({
  baseUrl: API_BASE_URL,
  prepareHeaders: (headers, { getState }) => {
    const token = (getState() as RootState).auth.accessToken;
    if (token) {
      headers.set('authorization', `Bearer ${token}`);
    }
    return headers;
  },
});

const baseQueryWithReauth = async (args, api, extraOptions) => {
  let result = await baseQuery(args, api, extraOptions);

  // Token过期，尝试刷新
  if (result.error && result.error.status === 401) {
    const refreshToken = (api.getState() as RootState).auth.refreshToken;

    if (refreshToken) {
      // 尝试刷新Token
      const refreshResult = await baseQuery(
        {
          url: '/auth/refresh',
          method: 'POST',
          body: { refresh_token: refreshToken }
        },
        api,
        extraOptions
      );

      if (refreshResult.data) {
        // 刷新成功，更新Token
        api.dispatch(updateTokens(refreshResult.data));

        // 重试原始请求
        result = await baseQuery(args, api, extraOptions);
      } else {
        // 刷新失败，清除认证信息
        api.dispatch(clearCredentials());
        window.location.href = '/login';
      }
    }
  }

  return result;
};
```

---

## 安全机制

### 1. 密码安全

#### 密码哈希
- 使用 **Werkzeug** 的 `generate_password_hash` 和 `check_password_hash`
- 默认使用 **pbkdf2:sha256** 算法
- 自动加盐处理

```python
# AdminUser Model
def set_password(self, password):
    """设置密码哈希"""
    self.password_hash = generate_password_hash(password)

def check_password(self, password):
    """验证密码"""
    return check_password_hash(self.password_hash, password)
```

#### 密码复杂度要求
- 最小长度: 8字符
- 建议包含大小写字母、数字和特殊字符

### 2. JWT Token安全

#### Token结构
```json
{
  "sub": "123",  // user_id
  "jti": "unique-token-id",
  "exp": 1234567890,
  "user_id": 123,
  "username": "admin",
  "email": "admin@example.com",
  "is_super_admin": false,
  "roles": ["operator"],
  "permissions": ["customer_read", "sms_send"]
}
```

#### 安全特性

**1. Token有效期**
- Access Token: 1小时 (短期，减少泄露风险)
- Refresh Token: 24小时 (长期，减少频繁登录)

**2. Token撤销 (黑名单)**
- 用户登出时，将Token JTI加入Redis黑名单
- 每次请求验证Token是否在黑名单中
- 黑名单条目自动过期 (与Token有效期同步)

**3. Token刷新机制**
- 使用Refresh Token获取新的Access Token
- Refresh Token一次性使用 (可选实现)
- 前端自动检测Token过期并刷新

### 3. CSRF防护

#### 飞书OAuth2.0中的State参数
```python
# 生成授权URL时
state = generate_random_state()
cache.set(f'auth_state_{state}', app_id, timeout=600)

# 回调验证时
cached_app_id = cache.get(f'auth_state_{state}')
if cached_app_id != app_id:
    raise FeishuAuthException("Invalid state parameter")

# 验证后立即删除
cache.delete(f'auth_state_{state}')
```

### 4. SQL注入防护

- 使用 **SQLAlchemy ORM**，自动参数化查询
- 避免原始SQL语句拼接
- 所有用户输入进行参数绑定

```python
# 安全的查询方式
user = AdminUser.query.filter_by(username=username).first()

# 避免这样做:
# query = f"SELECT * FROM users WHERE username = '{username}'"
```

### 5. XSS防护

#### 后端
- 使用 **Marshmallow** 进行输入验证和清理
- API返回JSON数据，前端负责渲染

#### 前端
- React默认转义所有输出
- 使用 `dangerouslySetInnerHTML` 时需格外注意
- 使用 **DOMPurify** 清理用户输入的HTML (如果需要)

### 6. 权限缓存

#### 用户权限缓存
```python
def get_permissions(self):
    """获取用户权限 (带缓存)"""
    cache_key = f'user_permissions_{self.id}'
    cached_permissions = cache.get(cache_key)

    if cached_permissions is not None:
        return cached_permissions

    # 从数据库加载
    permissions = []
    for role in self.get_roles():
        permissions.extend(role.get_permissions())

    # 缓存5分钟
    cache.set(cache_key, permissions, timeout=300)
    return permissions

def clear_permissions_cache(self):
    """清除权限缓存"""
    cache_key = f'user_permissions_{self.id}'
    cache.delete(cache_key)
```

**缓存失效策略**:
- 角色权限变更时，清除所有该角色用户的权限缓存
- 用户角色变更时，清除该用户的权限缓存
- 定期刷新 (5分钟TTL)

### 7. 数据隔离

#### 多级数据隔离
```python
# AdminUser Model
data_isolation_level = Column(
    String(20),
    default='none',
    nullable=False
)
# 可选值:
# - 'none': 无隔离，可访问所有数据
# - 'department': 部门级隔离，只能访问本部门数据
# - 'team': 团队级隔离，只能访问本团队数据
# - 'personal': 个人级隔离，只能访问自己创建的数据
```

#### 实现示例
```python
def get_accessible_accounts(user):
    """获取用户可访问的账户列表"""
    if user.is_super_admin or user.data_isolation_level == 'none':
        return Account.query.all()

    if user.data_isolation_level == 'department':
        # 根据用户部门筛选
        return Account.query.filter_by(department_id=user.department_id).all()

    if user.data_isolation_level == 'team':
        # 根据用户团队筛选
        return Account.query.filter_by(team_id=user.team_id).all()

    if user.data_isolation_level == 'personal':
        # 只返回用户自己创建的
        return Account.query.filter_by(created_by=user.id).all()
```

### 8. 审计日志

#### OperationLog表
```sql
CREATE TABLE mgmt.operation_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    request_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    resource VARCHAR(100) NOT NULL,
    resource_id VARCHAR(50),
    method VARCHAR(10) NOT NULL,
    url VARCHAR(500) NOT NULL,
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    request_body TEXT,
    response_status INTEGER,
    execution_time INTEGER,  -- 毫秒
    success BOOLEAN DEFAULT TRUE,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**记录内容**:
- 用户身份
- 操作类型 (create/update/delete)
- 资源类型和ID
- 请求详情 (URL, Method, Body)
- 响应状态
- 执行时间
- 错误信息

---

## 飞书集成认证

### OAuth2.0流程

```
┌────────┐                               ┌─────────────┐
│ Client │                               │Feishu Server│
└───┬────┘                               └──────┬──────┘
    │                                           │
    │  1. Request Authorization URL             │
    ├──────────────────────────────────────────►│
    │                                           │
    │  2. Return Authorization URL              │
    │◄──────────────────────────────────────────┤
    │                                           │
    │  3. Redirect to Feishu Login              │
    ├──────────────────────────────────────────►│
    │                                           │
    │  4. User Login & Authorize                │
    │                                           │
    │  5. Redirect with Code & State            │
    │◄──────────────────────────────────────────┤
    │                                           │
    │  6. Exchange Code for Token               │
    ├──────────────────────────────────────────►│
    │                                           │
    │  7. Return Access Token & User Info       │
    │◄──────────────────────────────────────────┤
    │                                           │
    │  8. Create/Update Local User              │
    │                                           │
    │  9. Generate JWT Tokens                   │
    │                                           │
    │ 10. Return Tokens & User Info             │
    └───────────────────────────────────────────┘
```

### 配置管理

#### FeishuAppConfig表
```sql
CREATE TABLE mgmt.feishu_app_configs (
    id SERIAL PRIMARY KEY,
    app_name VARCHAR(100) NOT NULL UNIQUE,
    app_id VARCHAR(64) NOT NULL UNIQUE,
    app_secret VARCHAR(255) NOT NULL,
    encrypt_key VARCHAR(255),
    verification_token VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    auto_create_user BOOLEAN DEFAULT FALSE,
    default_role_codes TEXT[],      -- 自动创建用户时分配的默认角色
    allowed_domains TEXT[],         -- 允许的邮箱域名白名单
    webhook_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 用户映射策略

#### 1. 通过feishu_user_id查找
```python
admin_user = cls.find_user_by_feishu_id(feishu_user_id)
```

#### 2. 通过邮箱查找 (关联已有用户)
```python
if not admin_user and email:
    admin_user = cls.find_user_by_email(email)
    if admin_user:
        # 创建飞书认证关联
        feishu_auth = FeishuAuthUser(
            admin_user_id=admin_user.id,
            feishu_user_id=feishu_user_id,
            ...
        )
        admin_user.auth_provider = 'mixed'  # 支持本地+飞书登录
```

#### 3. 自动创建用户
```python
if not admin_user and app_config.auto_create_user:
    admin_user = cls.create_admin_user_from_feishu(user_info, app_config)
```

### 用户信息同步

#### 每次登录时同步
```python
@classmethod
def sync_user_info(cls, admin_user: AdminUser, user_info: Dict):
    """同步飞书用户信息到本地"""
    feishu_auth = admin_user.feishu_auth

    # 更新基本信息
    admin_user.full_name = user_info.get('name') or user_info.get('en_name')

    # 更新飞书信息
    feishu_auth.feishu_name = user_info.get('name')
    feishu_auth.feishu_email = user_info.get('email')
    feishu_auth.feishu_avatar_url = user_info.get('avatar_url')
    feishu_auth.last_sync_at = datetime.utcnow()

    db.session.commit()
```

### 域名白名单

#### 配置示例
```python
allowed_domains = ['example.com', 'company.com']
```

#### 验证逻辑
```python
@classmethod
def validate_user_domain(cls, email: str, allowed_domains: List[str]):
    """验证用户邮箱域名"""
    if not allowed_domains:
        return True  # 无限制

    if not email or '@' not in email:
        return False

    domain = email.split('@')[1].lower()
    return domain in [d.lower() for d in allowed_domains]
```

---

## 权限控制系统

### RBAC模型

```
User ←──→ UserRole ←──→ Role ←──→ RolePermission ←──→ Permission
```

#### 核心概念

**User (用户)**
- 系统的实际使用者
- 可以拥有多个角色
- 通过角色获得权限

**Role (角色)**
- 权限的集合
- 如: super_admin, operator, viewer
- 一个用户可以有多个角色

**Permission (权限)**
- 最小权限单元
- 格式: `{resource}_{action}`
- 如: `customer_read`, `sms_send`, `channel_delete`

### 权限命名规范

#### 格式
```
{resource}_{action}
```

#### 资源类型 (resource)
- `customer`: 客户管理
- `sms`: 短信管理
- `channel`: 通道管理
- `account`: 账户管理
- `admin_user`: 管理员用户
- `role`: 角色管理
- `permission`: 权限管理

#### 操作类型 (action)
- `read`: 查看/读取
- `create`: 创建
- `update`: 更新/编辑
- `delete`: 删除
- `execute`: 执行特殊操作
- `export`: 导出数据
- `import`: 导入数据

#### 示例
```
customer_read          # 查看客户
customer_create        # 创建客户
customer_update        # 更新客户
customer_delete        # 删除客户
customer_export        # 导出客户数据

sms_send              # 发送短信
sms_read              # 查看短信记录
sms_test              # 测试发送

channel_read          # 查看通道
channel_create        # 创建通道
channel_update        # 更新通道
channel_delete        # 删除通道
channel_test          # 测试通道

admin_user_read       # 查看管理员
admin_user_create     # 创建管理员
admin_user_update     # 更新管理员
admin_user_delete     # 删除管理员
admin_user_simulate_login  # 模拟登录
admin_user_reset_password  # 重置密码

role_read             # 查看角色
role_create           # 创建角色
role_update           # 更新角色
role_delete           # 删除角色
role_assign           # 分配角色
```

### 权限检查流程

#### 后端检查
```python
@permission_required('customer_read')
def get_customers(current_user):
    """获取客户列表"""
    # 1. 装饰器先检查用户是否有 customer_read 权限
    # 2. 检查通过后执行业务逻辑
    customers = Customer.query.all()
    return success_response(data=[c.to_dict() for c in customers])
```

#### 检查逻辑
```python
def check_permission_by_code(user, permission_code):
    # 1. 检查用户是否激活
    if not user.is_active:
        return False

    # 2. 超级管理员拥有所有权限
    if user.is_super_admin:
        return True

    # 3. 获取用户所有权限 (通过角色)
    user_permissions = user.get_permissions()
    user_codes = {p.code for p in user_permissions}

    # 4. 检查是否包含所需权限
    return permission_code in user_codes
```

#### 前端权限检查
```typescript
// 路由级权限
<ProtectedRoute permissions={['customer_read']}>
  <CustomerListPage />
</ProtectedRoute>

// 按钮级权限
{user.permissions.includes('customer_create') && (
  <Button onClick={handleCreate}>创建客户</Button>
)}

// 功能级权限
const canEdit = user.permissions.includes('customer_update');
const canDelete = user.permissions.includes('customer_delete');
```

### 权限树结构

#### 按资源分组的权限树
```json
[
  {
    "resource": "customer",
    "label": "客户管理",
    "permissions": [
      {
        "id": 1,
        "name": "查看客户",
        "code": "customer_read",
        "action": "read"
      },
      {
        "id": 2,
        "name": "创建客户",
        "code": "customer_create",
        "action": "create"
      },
      {
        "id": 3,
        "name": "更新客户",
        "code": "customer_update",
        "action": "update"
      },
      {
        "id": 4,
        "name": "删除客户",
        "code": "customer_delete",
        "action": "delete"
      }
    ]
  },
  {
    "resource": "sms",
    "label": "短信管理",
    "permissions": [
      {
        "id": 5,
        "name": "查看短信",
        "code": "sms_read",
        "action": "read"
      },
      {
        "id": 6,
        "name": "发送短信",
        "code": "sms_send",
        "action": "send"
      }
    ]
  }
]
```

### 角色预设

#### 1. super_admin (超级管理员)
- 拥有所有权限
- 跳过所有权限检查
- 不可删除
- 不可被移除角色

#### 2. operator (操作员)
- 日常运营权限
- 可以查看和操作业务数据
- 不能管理系统配置

#### 3. viewer (查看者)
- 只读权限
- 可以查看所有数据
- 不能进行任何修改操作

### 权限管理API

#### 1. 获取权限树
```
GET /api/v1/permissions/tree
```

#### 2. 获取角色权限
```
GET /api/v1/roles/{role_id}/permissions
```

#### 3. 为角色分配权限
```
POST /api/v1/roles/{role_id}/permissions
Body: {
  "permission_ids": [1, 2, 3, 4]
}
```

#### 4. 为用户分配角色
```
POST /api/v1/users/{user_id}/roles
Body: {
  "role_ids": [1, 2]
}
```

---

## 附录

### 配置示例

#### Flask配置 (app/config.py)
```python
class Config:
    # JWT配置
    JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY', 'your-secret-key')
    JWT_ACCESS_TOKEN_EXPIRES = 3600  # 1小时
    JWT_REFRESH_TOKEN_EXPIRES = 86400  # 24小时

    # 数据库配置
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL')
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Redis配置 (用于缓存和Token黑名单)
    CACHE_TYPE = 'redis'
    CACHE_REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
    CACHE_REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))
    CACHE_REDIS_DB = int(os.environ.get('REDIS_DB', 0))
    CACHE_DEFAULT_TIMEOUT = 300  # 5分钟
```

### 环境变量

```bash
# 数据库
DATABASE_URL=postgresql://user:password@localhost:5432/pigeon_sms

# JWT
JWT_SECRET_KEY=your-very-secret-key-change-in-production

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# 飞书应用配置 (可选，也可通过数据库配置)
FEISHU_APP_ID=your-feishu-app-id
FEISHU_APP_SECRET=your-feishu-app-secret
```

### 常见问题

#### 1. Token过期如何处理？
**问题**: Access Token过期导致401错误

**解决方案**:
- 前端自动使用Refresh Token获取新的Access Token
- 如果Refresh Token也过期，跳转到登录页
- 实现代码见 `baseQueryWithReauth` 函数

#### 2. 如何撤销已发放的Token？
**问题**: 用户登出后Token仍然有效

**解决方案**:
- 使用Token黑名单机制
- 登出时将Token JTI加入Redis黑名单
- 每次请求验证Token是否在黑名单中

#### 3. 权限更新后何时生效？
**问题**: 修改角色权限后，已登录用户的权限没有更新

**解决方案**:
- Token中包含的权限信息在Token过期前不会更新
- 方案1: 强制用户重新登录 (撤销所有Token)
- 方案2: 实时权限检查 (不依赖Token中的权限，每次从数据库查询)
- 方案3: 缩短Token有效期 (如15分钟)

#### 4. 飞书用户如何关联已有账户？
**问题**: 飞书用户首次登录时，希望关联已有的本地账户

**解决方案**:
- 系统自动通过邮箱匹配
- 如果邮箱相同，自动关联并将auth_provider改为'mixed'
- 用户可以同时使用密码和飞书登录

#### 5. 如何实现单点登录(SSO)？
**问题**: 希望用户在多个子系统间无需重复登录

**解决方案**:
- 使用飞书OAuth2.0作为统一认证入口
- 各子系统信任飞书Token
- 或建立统一认证中心，颁发统一Token

### 安全最佳实践

1. **生产环境必做**:
   - ✅ 更改默认的JWT_SECRET_KEY
   - ✅ 使用HTTPS
   - ✅ 启用CORS白名单
   - ✅ 配置合理的Token有效期
   - ✅ 定期审计操作日志
   - ✅ 定期备份数据库

2. **推荐配置**:
   - ✅ 启用MFA (多因素认证)
   - ✅ 配置IP白名单
   - ✅ 限制API请求频率 (Rate Limiting)
   - ✅ 记录登录失败次数，锁定账户
   - ✅ 密码定期过期策略

3. **代码审查检查点**:
   - ✅ 所有API端点都有认证保护
   - ✅ 敏感操作都有权限检查
   - ✅ 用户输入都经过验证和清理
   - ✅ 不在日志中记录敏感信息 (密码、Token)
   - ✅ 错误信息不泄露系统内部信息

---

## 更新历史

| 版本 | 日期 | 更新内容 | 作者 |
|------|------|----------|------|
| v1.0 | 2025-10-15 | 初始版本，完整的认证系统设计文档 | Claude Code |

---

## 参考资料

- [Flask-JWT-Extended Documentation](https://flask-jwt-extended.readthedocs.io/)
- [飞书开放平台 - 身份验证](https://open.feishu.cn/document/common-capabilities/sso/web-application-sso)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [JWT Best Current Practices](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-jwt-bcp)
- [RBAC设计模式](https://en.wikipedia.org/wiki/Role-based_access_control)
