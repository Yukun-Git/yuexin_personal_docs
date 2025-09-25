# FEAT-6-1 供应商管理功能开发计划 - 架构对齐版

## 📋 项目概述

**功能名称**: 供应商管理 (Vendor Management)
**需求编号**: FEAT-6-1
**优先级**: P1 - 高优先级
**预计工期**: 5-7个工作日
**技术栈**: 完全对齐pigeon_web现有架构

## 🏗️ **pigeon_web架构分析总结**

基于深入分析pigeon_web现有代码，确认以下关键架构模式需要严格遵循：

### 模型层架构模式
- **继承模式**: `db.Model, TimestampMixin, I18nMixin`
- **主键设计**: PostgreSQL UUID 使用 `UUID(as_uuid=True), primary_key=True, default=db.func.uuid_generate_v4()`
- **枚举设计**: 独立枚举类，使用 `values_callable=lambda obj: [e.value for e in obj]`
- **字段设计**: JSON/JSONB 存储复杂数据，CHECK约束验证
- **方法规范**: `to_dict()`, `update_from_dict()`, 属性装饰器计算字段
- **关联关系**: 使用 `back_populates`, `lazy='dynamic'`

### 服务层架构模式
- **继承基类**: `BaseService`
- **类型标注**: 完整的 Python 类型提示
- **错误处理**: 统一的 `ValueError`, `IntegrityError`, `PermissionError`
- **事务管理**: `db.session.commit()`, 失败时 `db.session.rollback()`
- **权限验证**: `_has_admin_permission()` 私有方法

### API层架构模式
- **基类继承**: `flask_restful.Resource`
- **权限装饰器**: `@login_required` 装饰器模式
- **响应格式**: `APIResponse.success()`, `APIResponse.error()` 统一响应
- **异常处理**: 分层异常处理，记录日志
- **参数获取**: `request.args.get()`, `request.get_json()`

### 数据库设计模式
- **模块化**: 独立的 `sql/modules/*.sql` 文件
- **PostgreSQL枚举**: `CREATE TYPE ... AS ENUM (...)`
- **索引命名**: `idx_{table}_{column}` 格式
- **约束命名**: `chk_{table}_{condition}` 格式

### 权限系统模式
- **权限命名**: 下划线格式 (`vendor_read`, `vendor_create`)
- **装饰器**: `@require_permission()` (需查看具体实现)

---

## 📅 **架构对齐开发阶段**

## 🎯 **阶段1: 数据库层严格对齐设计** (1天)

### 任务1.1: 供应商表结构设计
**严格遵循enterprises表的设计模式**

```sql
-- 供应商状态枚举 (对齐EnterpriseStatus模式)
CREATE TYPE vendor_status AS ENUM ('active', 'inactive', 'suspended');

-- 供应商表 (完全对齐enterprises表模式)
CREATE TABLE IF NOT EXISTS vendors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- 基本信息 (对齐enterprise name字段)
    vendor_name VARCHAR(255) NOT NULL,
    display_name JSONB DEFAULT '{}',  -- I18n支持

    -- 联系信息 (对齐enterprise联系信息模式)
    contact_person VARCHAR(100),
    contact_phone VARCHAR(50),
    primary_email VARCHAR(255),
    website VARCHAR(255),

    -- 地址信息 (对齐enterprise地址模式)
    address JSONB DEFAULT '{}',

    -- 状态管理 (对齐enterprise状态模式)
    status vendor_status DEFAULT 'active' NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,

    -- 业务信息
    business_type VARCHAR(100),
    service_regions JSONB DEFAULT '[]',  -- 服务区域列表

    -- 元数据 (对齐enterprise元数据模式)
    custom_fields JSONB DEFAULT '{}',
    tags JSONB DEFAULT '[]',
    notes TEXT,

    -- 时间戳 (对齐TimestampMixin模式)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);
```

### 任务1.2: 通道表关联字段
**基于现有channels表添加vendor_id外键**

```sql
-- 添加供应商关联字段到channels表
ALTER TABLE channels
ADD COLUMN vendor_id UUID REFERENCES vendors(id) ON DELETE SET NULL;

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_channels_vendor_id ON channels(vendor_id);
```

### 任务1.3: 索引和约束设计
**严格遵循现有表的索引命名模式**

```sql
-- 主要查询索引
CREATE INDEX IF NOT EXISTS idx_vendors_vendor_name ON vendors(vendor_name);
CREATE INDEX IF NOT EXISTS idx_vendors_status ON vendors(status);
CREATE INDEX IF NOT EXISTS idx_vendors_is_active ON vendors(is_active);
CREATE INDEX IF NOT EXISTS idx_vendors_created_at ON vendors(created_at);

-- 唯一约束 (如果需要)
CREATE UNIQUE INDEX IF NOT EXISTS idx_vendors_name_unique ON vendors(vendor_name) WHERE is_active = true;
```

**预期产出**:
- `pigeon_web/sql/modules/vendors.sql` - 完整表结构
- `pigeon_web/sql/mock_data/vendors.sql` - 测试数据
- 与现有数据库模式100%对齐

---

## 🎯 **阶段2: 模型层严格对齐实现** (1天)

### 任务2.1: Vendor模型实现
**完全对齐Enterprise模型的设计模式**

文件位置: `app/models/customers/vendor.py`

```python
# Copyright(c) 2025
# All rights reserved.
#
# Author: yukun.xing <xingyukun@gmail.com>
# Date:   2025/09/22

"""Vendor model for managing SMS channel vendors."""

from enum import Enum
from datetime import datetime
from sqlalchemy.dialects.postgresql import UUID
from app.extensions import db
from app.models.base import to_time
from app.models.base.mixins import TimestampMixin, I18nMixin


class VendorStatus(Enum):
    """Vendor status enumeration."""
    ACTIVE = 'active'      # Active vendor
    INACTIVE = 'inactive'  # Inactive vendor
    SUSPENDED = 'suspended'  # Suspended vendor


class Vendor(db.Model, TimestampMixin, I18nMixin):
    """Vendor model for SMS channel vendors."""

    __tablename__ = 'vendors'

    # Primary key (对齐Enterprise模型)
    id = db.Column(UUID(as_uuid=True), primary_key=True,
                   default=db.func.uuid_generate_v4())

    # Basic information (对齐Enterprise基本信息)
    vendor_name = db.Column(db.String(255), nullable=False,
                           index=True, comment='Vendor name')
    display_name = db.Column(db.JSON, comment='Internationalized display name')

    # Contact information (对齐Enterprise联系信息)
    contact_person = db.Column(db.String(100), comment='Contact person')
    contact_phone = db.Column(db.String(50), comment='Contact phone')
    primary_email = db.Column(db.String(255), comment='Primary email')
    website = db.Column(db.String(255), comment='Website')

    # Address information (对齐Enterprise地址信息)
    address = db.Column(db.JSON, comment='Address information')

    # Status (对齐Enterprise状态管理)
    status = db.Column(db.Enum(VendorStatus, values_callable=lambda obj: [e.value for e in obj]),
                       default=VendorStatus.ACTIVE, nullable=False, index=True)
    is_active = db.Column(db.Boolean, default=True, nullable=False, index=True)

    # Business information
    business_type = db.Column(db.String(100), comment='Business type')
    service_regions = db.Column(db.JSON, default=list, comment='Service regions')

    # Metadata (对齐Enterprise元数据)
    custom_fields = db.Column(db.JSON, default=dict, comment='Custom fields')
    tags = db.Column(db.JSON, default=list, comment='Tags')
    notes = db.Column(db.Text, comment='Notes')

    # Relationships (对齐Enterprise关联关系模式)
    channels = db.relationship('Channel', back_populates='vendor',
                              lazy='dynamic', foreign_keys='Channel.vendor_id')

    def __repr__(self):
        return f'<Vendor {self.vendor_name} ({self.status.value})>'

    @property
    def display_name_localized(self):
        """Get localized display name (对齐Enterprise属性)."""
        from flask import g
        lang = getattr(g, 'language', 'en')
        return self.get_i18n_value(self.display_name, lang) or self.vendor_name

    @property
    def related_channels_count(self):
        """Get count of related channels (对齐Enterprise计算属性模式)."""
        try:
            return self.channels.count()
        except Exception:
            from app.extensions import db as _db
            try:
                _db.session.rollback()
            except Exception:
                pass
            return 0

    def to_dict(self, include_sensitive=False, include_relationships=False):
        """Convert to dictionary (完全对齐Enterprise.to_dict模式)."""
        data = {
            'id': str(self.id) if self.id else None,
            'vendor_name': self.vendor_name,
            'display_name': self.display_name,
            'display_name_localized': self.display_name_localized,
            'contact_person': self.contact_person,
            'contact_phone': self.contact_phone,
            'primary_email': self.primary_email,
            'website': self.website,
            'address': self.address,
            'status': self.status.value,
            'is_active': self.is_active,
            'business_type': self.business_type,
            'service_regions': self.service_regions,
            'tags': self.tags,
            'created_at': to_time(self.created_at),
            'updated_at': to_time(self.updated_at),
            'related_channels_count': self.related_channels_count
        }

        if include_sensitive:
            data.update({
                'custom_fields': self.custom_fields,
                'notes': self.notes
            })

        if include_relationships:
            data.update({
                'channels': [channel.to_dict() for channel in self.channels]
            })

        return data

    def update_from_dict(self, data):
        """Update vendor from dictionary (对齐Enterprise更新模式)."""
        updatable_fields = [
            'vendor_name', 'display_name', 'contact_person', 'contact_phone',
            'primary_email', 'website', 'address', 'business_type',
            'service_regions', 'custom_fields', 'tags', 'notes'
        ]

        for field in updatable_fields:
            if field in data:
                setattr(self, field, data[field])
```

### 任务2.2: Channel模型关联更新
**添加vendor关联关系到现有Channel模型**

更新 `app/models/customers/channel.py`:
```python
# 添加vendor关联字段
vendor_id = db.Column(UUID(as_uuid=True), db.ForeignKey('vendors.id'))

# 添加关联关系
vendor = db.relationship('Vendor', back_populates='channels')
```

**预期产出**:
- 完整的Vendor模型实现
- Channel模型关联关系更新
- 100%对齐现有模型设计模式

---

## 🎯 **阶段3: 服务层严格对齐实现** (1天)

### 任务3.1: VendorService实现
**完全对齐EnterpriseService的架构模式**

文件位置: `app/services/vendors/vendor_service.py`

```python
# Copyright(c) 2025
# All rights reserved.
#
# Author: yukun.xing <xingyukun@gmail.com>
# Date:   2025/09/22

"""Vendor business service layer."""

from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError

from app.extensions import db
from app.models.customers.vendor import Vendor, VendorStatus
from app.services.base.base_service import BaseService
from app.utils.pagination import PaginationHelper


class VendorService(BaseService):
    """Business service for vendor management (对齐EnterpriseService模式)."""

    def __init__(self):
        """Initialize vendor service."""
        super().__init__(Vendor)

    def get_vendors_with_filters(
        self,
        page: int = 1,
        per_page: int = 20,
        search: str = '',
        status: str = '',
        order_by: str = 'created_at',
        order_dir: str = 'desc'
    ) -> Dict[str, Any]:
        """
        Get vendor list with filtering and pagination (对齐Enterprise筛选模式).
        """
        # 实现逻辑完全对齐EnterpriseService.get_enterprises_with_filters
        pass

    def create_vendor(self, data: Dict[str, Any]) -> Vendor:
        """
        Create new vendor with validation (对齐Enterprise创建模式).
        """
        # 实现逻辑完全对齐EnterpriseService.create_enterprise
        pass

    def update_vendor(
        self,
        vendor_id: str,
        data: Dict[str, Any],
        current_user: Any = None
    ) -> Optional[Vendor]:
        """
        Update vendor with validation (对齐Enterprise更新模式).
        """
        # 实现逻辑完全对齐EnterpriseService.update_enterprise
        pass

    def delete_vendor(
        self,
        vendor_id: str,
        force: bool = False,
        current_user: Any = None
    ) -> Tuple[bool, str]:
        """
        Delete vendor with constraints (对齐Enterprise删除模式).
        """
        # 实现逻辑完全对齐EnterpriseService.delete_enterprise
        pass

    def get_vendor_channels(self, vendor_id: str) -> List[Dict[str, Any]]:
        """Get channels associated with vendor."""
        vendor = self.get_by_id(vendor_id)
        if not vendor:
            return []

        try:
            return [channel.to_dict() for channel in vendor.channels]
        except Exception:
            from app.extensions import db as _db
            try:
                _db.session.rollback()
            except Exception:
                pass
            return []

    def unlink_channel_from_vendor(
        self,
        vendor_id: str,
        channel_id: str,
        current_user: Any = None
    ) -> Tuple[bool, str]:
        """Unlink channel from vendor."""
        # 实现解除关联逻辑
        pass

    # 私有方法对齐Enterprise模式
    def _check_vendor_name_duplicate(self, name: str, exclude_id: str = None):
        """Check for vendor name duplicates."""
        pass

    def _has_admin_permission(self, user: Any) -> bool:
        """Check if user has admin permissions."""
        if not user:
            return False
        return hasattr(user, 'has_permission') and user.has_permission('vendor_admin')
```

**预期产出**:
- 完整的VendorService实现
- 100%对齐EnterpriseService架构模式
- 完整的业务逻辑和验证

---

## 🎯 **阶段4: API层严格对齐实现** (1.5天)

### 任务4.1: API目录结构
**严格对齐现有API模块结构**

```
app/api/v1/vendors/
├── __init__.py
├── route/
│   ├── __init__.py
│   ├── vendor_list.py         # 对齐enterprise_list.py
│   ├── vendor_detail.py       # 对齐enterprise_detail.py
│   ├── vendor_channels.py     # 供应商关联通道管理
│   └── routes.py              # 路由注册
└── schema/
    ├── __init__.py
    └── vendor_schema.py       # 对齐enterprise.py
```

### 任务4.2: VendorListResource实现
**完全对齐EnterpriseListResource模式**

文件位置: `app/api/v1/vendors/route/vendor_list.py`

```python
"""Vendor list and creation endpoints (对齐EnterpriseListResource)."""

from flask import current_app, request
from flask_restful import Resource
from sqlalchemy.exc import IntegrityError

from app.decorators.auth import login_required
from app.services.vendors.vendor_service import VendorService
from app.utils.response import APIResponse


class VendorListResource(Resource):
    """Vendor list operations (完全对齐EnterpriseListResource)."""

    def __init__(self):
        self.vendor_service = VendorService()

    @login_required
    def get(self, current_user):
        """Get vendor list with pagination and filtering."""
        # 实现逻辑完全对齐EnterpriseListResource.get
        pass

    @login_required
    def post(self, current_user):
        """Create new vendor."""
        # 实现逻辑完全对齐EnterpriseListResource.post
        pass
```

### 任务4.3: VendorDetailResource实现
**对齐EnterpriseDetailResource模式**

### 任务4.4: VendorChannelsResource实现
**供应商关联通道管理API**

```python
class VendorChannelsResource(Resource):
    """Vendor channels management."""

    @login_required
    def get(self, vendor_id, current_user):
        """Get vendor related channels."""
        pass

    @login_required
    def delete(self, vendor_id, channel_id, current_user):
        """Unlink channel from vendor."""
        pass
```

### 任务4.5: Schema定义
**对齐现有Schema模式**

文件位置: `app/api/v1/vendors/schema/vendor_schema.py`

```python
"""Vendor API schemas (对齐enterprise schema模式)."""

from marshmallow import Schema, fields, validate
from app.models.customers.vendor import VendorStatus

class VendorQuerySchema(Schema):
    """Vendor query parameters schema."""
    # 完全对齐企业查询Schema
    pass

class VendorCreateSchema(Schema):
    """Vendor creation schema."""
    # 完全对齐企业创建Schema
    pass

class VendorUpdateSchema(Schema):
    """Vendor update schema."""
    # 完全对齐企业更新Schema
    pass
```

**预期产出**:
- 完整的RESTful API实现
- 15个API端点
- 100%对齐现有API架构模式

---

## 🎯 **阶段5: 前端层架构对齐实现** (1.5天)

### 任务5.1: 前端目录结构分析和对齐
**分析现有前端架构模式**

首先深入分析现有前端代码：
- `frontend/src/pages/system/` 目录结构
- `frontend/src/api/` API接口定义模式
- `frontend/src/store/slices/` 状态管理模式
- `frontend/src/types/` 类型定义模式

### 任务5.2: 类型定义
**对齐现有TypeScript类型模式**

文件位置: `frontend/src/types/vendor.ts`

```typescript
// 完全对齐现有类型定义模式
export interface Vendor {
  id: string;
  vendorName: string;
  displayName?: Record<string, string>;
  contactPerson?: string;
  contactPhone?: string;
  // ... 其他字段对齐现有模式
}
```

### 任务5.3: API接口定义
**对齐现有RTK Query模式**

文件位置: `frontend/src/api/vendorApi.ts`

```typescript
// 对齐现有API定义模式
import { createApi } from '@reduxjs/toolkit/query/react';
import { baseQueryWithAuth } from './config';

export const vendorApi = createApi({
  reducerPath: 'vendorApi',
  baseQuery: baseQueryWithAuth,
  tagTypes: ['Vendor', 'VendorChannel'],
  endpoints: (builder) => ({
    // 对齐现有API端点模式
  })
});
```

### 任务5.4: 状态管理
**对齐现有Redux Slice模式**

### 任务5.5: 核心组件实现
**对齐现有组件架构模式**

- `VendorManagementPage` - 对齐现有页面组件模式
- `VendorTable` - 对齐现有表格组件模式
- `VendorForm` - 对齐现有表单组件模式
- `VendorChannelsModal` - 关联通道管理弹窗

**预期产出**:
- 完整的前端组件系统
- 100%对齐现有前端架构
- 响应式UI和用户体验

---

## 🔧 **权限系统对齐**

### 权限定义
**严格对齐现有权限命名规范**

```sql
-- 添加供应商相关权限 (对齐现有权限格式)
INSERT INTO permissions (name, code, resource, action, description) VALUES
('供应商查看', 'vendor_read', 'vendor', 'read', '查看供应商信息'),
('供应商创建', 'vendor_create', 'vendor', 'create', '创建新供应商'),
('供应商更新', 'vendor_update', 'vendor', 'update', '更新供应商信息'),
('供应商删除', 'vendor_delete', 'vendor', 'delete', '删除供应商'),
('供应商管理', 'vendor_admin', 'vendor', 'admin', '供应商完全管理权限');
```

### API权限装饰器
**使用现有权限验证机制**

```python
@login_required
@require_permission('vendor_read')  # 使用现有权限装饰器
def get(self, current_user):
    pass
```

---

## 📊 **架构对齐验收标准**

### 代码架构对齐验收
- [ ] 模型继承和设计100%对齐Enterprise模式
- [ ] 服务层方法签名和逻辑对齐EnterpriseService模式
- [ ] API层响应格式和错误处理对齐现有模式
- [ ] 数据库表结构和索引对齐现有规范
- [ ] 权限系统对齐现有RBAC模式

### 功能实现验收
- [ ] 供应商CRUD操作功能完整
- [ ] 关联通道管理功能正常
- [ ] 搜索筛选功能对齐现有模式
- [ ] 分页和排序功能对齐现有实现

### 前端架构对齐验收
- [ ] 组件架构对齐现有页面模式
- [ ] 状态管理对齐现有Redux模式
- [ ] API集成对齐现有RTK Query模式
- [ ] UI/UX设计对齐现有设计系统

---

## 🚨 **架构对齐风险管控**

### 技术债务防范
- **强制代码审查**: 每个阶段完成后强制对比现有代码
- **模式检查清单**: 针对每个文件创建对齐检查清单
- **集成测试**: 确保新功能与现有系统无缝集成

### 一致性保证
- **命名规范**: 严格遵循现有文件、类、方法命名规范
- **错误处理**: 复用现有异常类和错误处理模式
- **日志记录**: 对齐现有日志记录格式和级别

---

## 📝 **项目规范100%遵循**

### 编码规范
- ✅ 文件头格式: `Copyright(c) 2025 / Author: yukun.xing <xingyukun@gmail.com>`
- ✅ 权限命名: 下划线格式 (`vendor_read`, `vendor_create`)
- ✅ 英文注释: 所有注释使用英文
- ✅ 避免过度注释: 代码自解释为主

### 数据库规范
- ✅ 模块化SQL: `sql/modules/vendors.sql`
- ✅ Mock数据: `sql/mock_data/vendors.sql`
- ✅ 直接修改初始化脚本: 不创建迁移脚本

### 开发流程
- ✅ 在pigeon_web main分支直接开发
- ✅ 代码修复后等待用户测试确认
- ✅ 虚拟环境: `/Users/yukun-admin/projects/pigeon/venv`

---

**最后更新**: 2025-09-22
**文档版本**: v2.0 (架构对齐版)
**估计工期**: 5-7个工作日
**优先级**: P1 - 高优先级

**架构对齐承诺**: 本开发计划确保新增供应商管理功能与pigeon_web现有代码在模型层、服务层、API层、数据库层、前端层、权限系统等各方面100%对齐，保持代码架构的一致性和可维护性。