# 发送账号 - HTTP短信测试功能 - 详细设计与开发计划

## 一、需求概述

在发送账号列表页面（`http://localhost:5173/customers/sending-accounts`）的操作菜单中，为HTTP协议的发送账号新增"发送短信"功能，用于测试账号配置是否正确。

### 核心需求
1. 在操作菜单中添加"发送短信"按钮
2. 仅对HTTP协议的发送账号启用此功能，其他协议禁用
3. 弹出对话框支持输入手机号码（多个，每行一个）和短信内容
4. 对话框中显示账号的基本信息
5. 调用后端API向HTTP接口发送短信请求

### 验证规则
- 手机号码：必填，支持国际号码格式（如 +86 13800138000）
- 短信内容：必填，最大长度100字符
- 格式验证：暂不进行严格的手机号格式验证

### 结果处理
- 简化处理：只要API调用成功即视为成功
- 不检查实际短信是否发送成功

## 二、技术方案设计

### 2.1 后端设计

#### 2.1.1 API接口设计

**接口路径：** `POST /api/v1/sending-accounts/<account_id>/send-sms`

**请求参数：**
```json
{
  "phone_numbers": ["+8613800138000", "+8613900139000"],
  "message": "测试短信内容"
}
```

**响应格式：**
```json
{
  "success": true,
  "message": "短信发送请求已提交",
  "data": {
    "account_id": "ACC123",
    "total_numbers": 2,
    "submitted_at": "2025-01-15T10:30:00Z"
  }
}
```

**错误响应：**
```json
{
  "success": false,
  "message": "发送失败",
  "error": "账号协议类型不是HTTP"
}
```

#### 2.1.2 业务逻辑

1. **参数验证**
   - 验证account_id是否存在
   - 验证phone_numbers非空且为数组
   - 验证message非空且长度<=100

2. **协议检查**
   - 检查账号的protocol_type是否为'http'
   - 如果不是HTTP协议，返回错误

3. **配置提取**
   - 从account.protocol_config['http']获取HTTP配置
   - 提取url、method、auth_type、headers等配置

4. **HTTP请求构造**
   - 根据配置的认证类型添加认证信息
   - 构造请求体（根据配置的格式）
   - 设置超时时间

5. **发送请求**
   - 使用requests库向配置的URL发送请求
   - 捕获异常并返回友好错误信息
   - 记录日志

#### 2.1.3 文件结构

```
pigeon_web/app/api/v1/accounts/route/
├── account_sms_test.py          # 新建：短信测试接口
└── routes.py                     # 修改：注册新接口

pigeon_web/app/api/v1/accounts/schema/
└── account.py                    # 修改：添加短信发送请求Schema

pigeon_web/app/services/accounts/
└── account_sms_service.py        # 新建：短信发送服务
```

### 2.2 前端设计

#### 2.2.1 组件设计

**新增组件：** `SendSmsModal.tsx`

**位置：** `pigeon_web/frontend/src/pages/AccountControl/SendingAccounts/components/`

**组件结构：**
```tsx
interface SendSmsModalProps {
  visible: boolean;
  account: AccountListItem;
  onClose: () => void;
}
```

**UI布局：**
```
┌─────────────────────────────────────┐
│  发送短信测试                         │
├─────────────────────────────────────┤
│  【账号信息卡片】                     │
│  - 账号ID: ACC123                    │
│  - 账号名称: 测试账号                 │
│  - 协议类型: HTTP                    │
│  - HTTP接口: http://api.example.com  │
│  - 全局Sender: TestSender           │
├─────────────────────────────────────┤
│  手机号码（每行一个）* ┌─────────┐   │
│                      │+8613800..│   │
│                      │+8613900..│   │
│                      └─────────┘   │
├─────────────────────────────────────┤
│  短信内容 *           ┌─────────┐   │
│                      │测试内容  │   │
│                      └─────────┘   │
│                      (最多100字)    │
├─────────────────────────────────────┤
│            [取消]  [发送]            │
└─────────────────────────────────────┤
```

**样式规范：**
- 使用Ant Design Modal组件
- 卡片使用Alert或Descriptions组件展示账号信息
- 表单使用Form和FormItem
- 按钮样式与现有对话框保持一致
- 颜色、字体、间距遵循Material Design 3规范

#### 2.2.2 操作按钮集成

**修改文件：** `SendingAccountActionButtons.tsx`

**修改内容：**
1. 在dropdown菜单中添加"发送短信"选项
2. 添加按钮启用条件：`account.protocol_type === 'http'`
3. 添加点击处理函数

**菜单位置：**
```
操作菜单：
  - 查看详情
  - 编辑发送账号
  ─────────────
  - 连接测试
  - 发送短信  ← 新增（仅HTTP协议显示）
  - 暂停/激活发送账号
  ─────────────
  - 控制设置
  - 删除
```

#### 2.2.3 API集成

**修改文件：** `frontend/src/api/accountApi.ts`

**新增API定义：**
```typescript
// Send SMS test request
export interface SendSmsRequest {
  phone_numbers: string[];
  message: string;
}

export interface SendSmsResponse {
  account_id: string;
  total_numbers: number;
  submitted_at: string;
}

// API endpoint
sendSmsTest: builder.mutation<SendSmsResponse, {
  accountId: string;
  data: SendSmsRequest
}>({
  query: ({ accountId, data }) => ({
    url: `/sending-accounts/${accountId}/send-sms`,
    method: 'POST',
    body: data,
  }),
}),
```

## 三、开发计划

### 阶段一：后端开发

#### 1.1 创建Schema验证
- [ ] 在 `app/api/v1/accounts/schema/account.py` 中添加 `SendSmsRequestSchema`
- [ ] 定义phone_numbers字段（List[String]，必填）
- [ ] 定义message字段（String，必填，max_length=100）

#### 1.2 创建短信发送服务
- [ ] 创建 `app/services/accounts/account_sms_service.py`
- [ ] 实现 `send_test_sms(account_id, phone_numbers, message)` 方法
- [ ] 添加协议类型检查
- [ ] 添加HTTP配置提取
- [ ] 实现HTTP请求发送逻辑
- [ ] 添加异常处理和日志记录

#### 1.3 创建API接口
- [ ] 创建 `app/api/v1/accounts/route/account_sms_test.py`
- [ ] 实现 `AccountSmsTestResource` 类
- [ ] 添加 `@login_required` 装饰器
- [ ] 实现POST方法处理逻辑
- [ ] 添加参数验证
- [ ] 调用服务层方法
- [ ] 返回统一格式响应

#### 1.4 注册路由
- [ ] 在 `app/api/v1/accounts/route/routes.py` 中导入新Resource
- [ ] 注册路由 `/<account_id>/send-sms`
- [ ] 指定methods=['POST']

#### 1.5 后端测试
- [ ] 使用Postman或curl测试API
- [ ] 测试正常发送场景
- [ ] 测试参数验证
- [ ] 测试协议类型检查
- [ ] 测试错误处理

### 阶段二：前端开发

#### 2.1 创建SendSmsModal组件
- [ ] 创建 `SendSmsModal.tsx` 文件
- [ ] 添加文件头（Copyright信息）
- [ ] 定义组件Props接口
- [ ] 实现账号信息展示卡片
- [ ] 实现手机号码输入框（TextArea）
- [ ] 实现短信内容输入框（TextArea + 字数统计）
- [ ] 添加表单验证逻辑
- [ ] 实现发送按钮处理
- [ ] 添加loading状态
- [ ] 添加成功/失败提示

#### 2.2 集成到操作按钮
- [ ] 修改 `SendingAccountActionButtons.tsx`
- [ ] 在dropdown菜单中添加"发送短信"项
- [ ] 添加条件渲染：仅HTTP协议显示
- [ ] 添加状态管理（modal visible）
- [ ] 添加点击事件处理
- [ ] 渲染SendSmsModal组件

#### 2.3 API集成
- [ ] 在 `accountApi.ts` 中定义接口类型
- [ ] 添加 `sendSmsTest` mutation
- [ ] 配置缓存策略
- [ ] 导出hook：`useSendSmsTestMutation`

#### 2.4 样式调整
- [ ] 确保对话框宽度适中（建议600px）
- [ ] 调整卡片、表单间距
- [ ] 确保与现有对话框样式一致
- [ ] 添加响应式布局支持

#### 2.5 前端测试
- [ ] 测试对话框打开/关闭
- [ ] 测试表单验证
- [ ] 测试发送成功场景
- [ ] 测试发送失败场景
- [ ] 测试按钮启用/禁用条件
- [ ] 测试不同协议类型的账号

### 阶段三：联调与优化

#### 3.1 前后端联调
- [ ] 启动后端服务
- [ ] 启动前端开发服务器
- [ ] 测试完整流程
- [ ] 验证数据传输正确性
- [ ] 检查错误处理

#### 3.2 边界情况测试
- [ ] 测试空手机号列表
- [ ] 测试空短信内容
- [ ] 测试超长短信内容（>100字符）
- [ ] 测试特殊字符处理
- [ ] 测试网络异常情况
- [ ] 测试账号不存在情况
- [ ] 测试非HTTP协议账号

#### 3.3 用户体验优化
- [ ] 优化loading状态展示
- [ ] 优化错误提示文案
- [ ] 添加操作确认提示
- [ ] 优化表单交互体验

#### 3.4 代码审查
- [ ] 检查代码规范（英文注释、无过度注释）
- [ ] 检查文件头是否完整
- [ ] 检查错误处理是否完善
- [ ] 检查日志记录是否充分

### 阶段四：文档与提交

#### 4.1 更新文档
- [ ] 更新API文档
- [ ] 添加功能使用说明
- [ ] 记录已知限制

#### 4.2 代码提交
- [ ] 前端代码提交
- [ ] 后端代码提交
- [ ] 遵循提交规范：`feat(accounts): add HTTP SMS test feature`

## 四、技术细节

### 4.1 HTTP请求构造示例

```python
def send_http_sms(http_config, phone_numbers, message):
    """Send SMS via HTTP protocol."""
    url = http_config.get('url')
    method = http_config.get('method', 'POST').upper()
    auth_type = http_config.get('auth_type')

    # Construct request body
    payload = {
        'phone_numbers': phone_numbers,
        'message': message,
    }

    # Add authentication
    headers = http_config.get('headers', {}).copy()
    if auth_type == 'api_key':
        headers['X-API-Key'] = http_config.get('api_key')

    # Send request
    timeout = http_config.get('timeout', 30)

    if method == 'POST':
        response = requests.post(url, json=payload, headers=headers, timeout=timeout)
    else:
        response = requests.get(url, params=payload, headers=headers, timeout=timeout)

    response.raise_for_status()
    return response.json()
```

### 4.2 前端表单验证

```typescript
const validatePhoneNumbers = (value: string) => {
  if (!value || !value.trim()) {
    return '请输入至少一个手机号码';
  }
  const numbers = value.split('\n').filter(n => n.trim());
  if (numbers.length === 0) {
    return '请输入至少一个手机号码';
  }
  return undefined;
};

const validateMessage = (value: string) => {
  if (!value || !value.trim()) {
    return '请输入短信内容';
  }
  if (value.length > 100) {
    return '短信内容不能超过100字符';
  }
  return undefined;
};
```

### 4.3 样式参考

参考现有对话框组件：
- `SendingAccountOverviewModal.tsx` - 卡片布局、信息展示
- `AddSendingAccountModal.tsx` - 表单布局、按钮样式
- `AccountDetailModal.tsx` - 对话框整体风格

## 五、注意事项

1. **安全性**
   - 敏感信息（如密码、API密钥）不在前端展示
   - 后端需要验证用户权限
   - 日志记录时脱敏处理

2. **错误处理**
   - 网络超时友好提示
   - HTTP错误码转换为用户友好信息
   - 记录详细错误日志便于排查

3. **编码规范**
   - 所有注释使用英文
   - 避免过度注释
   - 添加文件头
   - 遵循项目编码习惯

4. **测试要求**
   - 修复后不能直接提交，等待用户测试确认
   - 需要测试各种边界情况
   - 确保不影响现有功能

5. **数据库变更**
   - 本功能不涉及数据库schema变更
   - 不需要创建迁移脚本

## 六、依赖关系

### 后端依赖
- Flask-RESTful（已有）
- requests库（需确认是否已安装）
- marshmallow（已有）

### 前端依赖
- Ant Design（已有）
- React Hook Form（已有）
- RTK Query（已有）

## 七、验收标准

1. ✅ HTTP协议账号的操作菜单中显示"发送短信"按钮
2. ✅ 非HTTP协议账号的"发送短信"按钮为禁用状态
3. ✅ 点击按钮后弹出对话框，显示账号基本信息
4. ✅ 可以输入多个手机号（每行一个）和短信内容
5. ✅ 表单验证正常工作（必填、长度限制）
6. ✅ 点击发送后调用API，显示loading状态
7. ✅ 发送成功/失败后显示相应提示
8. ✅ 对话框样式与现有对话框保持一致
9. ✅ 代码符合项目编码规范
10. ✅ 用户测试通过

## 八、后续优化方向

1. **功能增强**
   - 支持模板变量替换
   - 支持批量导入手机号
   - 显示每个号码的发送状态
   - 支持发送历史记录

2. **验证增强**
   - 手机号格式严格验证
   - 国际号码格式标准化
   - 重复号码检测

3. **用户体验**
   - 添加发送进度展示
   - 支持取消发送
   - 添加发送统计

4. **性能优化**
   - 大量号码时批量发送
   - 异步处理，不阻塞界面
   - 添加发送队列
