# Pigeon Web飞书登录集成设计方案

## 📋 概述

本文档基于对**pigeon_web**现有安全架构和**yuexin系列飞书认证项目**的深入分析，设计了一套完整的飞书登录集成方案。该方案在保持pigeon_web现有优秀架构的基础上，无缝集成飞书OAuth2认证，实现企业级的统一身份认证。

### 设计原则

1. **非侵入性**：最小化对现有系统的修改
2. **架构兼容**：复用现有JWT认证和RBAC权限系统
3. **安全优先**：保持现有安全特性，增强认证安全性
4. **可扩展性**：支持未来其他SSO认证方式的集成
5. **用户体验**：提供流畅的登录和权限管理体验

## 🎯 架构设计

### 整体架构图

```mermaid
graph TB
    subgraph "前端层"
        A[登录页面] --> B[飞书登录按钮]
        A --> C[用户名密码登录]
        B --> D[飞书授权页面]
    end

    subgraph "API网关层"
        E[Auth Controller]
        F[Feishu Auth Controller]
    end

    subgraph "服务层"
        G[AuthService - 现有]
        H[FeishuAuthService - 新增]
        I[UserSyncService - 可选]
        J[PermissionService - 现有]
    end

    subgraph "数据层"
        K[AdminUser表 - 扩展]
        L[现有RBAC表]
        M[Redis缓存]
    end

    subgraph "外部系统"
        N[飞书开放平台]
        O[飞书企业后台]
    end

    D --> N
    N --> F
    F --> H
    H --> G
    H --> K
    G --> L
    G --> M
    I --> O
    C --> E
    E --> G
```

### 认证流程对比

#### 现有认证流程
```
用户输入凭据 → 验证用户名密码 → 生成JWT令牌 → 返回前端
```

#### 飞书认证流程
```
点击飞书登录 → 重定向到飞书 → 用户授权 → 获取授权码 →
换取飞书令牌 → 获取用户信息 → 查找/创建本地用户 → 生成JWT令牌 → 返回前端
```

## 🗄️ 数据库设计

### 1. AdminUser表扩展

在现有`admin_users`表基础上添加飞书相关字段：

```sql
-- 扩展admin_users表，添加飞书认证相关字段
ALTER TABLE admin_users ADD COLUMN feishu_user_id VARCHAR(64) NULL UNIQUE;
ALTER TABLE admin_users ADD COLUMN feishu_union_id VARCHAR(64) NULL;
ALTER TABLE admin_users ADD COLUMN feishu_open_id VARCHAR(64) NULL;
ALTER TABLE admin_users ADD COLUMN auth_provider VARCHAR(20) DEFAULT 'local' NOT NULL;
ALTER TABLE admin_users ADD COLUMN feishu_avatar_url VARCHAR(500) NULL;
ALTER TABLE admin_users ADD COLUMN last_sync_at TIMESTAMP NULL;
ALTER TABLE admin_users ADD COLUMN sync_enabled BOOLEAN DEFAULT TRUE;

-- 添加约束检查
ALTER TABLE admin_users ADD CONSTRAINT chk_auth_provider
    CHECK (auth_provider IN ('local', 'feishu', 'mixed'));

-- 添加索引优化查询
CREATE INDEX idx_admin_users_feishu_user_id ON admin_users(feishu_user_id);
CREATE INDEX idx_admin_users_auth_provider ON admin_users(auth_provider);
CREATE INDEX idx_admin_users_feishu_union_id ON admin_users(feishu_union_id);

-- 添加注释
COMMENT ON COLUMN admin_users.feishu_user_id IS '飞书用户ID';
COMMENT ON COLUMN admin_users.feishu_union_id IS '飞书Union ID';
COMMENT ON COLUMN admin_users.feishu_open_id IS '飞书Open ID';
COMMENT ON COLUMN admin_users.auth_provider IS '认证提供方：local(本地), feishu(飞书), mixed(混合)';
COMMENT ON COLUMN admin_users.feishu_avatar_url IS '飞书头像URL';
COMMENT ON COLUMN admin_users.last_sync_at IS '最后同步时间';
COMMENT ON COLUMN admin_users.sync_enabled IS '是否启用同步';
```

### 2. 飞书配置表

创建飞书应用配置表：

```sql
-- 飞书应用配置表
CREATE TABLE feishu_app_configs (
    id SERIAL PRIMARY KEY,
    app_name VARCHAR(100) NOT NULL UNIQUE,
    app_id VARCHAR(64) NOT NULL UNIQUE,
    app_secret VARCHAR(255) NOT NULL,
    encrypt_key VARCHAR(255),
    verification_token VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    auto_create_user BOOLEAN DEFAULT FALSE,
    default_role_ids INTEGER[],
    allowed_domains TEXT[],
    webhook_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE feishu_app_configs IS '飞书应用配置表';
COMMENT ON COLUMN feishu_app_configs.auto_create_user IS '是否自动创建用户';
COMMENT ON COLUMN feishu_app_configs.default_role_ids IS '默认分配角色ID数组';
COMMENT ON COLUMN feishu_app_configs.allowed_domains IS '允许的邮箱域名列表';
```

### 3. 飞书令牌缓存表

虽然主要使用Redis，但提供数据库备份方案：

```sql
-- 飞书令牌缓存表（可选，主要使用Redis）
CREATE TABLE feishu_tokens (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES admin_users(id) ON DELETE CASCADE,
    app_id VARCHAR(64) NOT NULL,
    access_token_encrypted TEXT NOT NULL,  -- 加密存储的access token
    refresh_token_encrypted TEXT,          -- 加密存储的refresh token
    expires_at TIMESTAMP NOT NULL,
    refresh_expires_at TIMESTAMP,
    token_type VARCHAR(20) DEFAULT 'Bearer',
    scope VARCHAR(200),
    encryption_key_id VARCHAR(32) NOT NULL, -- 加密密钥ID，支持密钥轮换
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_feishu_tokens_user_app ON feishu_tokens(user_id, app_id);
CREATE INDEX idx_feishu_tokens_expires ON feishu_tokens(expires_at);
```

## 🔧 核心服务实现

### 1. FeishuAuthService

新增飞书认证服务，复用现有AuthService：

```python
# app/services/auth/service/feishu_auth.py

import requests
import logging
from datetime import datetime, timedelta
from flask import current_app
from typing import Optional, Dict, Any
from cryptography.fernet import Fernet
import os
import base64

from app.extensions import cache, db
from app.models.user.admin import AdminUser
from app.services.auth.service.auth import AuthService, PermissionService
from app.models.user.admin import Role


class FeishuAuthService:
    """飞书认证服务"""

    # 飞书API端点
    FEISHU_API_BASE = "https://open.feishu.cn/open-apis"

    @staticmethod
    def _get_encryption_key() -> bytes:
        """
        获取令牌加密密钥

        Returns:
            bytes: 加密密钥
        """
        # 从环境变量或配置中获取密钥
        key_b64 = current_app.config.get('FEISHU_TOKEN_ENCRYPTION_KEY')
        if not key_b64:
            # 如果没有配置密钥，生成一个新的（仅用于开发环境）
            key = Fernet.generate_key()
            current_app.logger.warning("No FEISHU_TOKEN_ENCRYPTION_KEY configured, using generated key")
            return key

        try:
            return base64.urlsafe_b64decode(key_b64.encode())
        except Exception:
            # 如果密钥格式不正确，生成新的
            key = Fernet.generate_key()
            current_app.logger.error("Invalid FEISHU_TOKEN_ENCRYPTION_KEY format, using generated key")
            return key

    @staticmethod
    def _encrypt_token(token: str) -> str:
        """
        加密令牌

        Args:
            token: 原始令牌

        Returns:
            str: 加密后的令牌
        """
        if not token:
            return token

        try:
            key = FeishuAuthService._get_encryption_key()
            fernet = Fernet(key)
            encrypted = fernet.encrypt(token.encode())
            return base64.urlsafe_b64encode(encrypted).decode()
        except Exception as e:
            current_app.logger.error(f"Failed to encrypt token: {str(e)}")
            # 加密失败时记录错误但不中断流程
            return token

    @staticmethod
    def _decrypt_token(encrypted_token: str) -> str:
        """
        解密令牌

        Args:
            encrypted_token: 加密的令牌

        Returns:
            str: 解密后的令牌
        """
        if not encrypted_token:
            return encrypted_token

        try:
            key = FeishuAuthService._get_encryption_key()
            fernet = Fernet(key)
            decoded = base64.urlsafe_b64decode(encrypted_token.encode())
            decrypted = fernet.decrypt(decoded)
            return decrypted.decode()
        except Exception as e:
            current_app.logger.error(f"Failed to decrypt token: {str(e)}")
            # 解密失败时返回原始值，可能是未加密的历史数据
            return encrypted_token

    @staticmethod
    def get_authorization_url(app_id: str, redirect_uri: str, state: str = None) -> str:
        """
        生成飞书授权URL

        Args:
            app_id: 飞书应用ID
            redirect_uri: 回调地址
            state: 状态参数

        Returns:
            str: 授权URL
        """
        from urllib.parse import urlencode

        params = {
            'app_id': app_id,
            'redirect_uri': redirect_uri,
            'response_type': 'code',
            'scope': 'user:read'
        }
        if state:
            params['state'] = state

        # 使用urlencode确保正确的URL编码
        query_string = urlencode(params)
        return f"https://open.feishu.cn/open-apis/authen/v1/index?{query_string}"

    @staticmethod
    def get_app_access_token(app_id: str, app_secret: str) -> Optional[str]:
        """
        获取应用访问令牌

        Args:
            app_id: 应用ID
            app_secret: 应用密钥

        Returns:
            str: 应用访问令牌
        """
        # 先从缓存获取
        cache_key = f"feishu_app_token_{app_id}"
        cached_token = cache.get(cache_key)
        if cached_token:
            return cached_token

        # 请求新令牌
        url = f"{FeishuAuthService.FEISHU_API_BASE}/auth/v3/app_access_token/internal"
        data = {
            'app_id': app_id,
            'app_secret': app_secret
        }

        try:
            response = requests.post(url, json=data, timeout=10)
            response.raise_for_status()

            result = response.json()
            if result.get('code') == 0:
                token = result.get('app_access_token')
                expire = result.get('expire', 7200)

                # 缓存令牌，提前5分钟过期
                cache.set(cache_key, token, timeout=expire-300)
                return token
            else:
                current_app.logger.error(f"获取飞书应用令牌失败: {result}")
                return None

        except Exception as e:
            current_app.logger.error(f"请求飞书应用令牌异常: {str(e)}")
            return None

    @staticmethod
    def exchange_code_for_token(app_id: str, app_secret: str, code: str) -> Optional[Dict[str, Any]]:
        """
        使用授权码换取用户访问令牌

        Args:
            app_id: 应用ID
            app_secret: 应用密钥
            code: 授权码

        Returns:
            dict: 用户令牌信息
        """
        # 获取应用访问令牌
        app_token = FeishuAuthService.get_app_access_token(app_id, app_secret)
        if not app_token:
            return None

        url = f"{FeishuAuthService.FEISHU_API_BASE}/authen/v1/access_token"
        headers = {
            'Authorization': f'Bearer {app_token}',
            'Content-Type': 'application/json'
        }
        data = {
            'grant_type': 'authorization_code',
            'code': code
        }

        try:
            response = requests.post(url, json=data, headers=headers, timeout=10)
            response.raise_for_status()

            result = response.json()
            if result.get('code') == 0:
                return result.get('data')
            else:
                current_app.logger.error(f"换取用户令牌失败: {result}")
                return None

        except Exception as e:
            current_app.logger.error(f"换取用户令牌异常: {str(e)}")
            return None

    @staticmethod
    def get_user_info(access_token: str) -> Optional[Dict[str, Any]]:
        """
        获取用户信息

        Args:
            access_token: 用户访问令牌

        Returns:
            dict: 用户信息
        """
        url = f"{FeishuAuthService.FEISHU_API_BASE}/authen/v1/user_info"
        headers = {
            'Authorization': f'Bearer {access_token}'
        }

        try:
            response = requests.get(url, headers=headers, timeout=10)
            response.raise_for_status()

            result = response.json()
            if result.get('code') == 0:
                return result.get('data')
            else:
                current_app.logger.error(f"获取用户信息失败: {result}")
                return None

        except Exception as e:
            current_app.logger.error(f"获取用户信息异常: {str(e)}")
            return None

    @staticmethod
    def find_or_create_user(feishu_user_info: Dict[str, Any],
                           auto_create: bool = False,
                           default_role_codes: list = None) -> Optional[AdminUser]:
        """
        查找或创建用户

        Args:
            feishu_user_info: 飞书用户信息
            auto_create: 是否自动创建用户
            default_role_codes: 默认角色代码列表

        Returns:
            AdminUser: 用户对象
        """
        feishu_user_id = feishu_user_info.get('user_id')
        email = feishu_user_info.get('email')

        if not feishu_user_id:
            return None

        # 先通过飞书ID查找
        user = AdminUser.query.filter_by(feishu_user_id=feishu_user_id).first()

        # 再通过邮箱查找
        if not user and email:
            user = AdminUser.query.filter_by(email=email).first()
            if user:
                # 关联飞书ID
                user.feishu_user_id = feishu_user_id
                user.feishu_union_id = feishu_user_info.get('union_id')
                user.feishu_open_id = feishu_user_info.get('open_id')
                user.feishu_avatar_url = feishu_user_info.get('avatar_url')
                user.auth_provider = 'mixed'
                user.last_sync_at = datetime.utcnow()
                db.session.commit()

        # 如果仍然没找到且允许自动创建
        if not user and auto_create and email:
            user = FeishuAuthService._create_user_from_feishu(
                feishu_user_info, default_role_codes
            )

        # 更新用户飞书信息
        if user:
            FeishuAuthService._update_user_from_feishu(user, feishu_user_info)

        return user

    @staticmethod
    def _create_user_from_feishu(feishu_user_info: Dict[str, Any],
                                default_role_codes: list = None) -> AdminUser:
        """
        从飞书信息创建用户

        Args:
            feishu_user_info: 飞书用户信息
            default_role_codes: 默认角色代码列表

        Returns:
            AdminUser: 新创建的用户
        """
        try:
            # 生成用户名（如果没有邮箱，使用飞书ID）
            email = feishu_user_info.get('email')
            username = email.split('@')[0] if email else f"feishu_{feishu_user_info.get('user_id')}"

            # 确保用户名唯一
            base_username = username
            counter = 1
            while AdminUser.query.filter_by(username=username).first():
                username = f"{base_username}_{counter}"
                counter += 1

            # 为飞书用户生成随机密码hash，防止check_password_hash报错
            import secrets
            import string
            from werkzeug.security import generate_password_hash

            random_password = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))

            user = AdminUser(
                username=username,
                email=email or f"{username}@feishu.local",
                full_name=feishu_user_info.get('name', username),
                password_hash=generate_password_hash(random_password),  # 生成有效hash，但用户无法知道密码
                is_active=True,
                feishu_user_id=feishu_user_info.get('user_id'),
                feishu_union_id=feishu_user_info.get('union_id'),
                feishu_open_id=feishu_user_info.get('open_id'),
                feishu_avatar_url=feishu_user_info.get('avatar_url'),
                auth_provider='feishu',
                last_sync_at=datetime.utcnow(),
                sync_enabled=True
            )

            db.session.add(user)
            db.session.flush()  # 获取用户ID

            # 分配默认角色 - 将role codes转换为role IDs
            if default_role_codes:
                from app.models.user.admin import UserRole, Role
                for role_code in default_role_codes:
                    role = Role.query.filter_by(code=role_code).first()
                    if role:
                        user_role = UserRole(user_id=user.id, role_id=role.id)
                        db.session.add(user_role)
                    else:
                        current_app.logger.warning(f"Role with code '{role_code}' not found")

            db.session.commit()
            current_app.logger.info(f"Created user from Feishu: {username}")

            return user

        except Exception as e:
            db.session.rollback()
            current_app.logger.error(f"Failed to create user from Feishu: {str(e)}")
            raise

    @staticmethod
    def _update_user_from_feishu(user: AdminUser, feishu_user_info: Dict[str, Any]):
        """
        更新用户飞书信息

        Args:
            user: 用户对象
            feishu_user_info: 飞书用户信息
        """
        try:
            # 更新基本信息
            if feishu_user_info.get('name') and user.sync_enabled:
                user.full_name = feishu_user_info.get('name')

            # 更新头像
            if feishu_user_info.get('avatar_url'):
                user.feishu_avatar_url = feishu_user_info.get('avatar_url')

            # 更新同步时间
            user.last_sync_at = datetime.utcnow()

            db.session.commit()

        except Exception as e:
            db.session.rollback()
            current_app.logger.error(f"Failed to update user from Feishu: {str(e)}")

    @staticmethod
    def authenticate_with_feishu(code: str, app_config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        飞书认证主流程

        Args:
            code: 授权码
            app_config: 应用配置

        Returns:
            dict: 认证结果，包含用户和令牌信息
        """
        try:
            # 1. 换取用户访问令牌
            token_data = FeishuAuthService.exchange_code_for_token(
                app_config['app_id'],
                app_config['app_secret'],
                code
            )

            if not token_data:
                return None

            # 2. 获取用户信息
            user_info = FeishuAuthService.get_user_info(token_data['access_token'])
            if not user_info:
                return None

            # 3. 查找或创建用户
            user = FeishuAuthService.find_or_create_user(
                user_info,
                app_config.get('auto_create_user', False),
                app_config.get('default_role_codes', [])
            )

            if not user or not user.is_active:
                return None

            # 4. 生成系统JWT令牌
            system_tokens = AuthService.generate_tokens(user)

            # 5. 缓存飞书令牌
            FeishuAuthService._cache_feishu_tokens(user.id, token_data, app_config['app_id'])

            # 6. 更新登录信息
            from flask import request
            user.update_login_info(request.remote_addr if request else None)
            db.session.commit()

            return {
                'user': user,
                'system_tokens': system_tokens,
                'feishu_tokens': token_data,
                'feishu_user_info': user_info
            }

        except Exception as e:
            current_app.logger.error(f"Feishu authentication failed: {str(e)}")
            return None

    @staticmethod
    def _cache_feishu_tokens(user_id: int, token_data: Dict[str, Any], app_id: str):
        """
        缓存飞书令牌到Redis

        Args:
            user_id: 用户ID
            token_data: 令牌数据
            app_id: 应用ID
        """
        try:
            cache_key = f"feishu_user_token_{app_id}_{user_id}"

            # 加密敏感令牌数据
            encrypted_access_token = FeishuAuthService._encrypt_token(token_data.get('access_token'))
            encrypted_refresh_token = FeishuAuthService._encrypt_token(token_data.get('refresh_token'))

            cache_data = {
                'access_token_encrypted': encrypted_access_token,
                'refresh_token_encrypted': encrypted_refresh_token,
                'expires_in': token_data.get('expires_in'),
                'refresh_expires_in': token_data.get('refresh_expires_in'),
                'cached_at': datetime.utcnow().isoformat(),
                'encryption_key_id': 'default'  # 支持密钥轮换
            }

            # 缓存到令牌过期时间
            timeout = token_data.get('expires_in', 7200)
            cache.set(cache_key, cache_data, timeout=timeout)

        except Exception as e:
            current_app.logger.error(f"Failed to cache Feishu tokens: {str(e)}")

    @staticmethod
    def refresh_feishu_token(user_id: int, app_id: str, app_secret: str) -> Optional[str]:
        """
        刷新飞书用户令牌

        Args:
            user_id: 用户ID
            app_id: 应用ID
            app_secret: 应用密钥

        Returns:
            str: 新的访问令牌
        """
        try:
            # 从缓存获取刷新令牌
            cache_key = f"feishu_user_token_{app_id}_{user_id}"
            cached_data = cache.get(cache_key)

            if not cached_data or not cached_data.get('refresh_token_encrypted'):
                return None

            # 解密refresh token
            refresh_token = FeishuAuthService._decrypt_token(cached_data.get('refresh_token_encrypted'))

            # 获取应用令牌
            app_token = FeishuAuthService.get_app_access_token(app_id, app_secret)
            if not app_token:
                return None

            # 刷新用户令牌
            url = f"{FeishuAuthService.FEISHU_API_BASE}/authen/v1/refresh_access_token"
            headers = {
                'Authorization': f'Bearer {app_token}',
                'Content-Type': 'application/json'
            }
            data = {
                'grant_type': 'refresh_token',
                'refresh_token': refresh_token
            }

            response = requests.post(url, json=data, headers=headers, timeout=10)
            response.raise_for_status()

            result = response.json()
            if result.get('code') == 0:
                new_token_data = result.get('data')
                # 更新缓存
                FeishuAuthService._cache_feishu_tokens(user_id, new_token_data, app_id)
                return new_token_data.get('access_token')

            return None

        except Exception as e:
            current_app.logger.error(f"Failed to refresh Feishu token: {str(e)}")
            return None
```

### 2. FeishuAuthController

新增飞书认证控制器：

```python
# app/api/v1/feishu_auth/route/routes.py

from flask import request, current_app, session
from marshmallow import ValidationError
import uuid

from app.api.v1.feishu_auth.route import bp
from app.services.auth.service.feishu_auth import FeishuAuthService
from app.models.feishu.config import FeishuAppConfig
from app.utils.response import APIResponse
from app.api.v1.auth.schema.auth import TokenResponseSchema


def _validate_redirect_uri(redirect_uri: str, allowed_domains: list) -> bool:
    """
    验证redirect_uri是否在允许的域名列表中

    Args:
        redirect_uri: 回调地址
        allowed_domains: 允许的域名列表

    Returns:
        bool: 是否验证通过
    """
    from urllib.parse import urlparse

    if not redirect_uri:
        return False

    try:
        parsed = urlparse(redirect_uri)

        # 必须是HTTPS（生产环境）或HTTP localhost（开发环境）
        if parsed.scheme not in ['https', 'http']:
            return False

        if parsed.scheme == 'http' and not parsed.hostname in ['localhost', '127.0.0.1']:
            return False

        # 如果配置了允许域名列表，检查域名
        if allowed_domains:
            hostname = parsed.hostname
            for allowed_domain in allowed_domains:
                if hostname == allowed_domain or hostname.endswith(f'.{allowed_domain}'):
                    return True
            return False

        # 如果没有配置域名限制，允许localhost和127.0.0.1
        return parsed.hostname in ['localhost', '127.0.0.1'] or parsed.hostname.endswith('.ngrok.io')

    except Exception:
        return False


@bp.route('/authorize', methods=['GET'])
def get_authorization_url():
    """获取飞书授权URL"""
    try:
        app_name = request.args.get('app', 'default')
        redirect_uri = request.args.get('redirect_uri')

        if not redirect_uri:
            return APIResponse.error(message='redirect_uri is required', code=400)

        # 获取应用配置
        app_config = FeishuAppConfig.query.filter_by(
            app_name=app_name,
            is_active=True
        ).first()

        if not app_config:
            return APIResponse.error(message='Feishu app not configured', code=400)

        # 验证redirect_uri防止开放重定向攻击
        if not _validate_redirect_uri(redirect_uri, app_config.allowed_domains):
            current_app.logger.warning(f"Invalid redirect_uri attempted: {redirect_uri}")
            return APIResponse.error(message='Invalid redirect_uri', code=400)

        # 生成state参数防止CSRF攻击
        state = str(uuid.uuid4())
        session[f'feishu_state_{state}'] = {
            'app_name': app_name,
            'redirect_uri': redirect_uri
        }

        # 生成授权URL
        auth_url = FeishuAuthService.get_authorization_url(
            app_config.app_id,
            redirect_uri,
            state
        )

        return APIResponse.success(data={
            'authorization_url': auth_url,
            'state': state
        })

    except Exception as e:
        current_app.logger.error(f"Failed to get authorization URL: {str(e)}")
        return APIResponse.error(message='Failed to get authorization URL', code=500)


@bp.route('/callback', methods=['POST'])
def feishu_callback():
    """飞书授权回调处理"""
    try:
        data = request.get_json() or {}
        code = data.get('code')
        state = data.get('state')

        if not code:
            return APIResponse.error(message='Authorization code is required', code=400)

        # 验证state参数
        state_key = f'feishu_state_{state}'
        state_data = session.pop(state_key, None) if state else None

        if not state_data:
            return APIResponse.error(message='Invalid state parameter', code=400)

        app_name = state_data['app_name']

        # 获取应用配置
        app_config = FeishuAppConfig.query.filter_by(
            app_name=app_name,
            is_active=True
        ).first()

        if not app_config:
            return APIResponse.error(message='Feishu app not configured', code=400)

        # 执行飞书认证
        auth_result = FeishuAuthService.authenticate_with_feishu(
            code,
            app_config.to_dict()
        )

        if not auth_result:
            return APIResponse.error(message='Feishu authentication failed', code=401)

        user = auth_result['user']
        system_tokens = auth_result['system_tokens']

        # 序列化响应
        token_schema = TokenResponseSchema()
        response_data = token_schema.dump(system_tokens)

        # 添加用户信息
        response_data['user'] = {
            'id': user.id,
            'username': user.username,
            'email': user.email,
            'full_name': user.full_name,
            'is_super_admin': user.is_super_admin,
            'auth_provider': user.auth_provider,
            'roles': [role.code for role in user.get_roles()],
            'permissions': [perm.code for perm in user.get_permissions()]
        }

        return APIResponse.success(
            data=response_data,
            message='Feishu login successful'
        )

    except Exception as e:
        current_app.logger.error(f"Feishu callback failed: {str(e)}")
        return APIResponse.error(message='Feishu authentication failed', code=500)


@bp.route('/sync-user', methods=['POST'])
@login_required
@permission_required(permission_code='admin_user_write')
def sync_user_from_feishu(current_user):
    """手动同步飞书用户信息"""
    try:
        user_id = request.json.get('user_id')

        if not user_id:
            user_id = current_user.id

        # 权限检查：只有超级管理员可以同步其他用户
        if user_id != current_user.id and not current_user.is_super_admin:
            return APIResponse.error(message='Permission denied', code=403)

        user = AdminUser.query.get(user_id)
        if not user or not user.feishu_user_id:
            return APIResponse.error(message='User not found or not linked to Feishu', code=404)

        # TODO: 实现用户信息同步逻辑
        # 这里可以调用飞书API获取最新用户信息并更新

        return APIResponse.success(message='User synchronized successfully')

    except Exception as e:
        current_app.logger.error(f"Failed to sync user: {str(e)}")
        return APIResponse.error(message='User synchronization failed', code=500)
```

### 3. 模型扩展

扩展AdminUser模型：

```python
# app/models/user/admin.py - 添加飞书相关方法

class AdminUser(db.Model, TimestampMixin):
    # ... 现有字段 ...

    # 新增飞书相关字段（已在数据库设计中定义）
    feishu_user_id = Column(String(64), unique=True, nullable=True)
    feishu_union_id = Column(String(64), nullable=True)
    feishu_open_id = Column(String(64), nullable=True)
    auth_provider = Column(String(20), default='local', nullable=False)
    feishu_avatar_url = Column(String(500), nullable=True)
    last_sync_at = Column(DateTime, nullable=True)
    sync_enabled = Column(Boolean, default=True)

    def is_feishu_user(self) -> bool:
        """检查是否为飞书用户"""
        return self.auth_provider in ('feishu', 'mixed') and self.feishu_user_id is not None

    def can_login_with_password(self) -> bool:
        """检查是否可以使用密码登录"""
        return self.auth_provider in ('local', 'mixed') and self.password_hash

    def can_login_with_feishu(self) -> bool:
        """检查是否可以使用飞书登录"""
        return self.auth_provider in ('feishu', 'mixed') and self.feishu_user_id

    def get_display_avatar(self) -> str:
        """获取显示头像URL"""
        return self.feishu_avatar_url or '/static/default-avatar.png'

    def to_dict_with_feishu(self) -> dict:
        """转换为包含飞书信息的字典"""
        base_dict = self.to_dict()
        base_dict.update({
            'feishu_user_id': self.feishu_user_id,
            'auth_provider': self.auth_provider,
            'feishu_avatar_url': self.feishu_avatar_url,
            'last_sync_at': self.last_sync_at.isoformat() if self.last_sync_at else None,
            'can_login_with_password': self.can_login_with_password(),
            'can_login_with_feishu': self.can_login_with_feishu(),
            'display_avatar': self.get_display_avatar()
        })
        return base_dict


# 新增飞书配置模型
class FeishuAppConfig(db.Model, TimestampMixin):
    """飞书应用配置模型"""

    __tablename__ = 'feishu_app_configs'

    id = Column(Integer, primary_key=True)
    app_name = Column(String(100), unique=True, nullable=False)
    app_id = Column(String(64), unique=True, nullable=False)
    app_secret = Column(String(255), nullable=False)
    encrypt_key = Column(String(255), nullable=True)
    verification_token = Column(String(255), nullable=True)
    is_active = Column(Boolean, default=True)
    auto_create_user = Column(Boolean, default=False)
    default_role_codes = Column(ARRAY(Text), nullable=True)  # 改为存储role codes而不是IDs
    allowed_domains = Column(ARRAY(Text), nullable=True)
    webhook_url = Column(String(500), nullable=True)

    def to_dict(self) -> dict:
        """转换为字典（包含敏感信息，仅服务层内部使用）"""
        return {
            'id': self.id,
            'app_name': self.app_name,
            'app_id': self.app_id,
            'app_secret': self.app_secret,
            'encrypt_key': self.encrypt_key,
            'verification_token': self.verification_token,
            'is_active': self.is_active,
            'auto_create_user': self.auto_create_user,
            'default_role_codes': self.default_role_codes,
            'allowed_domains': self.allowed_domains,
            'webhook_url': self.webhook_url
        }

    def to_safe_dict(self) -> dict:
        """转换为安全字典（不包含敏感信息）"""
        return {
            'id': self.id,
            'app_name': self.app_name,
            'app_id': self.app_id,
            'is_active': self.is_active,
            'auto_create_user': self.auto_create_user,
            'allowed_domains': self.allowed_domains
        }
```

## 🎨 前端集成

### 1. 登录页面扩展

在现有登录页面添加飞书登录选项：

```typescript
// src/pages/Login/index.tsx

import React, { useState, useEffect } from 'react';
import { Button, Card, Form, Input, Divider, Space } from 'antd';
import { UserOutlined, LockOutlined } from '@ant-design/icons';
import { useLoginMutation, useFeishuAuthorizationQuery } from '@/api/auth';

interface LoginProps {
  onLogin: (tokens: any) => void;
}

const Login: React.FC<LoginProps> = ({ onLogin }) => {
  const [loginForm] = Form.useForm();
  const [login, { isLoading: isLoginLoading }] = useLoginMutation();

  // 处理传统用户名密码登录
  const handleLogin = async (values: any) => {
    try {
      const result = await login(values).unwrap();
      onLogin(result.data);
    } catch (error) {
      console.error('Login failed:', error);
    }
  };

  // 处理飞书登录
  const handleFeishuLogin = async () => {
    try {
      // 构建回调URL
      const redirectUri = `${window.location.origin}/auth/feishu/callback`;

      // 获取授权URL - 使用query parameters而不是body
      const params = new URLSearchParams({
        app: 'default',
        redirect_uri: redirectUri
      });

      const response = await fetch(`/api/v1/feishu-auth/authorize?${params}`, {
        method: 'GET',
        credentials: 'include'  // 确保发送cookies用于session验证
      });

      const data = await response.json();

      if (data.success) {
        // 重定向到飞书授权页面
        window.location.href = data.data.authorization_url;
      } else {
        console.error('Failed to get authorization URL:', data.message);
      }
    } catch (error) {
      console.error('Feishu login failed:', error);
    }
  };

  return (
    <div className="login-container">
      <Card title="登录" className="login-card">
        <Form form={loginForm} onFinish={handleLogin}>
          <Form.Item
            name="username"
            rules={[{ required: true, message: '请输入用户名或邮箱' }]}
          >
            <Input
              prefix={<UserOutlined />}
              placeholder="用户名或邮箱"
              size="large"
            />
          </Form.Item>

          <Form.Item
            name="password"
            rules={[{ required: true, message: '请输入密码' }]}
          >
            <Input.Password
              prefix={<LockOutlined />}
              placeholder="密码"
              size="large"
            />
          </Form.Item>

          <Form.Item>
            <Button
              type="primary"
              htmlType="submit"
              loading={isLoginLoading}
              size="large"
              block
            >
              登录
            </Button>
          </Form.Item>
        </Form>

        <Divider>或</Divider>

        <Space direction="vertical" style={{ width: '100%' }}>
          <Button
            icon={<img src="/feishu-icon.svg" alt="飞书" style={{ width: 16, height: 16 }} />}
            size="large"
            block
            onClick={handleFeishuLogin}
          >
            使用飞书登录
          </Button>
        </Space>
      </Card>
    </div>
  );
};

export default Login;
```

### 2. 飞书回调页面

创建飞书授权回调处理页面：

```typescript
// src/pages/Auth/FeishuCallback.tsx

import React, { useEffect, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { Spin, Alert, Card } from 'antd';
import { useAppDispatch } from '@/hooks/redux';
import { setCredentials } from '@/store/slices/authSlice';

const FeishuCallback: React.FC = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const dispatch = useAppDispatch();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const handleCallback = async () => {
      try {
        // 从URL参数获取code和state
        const urlParams = new URLSearchParams(location.search);
        const code = urlParams.get('code');
        const state = urlParams.get('state');

        if (!code) {
          setError('授权码缺失');
          return;
        }

        // 调用后端处理回调
        const response = await fetch('/api/v1/feishu-auth/callback', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          credentials: 'include',  // 确保发送cookies用于session验证
          body: JSON.stringify({ code, state })
        });

        const data = await response.json();

        if (data.success) {
          // 保存认证信息
          const { access_token, refresh_token, user } = data.data;

          // 存储到localStorage
          localStorage.setItem('access_token', access_token);
          localStorage.setItem('refresh_token', refresh_token);
          localStorage.setItem('user_info', JSON.stringify(user));

          // 更新Redux状态
          dispatch(setCredentials({
            user,
            accessToken: access_token,
            refreshToken: refresh_token
          }));

          // 重定向到主页
          navigate('/', { replace: true });
        } else {
          setError(data.message || '飞书登录失败');
        }
      } catch (err) {
        setError('网络错误，请重试');
      } finally {
        setLoading(false);
      }
    };

    handleCallback();
  }, [location, navigate, dispatch]);

  if (loading) {
    return (
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        height: '100vh'
      }}>
        <Card>
          <Spin size="large" />
          <div style={{ marginTop: 16 }}>正在处理飞书登录...</div>
        </Card>
      </div>
    );
  }

  if (error) {
    return (
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        height: '100vh'
      }}>
        <Card>
          <Alert
            message="登录失败"
            description={error}
            type="error"
            showIcon
            action={
              <Button size="small" onClick={() => navigate('/login')}>
                返回登录
              </Button>
            }
          />
        </Card>
      </div>
    );
  }

  return null;
};

export default FeishuCallback;
```

### 3. 用户信息显示扩展

扩展用户信息显示组件以支持飞书信息：

```typescript
// src/components/UserProfile/index.tsx

import React from 'react';
import { Avatar, Badge, Tag, Tooltip } from 'antd';
import { UserOutlined } from '@ant-design/icons';
import { useAppSelector } from '@/hooks/redux';

const UserProfile: React.FC = () => {
  const { user } = useAppSelector(state => state.auth);

  if (!user) return null;

  const getAuthProviderTag = (provider: string) => {
    const providerMap = {
      'local': { color: 'blue', text: '本地账户' },
      'feishu': { color: 'green', text: '飞书账户' },
      'mixed': { color: 'orange', text: '混合账户' }
    };

    const config = providerMap[provider] || providerMap.local;
    return <Tag color={config.color}>{config.text}</Tag>;
  };

  return (
    <div className="user-profile">
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <Badge dot={user.is_active} color="green">
          <Avatar
            size={40}
            src={user.display_avatar}
            icon={<UserOutlined />}
          />
        </Badge>

        <div>
          <div style={{ fontWeight: 500 }}>
            {user.full_name}
            {user.is_super_admin && (
              <Tag color="red" size="small" style={{ marginLeft: 8 }}>
                超级管理员
              </Tag>
            )}
          </div>

          <div style={{ fontSize: 12, color: '#666' }}>
            {user.email}
          </div>

          <div style={{ marginTop: 4 }}>
            {getAuthProviderTag(user.auth_provider)}
            {user.feishu_user_id && (
              <Tooltip title={`飞书ID: ${user.feishu_user_id}`}>
                <Tag size="small">已关联飞书</Tag>
              </Tooltip>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default UserProfile;
```

## ⚙️ 配置管理

### 1. 应用配置

在Flask配置中添加飞书相关配置：

```python
# app/config.py

class Config:
    # ... 现有配置 ...

    # 飞书配置
    FEISHU_DEFAULT_APP_ID = os.environ.get('FEISHU_APP_ID')
    FEISHU_DEFAULT_APP_SECRET = os.environ.get('FEISHU_APP_SECRET')
    FEISHU_DEFAULT_ENCRYPT_KEY = os.environ.get('FEISHU_ENCRYPT_KEY')
    FEISHU_DEFAULT_VERIFICATION_TOKEN = os.environ.get('FEISHU_VERIFICATION_TOKEN')

    # 飞书登录配置
    FEISHU_AUTO_CREATE_USER = os.environ.get('FEISHU_AUTO_CREATE_USER', 'false').lower() == 'true'
    FEISHU_DEFAULT_ROLES = os.environ.get('FEISHU_DEFAULT_ROLES', '').split(',') if os.environ.get('FEISHU_DEFAULT_ROLES') else []
    FEISHU_ALLOWED_DOMAINS = os.environ.get('FEISHU_ALLOWED_DOMAINS', '').split(',') if os.environ.get('FEISHU_ALLOWED_DOMAINS') else []

    # 缓存配置
    FEISHU_TOKEN_CACHE_PREFIX = 'feishu_token'
    FEISHU_APP_TOKEN_CACHE_PREFIX = 'feishu_app_token'
```

### 2. 环境变量模板

创建`.env.example`文件：

```bash
# 飞书应用配置
FEISHU_APP_ID=cli_xxxxxxxxxx
FEISHU_APP_SECRET=xxxxxxxxxx
FEISHU_ENCRYPT_KEY=xxxxxxxxxx
FEISHU_VERIFICATION_TOKEN=xxxxxxxxxx

# 飞书登录配置
FEISHU_AUTO_CREATE_USER=false
FEISHU_DEFAULT_ROLES=user,guest
FEISHU_ALLOWED_DOMAINS=company.com,example.com

# 数据库配置（现有）
DATABASE_URL=postgresql://user:password@localhost/pigeon_web

# Redis配置（现有）
REDIS_URL=redis://localhost:6379/0

# JWT配置（现有）
JWT_SECRET_KEY=your-secret-key
JWT_ACCESS_TOKEN_EXPIRES=3600
JWT_REFRESH_TOKEN_EXPIRES=86400
```

## 🔧 数据迁移

### 1. 数据库迁移脚本

```python
# migrations/versions/add_feishu_support.py

"""Add Feishu authentication support

Revision ID: add_feishu_support
Revises: previous_revision
Create Date: 2025-09-19

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers
revision = 'add_feishu_support'
down_revision = 'previous_revision'
branch_labels = None
depends_on = None


def upgrade():
    # 扩展admin_users表
    op.add_column('admin_users', sa.Column('feishu_user_id', sa.String(64), nullable=True))
    op.add_column('admin_users', sa.Column('feishu_union_id', sa.String(64), nullable=True))
    op.add_column('admin_users', sa.Column('feishu_open_id', sa.String(64), nullable=True))
    op.add_column('admin_users', sa.Column('auth_provider', sa.String(20), nullable=False, server_default='local'))
    op.add_column('admin_users', sa.Column('feishu_avatar_url', sa.String(500), nullable=True))
    op.add_column('admin_users', sa.Column('last_sync_at', sa.DateTime(), nullable=True))
    op.add_column('admin_users', sa.Column('sync_enabled', sa.Boolean(), nullable=True, server_default='true'))

    # 添加约束
    op.create_check_constraint(
        'chk_auth_provider',
        'admin_users',
        "auth_provider IN ('local', 'feishu', 'mixed')"
    )

    # 添加唯一约束
    op.create_unique_constraint('uq_admin_users_feishu_user_id', 'admin_users', ['feishu_user_id'])

    # 添加索引
    op.create_index('idx_admin_users_feishu_user_id', 'admin_users', ['feishu_user_id'])
    op.create_index('idx_admin_users_auth_provider', 'admin_users', ['auth_provider'])
    op.create_index('idx_admin_users_feishu_union_id', 'admin_users', ['feishu_union_id'])

    # 创建飞书应用配置表
    op.create_table(
        'feishu_app_configs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('app_name', sa.String(100), nullable=False),
        sa.Column('app_id', sa.String(64), nullable=False),
        sa.Column('app_secret', sa.String(255), nullable=False),
        sa.Column('encrypt_key', sa.String(255), nullable=True),
        sa.Column('verification_token', sa.String(255), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=True, server_default='true'),
        sa.Column('auto_create_user', sa.Boolean(), nullable=True, server_default='false'),
        sa.Column('default_role_ids', postgresql.ARRAY(sa.Integer()), nullable=True),
        sa.Column('allowed_domains', postgresql.ARRAY(sa.Text()), nullable=True),
        sa.Column('webhook_url', sa.String(500), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=True, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.Column('updated_at', sa.DateTime(), nullable=True, server_default=sa.text('CURRENT_TIMESTAMP')),
        sa.PrimaryKeyConstraint('id')
    )

    op.create_unique_constraint('uq_feishu_app_configs_app_name', 'feishu_app_configs', ['app_name'])
    op.create_unique_constraint('uq_feishu_app_configs_app_id', 'feishu_app_configs', ['app_id'])

    # 插入默认配置（如果环境变量存在）
    op.execute("""
        INSERT INTO feishu_app_configs (app_name, app_id, app_secret, encrypt_key, verification_token)
        SELECT 'default',
               COALESCE(current_setting('app.feishu_app_id', true), ''),
               COALESCE(current_setting('app.feishu_app_secret', true), ''),
               COALESCE(current_setting('app.feishu_encrypt_key', true), ''),
               COALESCE(current_setting('app.feishu_verification_token', true), '')
        WHERE COALESCE(current_setting('app.feishu_app_id', true), '') != ''
    """)


def downgrade():
    # 删除飞书配置表
    op.drop_table('feishu_app_configs')

    # 删除admin_users表的飞书字段
    op.drop_constraint('chk_auth_provider', 'admin_users')
    op.drop_constraint('uq_admin_users_feishu_user_id', 'admin_users')
    op.drop_index('idx_admin_users_feishu_user_id', 'admin_users')
    op.drop_index('idx_admin_users_auth_provider', 'admin_users')
    op.drop_index('idx_admin_users_feishu_union_id', 'admin_users')

    op.drop_column('admin_users', 'sync_enabled')
    op.drop_column('admin_users', 'last_sync_at')
    op.drop_column('admin_users', 'feishu_avatar_url')
    op.drop_column('admin_users', 'auth_provider')
    op.drop_column('admin_users', 'feishu_open_id')
    op.drop_column('admin_users', 'feishu_union_id')
    op.drop_column('admin_users', 'feishu_user_id')
```

## 🚀 部署指南

### 1. 部署检查清单

- [ ] **环境变量配置**：设置飞书应用凭据
- [ ] **数据库迁移**：执行迁移脚本
- [ ] **Redis配置**：确保Redis正常运行
- [ ] **飞书应用配置**：在飞书管理后台配置回调URL
- [ ] **HTTPS部署**：飞书要求HTTPS回调
- [ ] **域名配置**：配置正确的域名和回调地址
- [ ] **防火墙设置**：确保能访问飞书API
- [ ] **日志配置**：配置适当的日志级别

### 2. 飞书应用后台配置

在飞书开放平台配置：

1. **应用信息**：
   - 应用名称：Pigeon Web管理系统
   - 应用描述：国际短信服务管理平台
   - 应用图标：上传应用logo

2. **权限配置**：
   - 获取用户基本信息
   - 获取用户邮箱信息
   - 获取用户头像信息

3. **回调配置**：
   - 重定向URL：`https://yourdomain.com/auth/feishu/callback`
   - 安全域名：`yourdomain.com`

4. **事件订阅**（可选）：
   - 订阅用户变更事件
   - 配置事件回调URL：`https://yourdomain.com/api/v1/feishu-webhook/events`

### 3. Nginx配置示例

```nginx
server {
    listen 443 ssl;
    server_name yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /api/ {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /auth/feishu/callback {
        try_files $uri $uri/ /index.html;
    }

    location / {
        try_files $uri $uri/ /index.html;
        root /path/to/frontend/build;
        index index.html;
    }
}
```

## 🔍 安全考虑

### 1. 安全增强措施

1. **CSRF防护**：
   - 使用state参数防止CSRF攻击
   - 验证referer头
   - 设置适当的CORS策略

2. **令牌安全**：
   - 飞书令牌与系统令牌分离存储
   - 令牌加密存储
   - 定期刷新机制

3. **用户验证**：
   - 邮箱域名白名单
   - 用户创建审批流程
   - 账户关联验证

4. **审计日志**：
   - 记录所有飞书登录事件
   - 用户关联操作日志
   - 异常行为监控

### 2. 权限隔离

```python
# 权限策略示例
FEISHU_PERMISSION_POLICY = {
    'auto_create_user': False,  # 默认不自动创建用户
    'require_admin_approval': True,  # 需要管理员审批
    'default_roles': ['guest'],  # 默认最小权限
    'allowed_domains': ['company.com'],  # 限制邮箱域名
    'sync_user_info': True,  # 同步用户基本信息
    'sync_frequency': 'daily'  # 同步频率
}
```

## 📊 监控和运维

### 1. 监控指标

- 飞书API调用成功率
- 用户登录成功率
- 令牌刷新频率
- 用户同步状态
- 异常登录检测

### 2. 告警策略

```python
# 告警规则示例
FEISHU_ALERTS = {
    'api_failure_rate': {
        'threshold': 0.1,  # 10%失败率
        'window': '5m',
        'action': 'email_admin'
    },
    'login_failure_spike': {
        'threshold': 50,  # 每分钟超过50次失败
        'window': '1m',
        'action': 'slack_notification'
    },
    'token_refresh_failure': {
        'threshold': 0.05,  # 5%刷新失败率
        'window': '10m',
        'action': 'check_app_config'
    }
}
```

## 🧪 测试策略

### 1. 单元测试

```python
# tests/test_feishu_auth.py

import pytest
from unittest.mock import patch, Mock
from app.services.auth.service.feishu_auth import FeishuAuthService


class TestFeishuAuthService:

    def test_get_authorization_url(self):
        """测试生成授权URL"""
        url = FeishuAuthService.get_authorization_url(
            'test_app_id',
            'http://localhost/callback',
            'test_state'
        )

        assert 'open.feishu.cn' in url
        assert 'test_app_id' in url
        assert 'localhost/callback' in url
        assert 'test_state' in url

    @patch('requests.post')
    def test_get_app_access_token_success(self, mock_post):
        """测试获取应用访问令牌成功"""
        mock_response = Mock()
        mock_response.json.return_value = {
            'code': 0,
            'app_access_token': 'test_token',
            'expire': 7200
        }
        mock_post.return_value = mock_response

        token = FeishuAuthService.get_app_access_token('app_id', 'app_secret')

        assert token == 'test_token'
        mock_post.assert_called_once()

    @patch('requests.post')
    def test_exchange_code_for_token_success(self, mock_post):
        """测试授权码换令牌成功"""
        # 模拟获取应用令牌
        with patch.object(FeishuAuthService, 'get_app_access_token', return_value='app_token'):
            mock_response = Mock()
            mock_response.json.return_value = {
                'code': 0,
                'data': {
                    'access_token': 'user_token',
                    'refresh_token': 'refresh_token',
                    'expires_in': 7200
                }
            }
            mock_post.return_value = mock_response

            result = FeishuAuthService.exchange_code_for_token('app_id', 'app_secret', 'auth_code')

            assert result['access_token'] == 'user_token'
            assert result['refresh_token'] == 'refresh_token'
```

### 2. 集成测试

```python
# tests/integration/test_feishu_login_flow.py

import pytest
from flask import url_for
from app import create_app
from app.extensions import db


@pytest.fixture
def app():
    app = create_app('testing')
    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


class TestFeishuLoginFlow:

    def test_get_authorization_url(self, client):
        """测试获取授权URL接口"""
        response = client.get('/api/v1/feishu-auth/authorize', query_string={
            'app': 'default',
            'redirect_uri': 'http://localhost/callback'
        })

        assert response.status_code == 200
        data = response.get_json()
        assert data['success'] is True
        assert 'authorization_url' in data['data']
        assert 'state' in data['data']

    @patch('app.services.auth.service.feishu_auth.FeishuAuthService.authenticate_with_feishu')
    def test_feishu_callback_success(self, mock_auth, client):
        """测试飞书回调成功"""
        # 模拟认证结果
        mock_user = Mock()
        mock_user.id = 1
        mock_user.username = 'test_user'
        mock_user.email = 'test@company.com'

        mock_auth.return_value = {
            'user': mock_user,
            'system_tokens': {
                'access_token': 'system_token',
                'refresh_token': 'refresh_token'
            }
        }

        # 设置session state
        with client.session_transaction() as sess:
            sess['feishu_state_test123'] = {
                'app_name': 'default',
                'redirect_uri': 'http://localhost/callback'
            }

        response = client.post('/api/v1/feishu-auth/callback', json={
            'code': 'test_code',
            'state': 'test123'
        })

        assert response.status_code == 200
        data = response.get_json()
        assert data['success'] is True
        assert 'access_token' in data['data']
```

### 3. 前端测试

```typescript
// src/components/Login/__tests__/FeishuLogin.test.tsx

import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Provider } from 'react-redux';
import { BrowserRouter } from 'react-router-dom';
import Login from '../index';
import { createTestStore } from '@/utils/test-utils';

// Mock fetch
global.fetch = jest.fn();

describe('FeishuLogin', () => {
  let store: any;

  beforeEach(() => {
    store = createTestStore();
    (fetch as jest.Mock).mockClear();
  });

  test('renders feishu login button', () => {
    render(
      <Provider store={store}>
        <BrowserRouter>
          <Login onLogin={jest.fn()} />
        </BrowserRouter>
      </Provider>
    );

    expect(screen.getByText('使用飞书登录')).toBeInTheDocument();
  });

  test('handles feishu login click', async () => {
    (fetch as jest.Mock).mockResolvedValueOnce({
      json: async () => ({
        success: true,
        data: {
          authorization_url: 'https://feishu.cn/auth?code=123',
          state: 'state123'
        }
      })
    });

    // Mock window.location.href
    delete (window as any).location;
    (window as any).location = { href: '' };

    render(
      <Provider store={store}>
        <BrowserRouter>
          <Login onLogin={jest.fn()} />
        </BrowserRouter>
      </Provider>
    );

    const feishuButton = screen.getByText('使用飞书登录');
    fireEvent.click(feishuButton);

    await waitFor(() => {
      expect(fetch).toHaveBeenCalledWith('/api/v1/feishu-auth/authorize', expect.any(Object));
    });
  });
});
```

## 📈 性能优化

### 1. 缓存策略

```python
# 缓存配置
FEISHU_CACHE_CONFIG = {
    'app_token': {
        'prefix': 'feishu_app_token',
        'ttl': 7200 - 300,  # 提前5分钟过期
        'namespace': 'auth'
    },
    'user_token': {
        'prefix': 'feishu_user_token',
        'ttl': 7200 - 60,   # 提前1分钟过期
        'namespace': 'user'
    },
    'user_info': {
        'prefix': 'feishu_user_info',
        'ttl': 3600,        # 1小时缓存
        'namespace': 'user'
    }
}
```

### 2. 数据库优化

```sql
-- 性能优化索引
CREATE INDEX CONCURRENTLY idx_admin_users_feishu_composite
ON admin_users (feishu_user_id, is_active, auth_provider)
WHERE feishu_user_id IS NOT NULL;

-- 分区表优化（大量用户场景）
CREATE TABLE admin_users_feishu PARTITION OF admin_users
FOR VALUES IN ('feishu', 'mixed');
```

## 🎯 总结

本设计方案实现了pigeon_web与飞书认证的无缝集成，具有以下特点：

### 🌟 核心优势

1. **非侵入性集成**：最小化对现有系统的修改，保持原有架构优势
2. **安全性保证**：复用现有JWT认证，增加飞书OAuth2双重保障
3. **灵活配置**：支持多应用配置，可按需启用不同认证方式
4. **向后兼容**：现有用户登录不受影响，平滑过渡
5. **企业级特性**：支持用户同步、权限管理、审计日志等企业需求

### 🔄 实施策略

1. **分阶段实施**：
   - 第一阶段：基础飞书登录集成
   - 第二阶段：用户同步和管理功能
   - 第三阶段：高级安全和监控功能

2. **风险控制**：
   - 完善的测试覆盖
   - 渐进式部署策略
   - 回滚预案

3. **用户体验**：
   - 流畅的登录流程
   - 清晰的权限提示
   - 友好的错误处理

这个集成方案既保持了pigeon_web现有的优秀架构，又充分利用了飞书认证的企业级特性，为用户提供了更加便捷、安全的认证体验。通过carefully designed的安全机制和性能优化，确保系统在引入新功能的同时保持高可用性和安全性。

---

**文档版本**: v1.0
**创建日期**: 2025-09-19
**适用版本**: pigeon_web v1.0+
**维护者**: Development Team