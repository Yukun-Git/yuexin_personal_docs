# per_page 到 page_size 统一改造计划

## 背景

系统中存在前后端分页参数命名不一致的问题：
- **前端统一使用**: `page_size`
- **后端部分模块使用**: `per_page`（旧的命名方式）
- **后端部分模块使用**: `page_size`（新的命名方式）

这导致了参数不匹配的 400 错误。为了保持代码一致性和可维护性，需要将所有后端模块统一改为使用 `page_size`。

## 已完成的模块（使用 page_size）

以下模块已经使用 `page_size`，无需修改：
- ✅ **whitelist** - 白名单管理
- ✅ **blacklist** - 黑名单管理
- ✅ **platform_errors** - 平台错误管理
- ✅ **sms** - 短信管理
- ✅ **sensitive_words** - 敏感词管理（刚修复完成）

## 待修改的模块（使用 per_page）

需要将以下模块从 `per_page` 改为 `page_size`：

### 1. Channels 模块（渠道管理）
**Schema 文件**:
- `app/api/v1/channels/schema/channel.py` (1处)
  - `ChannelQuerySchema` 第 350 行
- `app/api/v1/channels/schema/channel_group.py` (3处)
  - 第 97 行
  - 第 135 行
  - 第 301 行（dump_only，响应字段）
- `app/api/v1/channels/schema/sender.py` (1处)
  - 第 232 行

**Route 文件**:
- `app/api/v1/channels/route/channel_list.py`
  - 第 29 行: `request.args.get('per_page', 20, type=int)`
  - 第 77 行: `per_page=per_page`
- `app/api/v1/channels/route/channel_groups.py`
  - 第 48、69、91 行（第一个查询接口）
  - 第 227、247、268 行（第二个查询接口）
  - 第 447、461 行（第三个查询接口）
- `app/api/v1/channels/route/channel_advanced_query.py`
  - 第 236 行（文档示例）
  - 第 250、264 行
- `app/api/v1/channels/route/sender_management.py`
  - 第 60 行: `per_page=query_params['per_page']`

**Service 文件**:
- 需要检查 `app/services/channels/` 下的服务类方法签名

---

### 2. Roles 模块（角色管理）
**Schema 文件**:
- `app/api/v1/roles/schema/role_schema.py` (2处)
  - 第 141 行: 查询 schema
  - 第 160 行: 响应 schema（dump_only）

**Route 文件**:
- `app/api/v1/roles/route/role_list.py`
  - 第 75 行: `per_page=query_params['per_page']`
  - 第 96 行: `'per_page': paginated_roles.per_page`

**Service 文件**:
- 需要检查角色服务的方法签名

---

### 3. Accounts 模块（发送账户管理）
**Schema 文件**:
- `app/api/v1/accounts/schema/account.py` (2处)
  - 第 537 行
  - 第 789 行

**Route 文件**:
- `app/api/v1/accounts/route/account_list.py`
  - 第 23 行: `request.args.get('per_page', 20, type=int)`
  - 第 32 行: `per_page=per_page`
- `app/api/v1/accounts/route/account_sender_validation.py`
  - 第 124 行: `per_page=5` (内部调用，限制冲突数量)

**Service 文件**:
- `app/services/accounts/account_service.py`
- `app/services/accounts/account_sender_config_service.py`

---

### 4. Account Connections 模块（账户连接管理）
**Schema 文件**:
- `app/api/v1/account_connections/schema/connection.py` (2处)
  - 第 222 行
  - 第 365 行
- `app/api/v1/account_connections/schema/query.py` (1处)
  - 第 190 行

**Route 文件**:
- `app/api/v1/account_connections/route/connection_list.py`
  - 第 37 行（文档注释）
  - 第 67 行: `'per_page': query_params.get('per_page', 20)`
  - 第 130 行: `'per_page': pagination_data.get('per_page')`
  - 第 196 行: `'per_page': 100` (刷新操作的限制)
  - 第 280、300、308、337 行（另一个接口）
- `app/api/v1/account_connections/route/connection_detail.py`
  - 第 481 行（文档注释）
  - 第 508 行: `per_page=query_params.get('per_page', 20)`
  - 第 539 行: `'per_page': result['per_page']`
- `app/api/v1/account_connections/route/connection_export.py`
  - 第 66 行: `'per_page': 10000` (导出时的大限制)

**Service 文件**:
- `app/services/customers/account_connection_service.py`

---

### 5. Admin Users 模块（管理员用户）
**Schema 文件**:
- `app/api/v1/admin_users/schema/admin_user_schema.py` (2处)
  - 第 210 行: 查询 schema
  - 第 254 行: 响应 schema（dump_only）

**Route 文件**:
- `app/api/v1/admin_users/route/admin_user_list.py`
  - 第 35 行（文档注释）
  - 第 92 行: `per_page=query_params.get('per_page', 20)`
  - 第 112 行: `'per_page': result['pagination']['per_page']`

**Service 文件**:
- `app/services/admin/admin_user_service.py`

---

### 6. Vendors 模块（供应商管理）
**Schema 文件**:
- `app/api/v1/vendors/schema/vendor.py` (1处)
  - 第 249 行

**Route 文件**:
- `app/api/v1/vendors/route/vendor_list.py`
  - 第 24 行: `request.args.get('per_page', 20, type=int)`
  - 第 33 行: `per_page=per_page`

**Service 文件**:
- `app/services/vendors/vendor_service.py`

---

### 7. Enterprises 模块（企业管理）
**Schema 文件**:
- `app/api/v1/enterprises/schema/enterprise_account.py` (1处)
  - 第 172 行

**Route 文件**:
- `app/api/v1/enterprises/route/enterprise_accounts.py`
  - 第 36 行: `request.args.get('per_page', 20, type=int)`
  - 第 51 行: `per_page=per_page`
  - 第 65 行: `'pageSize': result.get('pagination', {}).get('per_page', per_page)`

**Service 文件**:
- `app/services/enterprises/enterprise_service.py`

---

### 8. Country Regions 模块（国家地区管理）
**Schema 文件**:
- `app/api/v1/country_regions/schema/country_region_schema.py` (1处)
  - ⚠️ **特殊情况**: 第 194 行定义了 `per_page`，但第 242-244 行已有兼容处理：
    ```python
    # Handle frontend naming convention: page_size -> per_page
    if 'page_size' in data and 'per_page' not in data:
        data['per_page'] = data['page_size']
    ```
  - **建议**: 去掉兼容逻辑，直接改为 `page_size`

**Route 文件**:
- `app/api/v1/country_regions/routes.py`
  - 第 109 行: `per_page = query_params['per_page']`
  - 第 119 行: `per_page=per_page`
  - 第 144 行: `'page_size': pagination_info['per_page']` (注意这里输出是 page_size)

**Service 文件**:
- `app/services/country_regions/country_region_service.py`

---

### 9. Channel Country Prices 模块（渠道国家价格）
**Schema 文件**:
- `app/api/v1/channel_country_prices/schema/price_schema.py` (2处)
  - 第 35 行
  - 第 185 行

**Route 文件**:
- `app/api/v1/channel_country_prices/route/price_list.py`
  - 第 39 行: `per_page = kwargs.get('per_page', 20)`
  - 第 49 行: `per_page=per_page`
  - 第 62 行: `'per_page': result['pagination']['per_page']`
- `app/api/v1/channel_country_prices/route/price_history.py`
  - 第 39 行: `per_page = kwargs.get('per_page', 20)`
  - 第 52 行: `per_page=per_page`

**Service 文件**:
- `app/services/channel_country_prices/price_service.py`
- `app/services/channel_country_prices/batch_import_service.py`

---

## 修改步骤

### 第一步：Schema 层修改
对每个模块的 schema 文件：
1. 将字段定义从 `per_page` 改为 `page_size`
2. 保持字段验证规则不变（`validate=validate.Range(min=1, max=100)`）
3. 保持默认值不变（`load_default=20`）
4. 响应 schema 中的 `dump_only` 字段也要改

**示例**:
```python
# 修改前
per_page = fields.Int(load_default=20, validate=validate.Range(min=1, max=100))

# 修改后
page_size = fields.Int(load_default=20, validate=validate.Range(min=1, max=100))
```

### 第二步：Route 层修改
对每个模块的 route 文件：
1. 查询参数获取: `request.args.get('page_size', 20)` 或 `query_params['page_size']`
2. 调用 Service 时: `per_page=query_params['page_size']` (Service 层参数名保持 per_page)
3. 响应数据构造: 根据需要决定是否修改

**示例**:
```python
# 修改前
query_params = self.query_schema.load(request.args.to_dict())
result = self.service.get_list(
    page=query_params['page'],
    per_page=query_params['per_page']
)

# 修改后
query_params = self.query_schema.load(request.args.to_dict())
result = self.service.get_list(
    page=query_params['page'],
    per_page=query_params['page_size']  # 注意：传给 service 的参数名仍是 per_page
)
```

### 第三步：Service 层修改（可选）
Service 层的方法签名**可以保持 per_page 不变**，因为：
- Service 是内部实现，不直接暴露给前端
- 保持 per_page 可以减少改动范围
- 只在 API 边界（Schema/Route）统一使用 page_size

**如果要彻底统一**，也可以修改 Service 层：
1. 修改方法签名: `def get_list(self, page: int, per_page: int)` → `def get_list(self, page: int, page_size: int)`
2. 修改方法内部的变量名
3. 修改分页工具的调用

### 第四步：测试代码修改（必做）

**需要修改的测试文件**：
- `tests/api/accounts/test_account_list.py`
  - 第 116 行：`per_page=10` → `page_size=10`
  - 第 83、109、123、140 行：mock 数据中的 `'per_page'` → `'page_size'`

**修改示例**：
```python
# 修改前
def test_get_account_list_with_pagination(self, client, auth_headers, mock_current_user):
    """Test account list with pagination parameters."""
    with patch('app.api.v1.accounts.route.account_list.AccountService') as mock_service:
        mock_service_instance = Mock()
        mock_service.return_value = mock_service_instance
        mock_service_instance.get_accounts_with_filters.return_value = {
            'accounts': [],
            'pagination': {
                'page': 2,
                'per_page': 10,  # ← 需要改
                'total': 25,
                'pages': 3
            }
        }

        response = client.get(
            '/api/v1/sending-accounts/?page=2&per_page=10',  # ← 需要改
            headers=auth_headers
        )

        assert response.status_code == 200
        data = response.get_json()
        assert data['data']['pagination']['page'] == 2
        assert data['data']['pagination']['per_page'] == 10  # ← 需要改

# 修改后
def test_get_account_list_with_pagination(self, client, auth_headers, mock_current_user):
    """Test account list with pagination parameters."""
    with patch('app.api.v1.accounts.route.account_list.AccountService') as mock_service:
        mock_service_instance = Mock()
        mock_service.return_value = mock_service_instance
        mock_service_instance.get_accounts_with_filters.return_value = {
            'accounts': [],
            'pagination': {
                'page': 2,
                'page_size': 10,  # ✓ 已修改
                'total': 25,
                'pages': 3
            }
        }

        response = client.get(
            '/api/v1/sending-accounts/?page=2&page_size=10',  # ✓ 已修改
            headers=auth_headers
        )

        assert response.status_code == 200
        data = response.get_json()
        assert data['data']['pagination']['page'] == 2
        assert data['data']['pagination']['page_size'] == 10  # ✓ 已修改
```

**其他可能需要检查的测试文件**：
- 使用 grep 搜索所有测试中的 per_page：
  ```bash
  grep -r "per_page" tests/api/ --include="*.py"
  ```
- 逐一检查并修改相关测试用例

---

## 重要注意事项

### 1. 兼容性处理
某些模块（如 country_regions）已经有兼容逻辑，需要：
- ✅ 保留兼容逻辑作为过渡（如果前端可能发送 per_page）
- ❌ 或者直接移除兼容逻辑，彻底改为 page_size

**建议**: 彻底改为 page_size，移除所有兼容逻辑，避免混乱。

### 2. 响应字段
响应数据中的分页信息可能也包含 per_page：
```python
{
  "pagination": {
    "page": 1,
    "per_page": 20,  # 是否要改为 page_size？
    "total": 100
  }
}
```

**建议**:
- **前端已适配的模块**: 响应字段也改为 `page_size`
- **前端未适配的模块**: 暂时保持 `per_page`，或同时返回两个字段过渡

### 3. 特殊用途的 per_page
有些地方 per_page 用于特殊目的（非前端传参）：
- `account_connections/route/connection_export.py:66`: 导出时设置为 10000
- `accounts/route/account_sender_validation.py:124`: 冲突检查时设置为 5

这些**不需要修改**，因为它们是内部调用，不涉及前后端交互。

### 4. 文档注释
修改时记得更新：
- 路由文档字符串中的参数说明
- OpenAPI/Swagger 注释
- 示例代码中的参数名

### 5. 数据库/缓存影响
分页参数的重命名**不影响**：
- 数据库查询（只是变量名变化）
- 缓存键（除非缓存键中包含参数名）
- 数据持久化（分页参数不持久化）

### 6. 前端影响
前端已经统一使用 `page_size`，所以：
- ✅ **whitelist、blacklist、platform_errors、sms、sensitive_words** 模块无需修改前端
- ⚠️ **其他模块需要确认前端是发送 page_size 还是 per_page**

---

## 测试要点

### 1. 修改测试代码（每个阶段开始前执行）

**步骤 1.1：搜索测试文件中的 per_page**
```bash
grep -r "per_page" tests/api/ --include="*.py" -n
```

**步骤 1.2：修改测试文件**
对于每个包含 per_page 的测试文件：
- 修改请求 URL 中的参数：`per_page=10` → `page_size=10`
- 修改 mock 数据中的字段：`'per_page': 10` → `'page_size': 10`
- 修改断言中的字段：`assert data['pagination']['per_page']` → `assert data['pagination']['page_size']`

**步骤 1.3：运行测试验证**
```bash
# 运行修改过的测试文件
pytest tests/api/accounts/test_account_list.py -v

# 确保测试通过
```

### 2. 手工功能测试（每完成一个模块后执行）

**步骤 2.1：准备测试环境**
```bash
# 获取登录 token
export TOKEN="your_jwt_token_here"

# 或使用 curl 登录获取
TOKEN=$(curl -X POST http://localhost:5000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}' \
  | jq -r '.data.token')
```

**步骤 2.2：执行测试用例**

使用以下测试矩阵，对每个修改的模块执行测试：

| 测试用例 | URL 示例 | 预期结果 |
|---------|---------|---------|
| 基本分页 | `/api/v1/channels?page=1&page_size=20` | 200，返回最多 20 条数据 |
| 默认值 | `/api/v1/channels?page=1` | 200，page_size 默认为 20 |
| 最小边界 | `/api/v1/channels?page=1&page_size=1` | 200，返回 1 条数据 |
| 最大边界 | `/api/v1/channels?page=1&page_size=100` | 200，返回最多 100 条数据 |
| 无效值（0） | `/api/v1/channels?page=1&page_size=0` | 400，提示参数无效 |
| 无效值（超限） | `/api/v1/channels?page=1&page_size=101` | 400，提示参数无效 |
| 旧参数名 | `/api/v1/channels?page=1&per_page=20` | 400，提示 per_page 是未知字段 |

**步骤 2.3：测试脚本示例**

保存以下脚本为 `test_pagination.sh`：
```bash
#!/bin/bash

# 配置
API_BASE="http://localhost:5000"
TOKEN="your_token_here"
ENDPOINT="/api/v1/channels"  # 修改为你要测试的端点

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_case() {
    local name=$1
    local params=$2
    local expected_code=$3

    echo "Testing: $name"
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "${API_BASE}${ENDPOINT}?${params}")

    status_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    if [ "$status_code" -eq "$expected_code" ]; then
        echo -e "${GREEN}✓ PASS${NC} - Status: $status_code"
    else
        echo -e "${RED}✗ FAIL${NC} - Expected: $expected_code, Got: $status_code"
        echo "Response: $body"
    fi
    echo ""
}

echo "=== 开始分页参数测试 ==="
echo ""

test_case "基本分页" "page=1&page_size=20" 200
test_case "默认值测试" "page=1" 200
test_case "最小边界" "page=1&page_size=1" 200
test_case "最大边界" "page=1&page_size=100" 200
test_case "无效值0" "page=1&page_size=0" 400
test_case "超限值" "page=1&page_size=101" 400
test_case "旧参数名" "page=1&per_page=20" 400

echo "=== 测试完成 ==="
```

使用方法：
```bash
chmod +x test_pagination.sh
./test_pagination.sh
```

**步骤 2.4：记录测试结果**

| 模块 | 基本功能 | 默认值 | 边界值 | 错误值 | 旧参数拒绝 | 备注 |
|------|---------|--------|--------|--------|----------|------|
| Vendors | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Roles | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Admin Users | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Enterprises | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Country Regions | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Channels | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Accounts | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Account Connections | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |
| Channel Country Prices | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ | |

### 3. 前端集成测试（每完成一个阶段后执行）

**步骤 3.1：前端页面冒烟测试清单**

逐一打开以下页面，验证功能正常：

| 页面路径 | 功能检查项 | 测试结果 | 备注 |
|---------|----------|---------|------|
| `/channels` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/sending-accounts` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/account-connections` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/system/roles` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/system/admin-users` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/vendors` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/enterprises/accounts` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/system/country-regions` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |
| `/channel-country-prices` | ✓ 列表加载<br>✓ 分页组件显示<br>✓ 翻页功能<br>✓ 修改每页大小<br>✓ 无控制台错误 | ⬜ | |

**步骤 3.2：详细操作流程**

对每个页面执行以下操作：
1. 打开页面，观察列表是否正常加载
2. 检查浏览器控制台，确认无错误
3. 查看网络请求，确认发送的是 `page_size` 参数
4. 点击分页组件的"下一页"，验证翻页功能
5. 修改每页显示条数（如 10、20、50），验证列表重新加载
6. 在 URL 中验证参数格式：`?page=1&page_size=20`

### 4. 自动化测试运行（每个阶段完成后执行）

**步骤 4.1：运行单元测试**
```bash
# 运行所有 API 测试
pytest tests/api/ -v

# 如果有失败，查看详细输出
pytest tests/api/ -v --tb=short
```

**步骤 4.2：运行特定模块测试**
```bash
# 测试已统一的模块（回归测试）
pytest tests/api/whitelist/ -v
pytest tests/api/blacklist/ -v
pytest tests/api/sensitive_words/ -v

# 测试新修改的模块
pytest tests/api/accounts/ -v
pytest tests/api/channels/ -v
pytest tests/api/vendors/ -v
pytest tests/api/roles/ -v
```

**步骤 4.3：检查测试覆盖率（可选）**
```bash
pytest tests/api/ --cov=app/api/v1 --cov-report=html
# 打开 htmlcov/index.html 查看覆盖率报告
```

### 5. 回归测试（全部完成后执行）

**步骤 5.1：运行完整测试套件**
```bash
# 运行所有测试
pytest tests/ -v

# 确保所有测试通过
```

**步骤 5.2：前端构建测试**
```bash
cd frontend
npm run build

# 确保无错误，无警告
```

**步骤 5.3：验证已统一模块不受影响**

测试以下已经统一的模块，确保功能正常：
- ✅ 白名单管理（whitelist）
- ✅ 黑名单管理（blacklist）
- ✅ 平台错误管理（platform_errors）
- ✅ 短信管理（sms）
- ✅ 敏感词管理（sensitive_words）

---

## 修改顺序建议

**阶段一：小范围试点**（验证方案）
1. ✅ Vendors 模块（文件少，业务简单）
2. ✅ Roles 模块（文件少，业务简单）

**阶段二：中等规模**（扩大范围）
3. ✅ Admin Users 模块
4. ✅ Enterprises 模块
5. ✅ Country Regions 模块（注意移除兼容逻辑）

**阶段三：大规模核心模块**（最复杂）
6. ✅ Channels 模块（文件多，业务复杂）
7. ✅ Accounts 模块（文件多，业务关键）
8. ✅ Account Connections 模块（文件多，业务关键）
9. ✅ Channel Country Prices 模块

**每个阶段完成后**:
- 运行该模块的所有测试
- 手动测试前端页面
- 确认没有问题后再进入下一阶段

---

## 回滚方案

如果修改后出现问题：
1. 使用 git 回滚到修改前的版本
2. 检查前端实际发送的参数名（可能前端某些页面还在发送 per_page）
3. 考虑在 Schema 中添加临时兼容逻辑：
   ```python
   @post_load
   def handle_compatibility(self, data, **kwargs):
       # Temporary: support both per_page and page_size
       if 'per_page' in data and 'page_size' not in data:
           data['page_size'] = data['per_page']
       return data
   ```

---

## 最终检查清单

### 代码修改检查
- [ ] 所有 Schema 文件中的 `per_page` 已改为 `page_size`
- [ ] 所有 Route 文件中的 `query_params['per_page']` 已改为 `query_params['page_size']`
- [ ] 所有 `request.args.get('per_page')` 已改为 `request.args.get('page_size')`
- [ ] 文档注释中的 per_page 已更新
- [ ] 特殊用途的 per_page（导出、内部调用）已保留

### 测试代码检查
- [ ] 测试文件中的 `per_page=10` 已改为 `page_size=10`
- [ ] Mock 数据中的 `'per_page': 10` 已改为 `'page_size': 10`
- [ ] 断言中的 `data['pagination']['per_page']` 已改为 `data['pagination']['page_size']`
- [ ] 运行 `grep -r "per_page" tests/api/ --include="*.py"`，确认只剩下注释或无关引用

### 自动化测试检查
- [ ] 所有 API 测试通过：`pytest tests/api/ -v`
- [ ] 回归测试通过（已统一模块）：
  - [ ] `pytest tests/api/whitelist/ -v`
  - [ ] `pytest tests/api/blacklist/ -v`
  - [ ] `pytest tests/api/sensitive_words/ -v`
- [ ] 新修改模块测试通过

### 手工测试检查
- [ ] 9 个模块的 API 手工测试全部完成（参考测试矩阵）
- [ ] 所有测试用例（基本功能、默认值、边界值、错误值、旧参数拒绝）都通过

### 前端测试检查
- [ ] 9 个前端页面的冒烟测试全部完成
- [ ] 所有页面列表加载正常
- [ ] 分页组件工作正常
- [ ] 浏览器控制台无错误
- [ ] 网络请求参数为 `page_size` 而不是 `per_page`
- [ ] `npm run build` 无错误、无警告

### 代码清理检查
- [ ] 后端代码搜索确认：`grep -r "per_page" app/api/ --include="*.py"`
  - 确认只剩下注释、内部调用、导出等特殊用途
- [ ] 前端代码搜索确认：`grep -r "per_page" frontend/src/ --include="*.ts" --include="*.tsx"`
  - 确认已全部改为 `page_size`

### 文档更新检查
- [ ] API 文档中的参数说明已更新
- [ ] 本迁移计划文档已标记为"已完成"
- [ ] 更新记录已添加完成日期

---

## 估算工作量

### 代码修改
- **Schema 修改**: 约 20 个文件，预计 1-2 小时
- **Route 修改**: 约 20 个文件，预计 2-3 小时
- **测试代码修改**: 约 2-3 个文件，预计 0.5 小时

### 测试工作
- **手工 API 测试**: 9 个模块 × 20 分钟 = 3 小时
- **前端页面测试**: 9 个页面 × 15 分钟 = 2.5 小时
- **自动化测试运行**: 预计 1 小时
- **问题修复缓冲**: 预计 1-2 小时

### 总计
- **开发工作**: 3.5-5.5 小时
- **测试工作**: 6.5-8.5 小时
- **总计**: 约 10-14 小时（分 3 个阶段进行）

**建议分配**：
- 阶段一（Vendors + Roles）: 3-4 小时
- 阶段二（Admin Users + Enterprises + Country Regions）: 3-4 小时
- 阶段三（Channels + Accounts + Account Connections + Channel Country Prices）: 4-6 小时

---

## 相关文档

- 前端统一规范文档: (如果有的话)
- 后端 API 规范文档: (如果有的话)
- 分页组件使用文档: (如果有的话)

---

## 更新记录

- 2025-10-23: 创建本文档，分析了所有使用 per_page 的模块
- 2025-10-23: 完成 sensitive_words 模块的修改（作为参考示例）
