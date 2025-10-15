# HTTP协议支持详细设计文档

## 文档信息
- **创建时间**: 2025-01-15
- **作者**: Claude Code
- **版本**: v1.0
- **状态**: 设计阶段

## 1. 需求概述

### 1.1 背景
Pigeon SMS平台当前仅支持SMPP协议。为了支持更多客户端接入场景,需要在Gateway侧增加HTTP协议支持,允许客户端通过RESTful API提交短信。

### 1.2 使用场景
1. **pigeon_web管理员**: 通过Web UI界面发送短信,内部使用HTTP API
2. **外部客户端**: 第三方系统通过HTTP API集成短信发送功能

### 1.3 功能范围
**本期实现**:
- ✅ Gateway侧HTTP Server实现
- ✅ 支持MT消息(Mobile Terminated,下行短信)提交
- ✅ RESTful API + JSON格式
- ✅ Basic Auth认证(account_id + interface_password)
- ✅ JWT认证(for pigeon_web)
- ✅ 支持独立部署
- ✅ 健康检查接口
- ✅ pigeon_web UI查看消息状态(查询数据库)

**暂不实现**:
- ❌ Channel侧HTTP Client
- ❌ Webhook推送状态报告给外部客户端
- ❌ 外部客户端查询消息状态API
- ❌ MO消息(Mobile Originated,上行短信)接收
- ❌ HTTP长短信合并拆分
- ❌ 限流和并发控制

## 2. 架构设计

### 2.1 协议抽象层设计

当前项目已有良好的协议抽象:
```
protocol/
├── server/
│   ├── server.go          # Server接口定义
│   ├── types.go           # Handler函数类型定义
│   └── smpp/              # SMPP实现
│       └── server.go
├── pdu/
│   └── base/              # 协议无关的PDU抽象
│       ├── pdu.go
│       ├── pdu_connect.go
│       ├── pdu_submit.go
│       └── pdu_deliver.go
└── factory/
    └── server_factory.go  # Server工厂
```

**HTTP协议将复用这套抽象**,新增:
```
protocol/
├── server/
│   └── http/              # HTTP实现(新增)
│       ├── server.go      # HTTP Server核心
│       ├── handler.go     # HTTP请求处理
│       ├── middleware.go  # 中间件(认证/日志)
│       └── types.go       # HTTP特定类型定义
└── pdu/
    └── http/              # HTTP PDU实现(新增)
        ├── submit_request.go
        └── submit_response.go
```

### 2.2 HTTP与SMPP对比

| 特性 | SMPP | HTTP |
|------|------|------|
| 连接方式 | 长连接 | 无状态短连接 |
| 认证 | Bind时认证一次 | 每次请求都认证 |
| Session管理 | 需要维护session | 不需要session |
| 心跳机制 | enquire_link | 不需要 |
| PDU类型 | ConnectRequest, SubmitRequest, DeliverRequest等 | 仅SubmitRequest |
| 消息格式 | 二进制PDU | JSON |
| 序列号 | 需要sequence_number | 不需要 |

### 2.3 HTTP到PDU的映射关系

#### 2.3.1 HTTP Request → base.SubmitRequest

**HTTP请求**:
```http
POST /api/v1/messages HTTP/1.1
Host: localhost:8080
Content-Type: application/json
Authorization: Basic dGVzdDp0ZXN0MTIz

{
  "from": "1234",
  "to": "+8613800138000",
  "content": "Hello World",
  "encoding": "UCS2"
}
```

**映射到base.SubmitRequest**:
```go
type HTTPSubmitRequest struct {
    // base.Request接口字段
    account        string  // 从Authorization解析
    srcAddress     string  // HTTP客户端IP
    sequenceNumber uint32  // HTTP不需要,设为0

    // base.SubmitRequest接口字段
    from           string  // HTTP body.from
    to             string  // HTTP body.to
    content        string  // HTTP body.content
    encoding       string  // HTTP body.encoding
}
```

**关键设计点**:
- HTTP不需要ConnectRequest,直接实现SubmitRequest
- sequenceNumber在HTTP中无意义,统一设为0
- srcAddress使用HTTP客户端IP地址
- 完整实现base.SubmitRequest接口,复用Gateway的HandleSubmit逻辑

#### 2.3.2 base.SubmitResponse → HTTP Response

**HTTP响应**:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "code": 0,
  "message": "success",
  "data": {
    "message_id": "gw_http_001_20250115123456_001",
    "status": "accepted",
    "submitted_at": "2025-01-15T12:34:56Z"
  }
}
```

**错误响应**:
```http
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "code": 401,
  "message": "invalid password",
  "data": null
}
```

### 2.4 认证方案

#### 2.4.1 Basic Auth(外部客户端)
- 使用Account表的`account_id`和`interface_password`
- HTTP Header: `Authorization: Basic base64(account_id:interface_password)`
- 每次请求都验证账号密码

**示例**:
```bash
# account_id=test, interface_password=test123
# base64("test:test123") = dGVzdDp0ZXN0MTIz

curl -X POST http://localhost:8080/api/v1/messages \
  -H "Authorization: Basic dGVzdDp0ZXN0MTIz" \
  -H "Content-Type: application/json" \
  -d '{"from":"1234","to":"+8613800138000","content":"Hello"}'
```

#### 2.4.2 JWT Token(pigeon_web)
- 使用pigeon_web现有的JWT认证
- HTTP Header: `Authorization: Bearer <jwt_token>`
- 验证JWT签名和过期时间

**JWT Payload**:
```json
{
  "account_id": "web_account_001",
  "user_id": 123,
  "exp": 1705334096
}
```

### 2.5 部署模式

**独立部署**: SMPP Gateway和HTTP Gateway作为独立进程运行

#### 目录结构:
```
config/gateway/
├── conf.toml       # SMPP Gateway配置
└── conf.http.toml  # HTTP Gateway配置(新增)
```

#### HTTP Gateway配置示例:
```toml
# config/gateway/conf.http.toml
[gateway]

[gateway.delivery]
code = "gw_http"                       # Gateway标识(自动加随机后缀)
deliver_pool_size = 50
deliver_pop_timeout = 5                # 秒
deliver_waiting_second = 30
server_type = "HTTP_V1"                # 协议类型(新增)
listen_addr = "127.0.0.1:8080"         # HTTP监听地址
server_worker_pool_size = 2000         # 并发处理池大小

# HTTP特定配置(新增)
[gateway.delivery.http]
request_timeout = 30                   # 请求超时(秒)
max_body_size = 1048576               # 最大请求体(1MB)
enable_cors = true                     # 是否启用CORS
cors_origins = ["http://localhost:5173"]  # 允许的源

# JWT配置(for pigeon_web)
[gateway.delivery.http.jwt]
secret = "your-jwt-secret-key"
issuer = "pigeon_web"

# 以下配置与SMPP Gateway相同
[gateway.usecase]
merge_long_msg_retry_count = 10
merge_long_msg_retry_interval = 100
counter_periods = ["1s", "30s", "1m", "5m", "10m", "30m", "1h", "4h", "12h", "1d", "3d"]
counter_expire_count = 30

[gateway.repo]
# ... (与SMPP相同)
```

#### 启动命令:
```bash
# SMPP Gateway
cd pigeon/src/main/gateway
./start.sh --config=../../config/gateway/conf.toml

# HTTP Gateway(新增)
cd pigeon/src/main/gateway
./start.sh --config=../../config/gateway/conf.http.toml
```

## 3. 数据模型

### 3.1 ProtocolType扩展

**文件**: `pigeon/src/models/types.go`

```go
type ProtocolType string

const (
    SMPPV34ProtocolType ProtocolType = "SMPP_V32"
    HTTPV1ProtocolType  ProtocolType = "HTTP_V1"   // 新增
)
```

### 3.2 数据库变更

**无需修改数据库Schema**

说明:
- Account表已有`protocol_type`字段,支持SMPP
- HTTP协议复用相同字段,只需添加"HTTP_V1"枚举值
- pigeon_web的Account模型已支持protocol_type配置

### 3.3 pigeon_web模型更新

**文件**: `pigeon_web/app/models/customers/account.py`

```python
class ProtocolType(enum.Enum):
    """Protocol type enumeration."""
    SMPP = 'smpp'
    HTTP = 'http'  # 新增
```

**文件**: `pigeon_web/frontend/src/pages/AccountControl/SendingAccounts/components/AccountForm/ProtocolSettingsStep.tsx`

```typescript
// 协议类型选项
const protocolTypeOptions = [
  { label: 'SMPP', value: 'smpp' },
  { label: 'HTTP', value: 'http' },  // 启用HTTP选项
  { label: 'CMPP(暂时隐藏)', value: 'cmpp', disabled: true },
];
```

## 4. API设计

### 4.1 RESTful API规范

#### Base URL
- 开发环境: `http://localhost:8080/api/v1`
- 生产环境: `https://gateway.example.com/api/v1`

#### 通用响应格式
```json
{
  "code": 0,           // 0表示成功,其他表示错误码
  "message": "success",
  "data": { ... }      // 响应数据,可为null
}
```

#### 错误码映射
```go
// SMPP错误码映射到HTTP状态码
var httpStatusMapping = map[errors.ErrorCode]int{
    errors.ESME_ROK:           200,  // 成功
    errors.ESME_RINVPASWD:     401,  // 认证失败
    errors.ESME_RINVSYSID:     401,  // 账号不存在
    errors.ESME_RINVDSTADR:    400,  // 无效的目标地址
    errors.ESME_RSUBMITFAIL:   500,  // 提交失败
    errors.ESME_RMSGQFUL:      503,  // 队列满
}
```

### 4.2 API接口清单

#### 4.2.1 健康检查

**接口**: `GET /health`

**描述**: 检查HTTP Gateway服务状态

**认证**: 不需要

**响应**:
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "status": "healthy",
    "version": "1.0.0",
    "protocol": "HTTP_V1",
    "gateway_code": "gw_http_001",
    "uptime_seconds": 3600
  }
}
```

#### 4.2.2 发送短信

**接口**: `POST /api/v1/messages`

**描述**: 提交短信到Gateway

**认证**: Required (Basic Auth或JWT)

**请求Header**:
```
Authorization: Basic base64(account_id:interface_password)
# 或
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**请求Body**:
```json
{
  "from": "1234",                    // 发送方,可选,默认使用Account的sender_id
  "to": "+8613800138000",            // 接收方,必填,E.164格式
  "content": "Hello World",          // 短信内容,必填
  "encoding": "UCS2"                 // 编码方式,可选,默认ASCII
}
```

**字段说明**:
- `from`: 发送方号码,可选。如果不提供,使用Account配置的sender_id
- `to`: 接收方号码,必填。格式为E.164(如+8613800138000)
- `content`: 短信内容,必填。长度限制根据encoding不同而不同
- `encoding`: 编码方式,可选。支持: "ASCII", "UCS2", "GSM-7bit", "ISO-8859-1"

**成功响应** (HTTP 200):
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "message_id": "gw_http_001_20250115123456_001",
    "status": "accepted",
    "submitted_at": "2025-01-15T12:34:56Z"
  }
}
```

**错误响应示例**:

1. 认证失败 (HTTP 401):
```json
{
  "code": 401,
  "message": "invalid password",
  "data": null
}
```

2. 账号不存在 (HTTP 401):
```json
{
  "code": 401,
  "message": "account not found",
  "data": null
}
```

3. 参数错误 (HTTP 400):
```json
{
  "code": 400,
  "message": "invalid destination address",
  "data": null
}
```

4. 队列满 (HTTP 503):
```json
{
  "code": 503,
  "message": "message queue is full",
  "data": null
}
```

## 5. 核心实现

### 5.1 HTTP Server实现

**文件**: `pigeon/src/protocol/server/http/server.go`

```go
// Copyright (c) 2025 .
// All rights reserved.
//
// Author: yukun.xing <xingyukun@gmail.com>
// Date:   2025/01/15

package http

import (
    "context"
    "net/http"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/pkg/errors"

    "pigeon/src/base/logger"
    "pigeon/src/protocol/server"
    "pigeon/src/protocol/pdu/base"
    "pigeon/src/gateway"
)

var log = logger.Get()

type httpServer struct {
    listenAddr          string
    router              *gin.Engine
    httpServer          *http.Server
    isHandlerRegistered bool
    usecase             gateway.IUsecase  // 用于账号验证等

    // Handler functions (满足server.Server接口)
    handleSubmit        server.SubmitHandlerFunc

    // 以下handler在HTTP中不使用,但为了实现接口需要保留
    handleConnect       server.ConnectHandlerFunc
    handleDisconnect    server.DisconnectHandlerFunc
    handleDeliverResp   server.DeliverResponseHandlerFunc
    afterDisconnect     server.AfterDisconnectHandlerFunc
}

func NewServer(listenAddr string, submitWorkerPoolSize int) (server.Server, error) {
    gin.SetMode(gin.ReleaseMode)
    router := gin.New()
    router.Use(gin.Recovery())
    router.Use(loggerMiddleware())

    s := &httpServer{
        listenAddr: listenAddr,
        router:     router,
    }

    s.registerRoutes()
    return s, nil
}

func (s *httpServer) registerRoutes() {
    // Health check (不需要认证)
    s.router.GET("/health", s.handleHealth)

    // API v1
    api := s.router.Group("/api/v1")
    {
        api.POST("/messages", s.authMiddleware(), s.handleSubmitMessage)
    }
}

func (s *httpServer) SetUsecase(usecase gateway.IUsecase) {
    s.usecase = usecase
}

func (s *httpServer) RegisterHandler(
    handleConnect server.ConnectHandlerFunc,
    handleSubmit server.SubmitHandlerFunc,
    handleDisconnect server.DisconnectHandlerFunc,
    handleDeliverResp server.DeliverResponseHandlerFunc,
    afterDisconnect server.AfterDisconnectHandlerFunc) error {

    if handleSubmit == nil {
        return errors.New("Submit handler is nil")
    }

    s.handleConnect = handleConnect
    s.handleSubmit = handleSubmit
    s.handleDisconnect = handleDisconnect
    s.handleDeliverResp = handleDeliverResp
    s.afterDisconnect = afterDisconnect
    s.isHandlerRegistered = true

    return nil
}

func (s *httpServer) Start(ctx context.Context) error {
    if !s.isHandlerRegistered {
        return errors.New("Handlers are not registered")
    }

    s.httpServer = &http.Server{
        Addr:           s.listenAddr,
        Handler:        s.router,
        ReadTimeout:    30 * time.Second,
        WriteTimeout:   30 * time.Second,
        MaxHeaderBytes: 1 << 20,
    }

    go func() {
        <-ctx.Done()
        shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        s.httpServer.Shutdown(shutdownCtx)
    }()

    log.Info("HTTP server starting", "addr", s.listenAddr)
    if err := s.httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        return errors.Wrap(err, "HTTP server failed")
    }
    return nil
}

func (s *httpServer) Stop() error {
    if s.httpServer != nil {
        ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
        defer cancel()
        return s.httpServer.Shutdown(ctx)
    }
    return nil
}

// HTTP协议没有session概念
func (s *httpServer) HasSession(account string) bool {
    return false
}

// HTTP协议不需要enquire link
func (s *httpServer) RunEnquireLink(
    sessionCtx context.Context, sessionI any,
    systemID, remoteIp string) server.TimerController {
    return nil
}

// HTTP不使用这些PDU处理方法
func (s *httpServer) HandleConnectPDU(
    request base.ConnectRequest, reqErr error) (base.ConnectResponse, bool, error) {
    return nil, false, errors.New("not implemented for HTTP")
}

func (s *httpServer) HandleSubmitPDU(
    request base.SubmitRequest, reqErr error) (base.SubmitResponse, error) {
    return s.handleSubmit(request)
}

func (s *httpServer) HandleDisconnectPDU(
    request base.DisconnectRequest, reqErr error) (base.DisconnectResponse, bool, error) {
    return nil, false, errors.New("not implemented for HTTP")
}

// HTTP不支持deliver推送
func (s *httpServer) SendDeliverRequest(account string, request base.DeliverRequest) error {
    return errors.New("HTTP protocol does not support deliver push")
}

func (s *httpServer) HandleDeliverResponse(response base.DeliverResponse) error {
    return errors.New("not implemented for HTTP")
}
```

### 5.2 HTTP Handler实现

**文件**: `pigeon/src/protocol/server/http/handler.go`

```go
// Copyright (c) 2025 .
// All rights reserved.
//
// Author: yukun.xing <xingyukun@gmail.com>
// Date:   2025/01/15

package http

import (
    "net/http"
    "time"

    "github.com/gin-gonic/gin"

    "pigeon/src/protocol/pdu/httpPdu"
    gwError "pigeon/src/errors"
)

type SubmitMessageRequest struct {
    From     string `json:"from"`
    To       string `json:"to" binding:"required"`
    Content  string `json:"content" binding:"required"`
    Encoding string `json:"encoding"`
}

func (s *httpServer) handleHealth(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{
        "code": 0,
        "message": "success",
        "data": gin.H{
            "status":         "healthy",
            "version":        "1.0.0",
            "protocol":       "HTTP_V1",
            "uptime_seconds": time.Now().Unix(),
        },
    })
}

func (s *httpServer) handleSubmitMessage(c *gin.Context) {
    var req SubmitMessageRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{
            "code":    http.StatusBadRequest,
            "message": "invalid request body: " + err.Error(),
            "data":    nil,
        })
        return
    }

    // 从context获取认证后的account_id
    accountID, exists := c.Get("account_id")
    if !exists {
        c.JSON(http.StatusUnauthorized, gin.H{
            "code":    http.StatusUnauthorized,
            "message": "account not found in context",
            "data":    nil,
        })
        return
    }

    // 构建HTTP SubmitRequest
    submitReq := httpPdu.NewSubmitRequest(
        accountID.(string),
        c.ClientIP(),
        &req,
    )

    // 调用Gateway的HandleSubmit
    submitResp, err := s.handleSubmit(submitReq)

    // 转换为HTTP响应
    statusCode := http.StatusOK
    respCode := 0
    respMsg := "success"

    if err != nil {
        statusCode = mapErrorToHTTPStatus(err)
        respCode = gwError.ExtractErrorCode(err)
        respMsg = err.Error()

        c.JSON(statusCode, gin.H{
            "code":    respCode,
            "message": respMsg,
            "data":    nil,
        })
        return
    }

    c.JSON(statusCode, gin.H{
        "code":    respCode,
        "message": respMsg,
        "data": gin.H{
            "message_id":   submitResp.GetMessageID(),
            "status":       "accepted",
            "submitted_at": time.Now().Format(time.RFC3339),
        },
    })
}

func mapErrorToHTTPStatus(err error) int {
    errCode := gwError.ExtractErrorCode(err)

    switch errCode {
    case int32(gwError.ESME_ROK):
        return http.StatusOK
    case int32(gwError.ESME_RINVPASWD), int32(gwError.ESME_RINVSYSID):
        return http.StatusUnauthorized
    case int32(gwError.ESME_RINVDSTADR), int32(gwError.ESME_RINVSRCADR):
        return http.StatusBadRequest
    case int32(gwError.ESME_RMSGQFUL):
        return http.StatusServiceUnavailable
    default:
        return http.StatusInternalServerError
    }
}
```

### 5.3 认证中间件

**文件**: `pigeon/src/protocol/server/http/middleware.go`

```go
// Copyright (c) 2025 .
// All rights reserved.
//
// Author: yukun.xing <xingyukun@gmail.com>
// Date:   2025/01/15

package http

import (
    "encoding/base64"
    "net/http"
    "strings"

    "github.com/gin-gonic/gin"
)

func (s *httpServer) authMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        authHeader := c.GetHeader("Authorization")
        if authHeader == "" {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                "code":    http.StatusUnauthorized,
                "message": "missing authorization header",
                "data":    nil,
            })
            return
        }

        // 支持Basic Auth (外部客户端)
        if strings.HasPrefix(authHeader, "Basic ") {
            if s.handleBasicAuth(c, authHeader) {
                c.Next()
                return
            }
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                "code":    http.StatusUnauthorized,
                "message": "invalid credentials",
                "data":    nil,
            })
            return
        }

        // 支持Bearer Token (pigeon_web JWT)
        if strings.HasPrefix(authHeader, "Bearer ") {
            if s.handleJWTAuth(c, authHeader) {
                c.Next()
                return
            }
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
                "code":    http.StatusUnauthorized,
                "message": "invalid token",
                "data":    nil,
            })
            return
        }

        c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
            "code":    http.StatusUnauthorized,
            "message": "unsupported authorization type",
            "data":    nil,
        })
    }
}

func (s *httpServer) handleBasicAuth(c *gin.Context, authHeader string) bool {
    encoded := strings.TrimPrefix(authHeader, "Basic ")
    decoded, err := base64.StdEncoding.DecodeString(encoded)
    if err != nil {
        log.Warn("Failed to decode basic auth", "error", err)
        return false
    }

    parts := strings.SplitN(string(decoded), ":", 2)
    if len(parts) != 2 {
        log.Warn("Invalid basic auth format")
        return false
    }

    accountID := parts[0]
    password := parts[1]

    // 验证账号密码
    account, err := s.usecase.GetAccount(accountID)
    if err != nil || account == nil {
        log.Warn("Account not found", "account_id", accountID)
        return false
    }

    // 验证interface_password
    if account.InterfacePassword != password {
        log.Warn("Invalid password", "account_id", accountID)
        return false
    }

    // 保存到context
    c.Set("account_id", accountID)
    c.Set("account", account)

    log.Info("Basic auth successful", "account_id", accountID)
    return true
}

func (s *httpServer) handleJWTAuth(c *gin.Context, authHeader string) bool {
    token := strings.TrimPrefix(authHeader, "Bearer ")

    // TODO: 实现JWT验证
    // 1. 解析JWT token
    // 2. 验证签名
    // 3. 检查过期时间
    // 4. 提取account_id

    // 临时实现: 暂不验证,直接返回false
    log.Warn("JWT auth not implemented yet")
    return false
}

func loggerMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        path := c.Request.URL.Path
        method := c.Request.Method

        c.Next()

        latency := time.Since(start)
        statusCode := c.Writer.Status()

        log.Info("HTTP request",
            "method", method,
            "path", path,
            "status", statusCode,
            "latency_ms", latency.Milliseconds(),
            "client_ip", c.ClientIP())
    }
}
```

### 5.4 HTTP PDU实现

**文件**: `pigeon/src/protocol/pdu/http/submit_request.go`

```go
// Copyright (c) 2025 .
// All rights reserved.
//
// Author: yukun.xing <xingyukun@gmail.com>
// Date:   2025/01/15

package http

import (
    "fmt"

    "pigeon/src/protocol/pdu/base"
    "pigeon/src/models"
    "pigeon/src/errors"
)

type SubmitMessageRequest struct {
    From     string
    To       string
    Content  string
    Encoding string
}

type SubmitRequest struct {
    account        string
    srcAddress     string
    sequenceNumber uint32

    from           string
    to             string
    content        string
    encoding       string
}

func NewSubmitRequest(accountID, srcIP string, req *SubmitMessageRequest) *SubmitRequest {
    return &SubmitRequest{
        account:        accountID,
        srcAddress:     srcIP,
        sequenceNumber: 0,
        from:           req.From,
        to:             req.To,
        content:        req.Content,
        encoding:       req.Encoding,
    }
}

// 实现 base.Request 接口
func (r *SubmitRequest) GetAccount() string {
    return r.account
}

func (r *SubmitRequest) GetSrcAddress() string {
    return r.srcAddress
}

func (r *SubmitRequest) GetCommandId() uint32 {
    return 0
}

func (r *SubmitRequest) GetStatus() int32 {
    return 0
}

func (r *SubmitRequest) GetSequenceNumber() uint32 {
    return r.sequenceNumber
}

func (r *SubmitRequest) SetAccount(account string) {
    r.account = account
}

func (r *SubmitRequest) SetSrcAddress(srcIPAddr string) {
    r.srcAddress = srcIPAddr
}

func (r *SubmitRequest) SetCommandId(commandID uint32) {
    // no-op for HTTP
}

func (r *SubmitRequest) SetStatus(status int32) {
    // no-op for HTTP
}

func (r *SubmitRequest) SetSequenceNumber(seqNum uint32) {
    r.sequenceNumber = seqNum
}

func (r *SubmitRequest) GenResponse(status int32) base.Response {
    return &SubmitResponse{
        account:        r.account,
        status:         status,
        sequenceNumber: r.sequenceNumber,
    }
}

func (r *SubmitRequest) ToRequestPDU() interface{} {
    return r
}

func (r *SubmitRequest) ToString() string {
    return fmt.Sprintf("HTTPSubmit{account=%s, from=%s, to=%s, content_len=%d}",
        r.account, r.from, r.to, len(r.content))
}

// 实现 base.SubmitRequest 接口
func (r *SubmitRequest) CanPassthrough() bool {
    return false
}

func (r *SubmitRequest) GetSrcAddr() (*base.Address, error) {
    if r.from == "" {
        return nil, errors.NewError(nil, errors.ESME_RINVSRCADR)
    }

    return &base.Address{
        TON:  1,
        NPI:  1,
        Addr: r.from,
    }, nil
}

func (r *SubmitRequest) GetDestAddr() (*base.Address, error) {
    if r.to == "" {
        return nil, errors.NewError(nil, errors.ESME_RINVDSTADR)
    }

    return &base.Address{
        TON:  1,
        NPI:  1,
        Addr: r.to,
    }, nil
}

func (r *SubmitRequest) GetMessage() base.Message {
    encoding := models.ContentEncodingASCII
    switch r.encoding {
    case "UCS2":
        encoding = models.ContentEncodingUCS2
    case "GSM-7bit":
        encoding = models.ContentEncodingGSM7Bit
    case "ISO-8859-1":
        encoding = models.ContentEncodingLatin1
    }

    return &SimpleMessage{
        content:  []byte(r.content),
        encoding: encoding,
    }
}

func (r *SubmitRequest) SetSrcAddr(addr *base.Address) error {
    r.from = addr.Addr
    return nil
}

func (r *SubmitRequest) SetDestAddr(addr *base.Address) error {
    r.to = addr.Addr
    return nil
}

func (r *SubmitRequest) SetMessage(msg base.Message) error {
    r.content = string(msg.GetContent())
    return nil
}

func (r *SubmitRequest) ToShortMessageModel(gwCode string, senderID string) *models.ShortMessage {
    srcAddr, _ := r.GetSrcAddr()
    destAddr, _ := r.GetDestAddr()
    message := r.GetMessage()

    sm := &models.ShortMessage{
        AccountID:          r.account,
        GatewayCode:        gwCode,
        GatewayFromAddress: srcAddr,
        GatewayToAddress:   destAddr,
        GatewayContent:     message.GetContent(),
        GatewayEncoding:    message.GetEncoding(),
        // ... 其他字段由Gateway填充
    }

    return sm
}

// SimpleMessage实现base.Message接口
type SimpleMessage struct {
    content  []byte
    encoding models.ContentEncoding
}

func (m *SimpleMessage) GetContent() []byte {
    return m.content
}

func (m *SimpleMessage) GetEncoding() models.ContentEncoding {
    return m.encoding
}

func (m *SimpleMessage) IsLongMessage() bool {
    return false
}

func (m *SimpleMessage) GetLongMessageInfo() *base.LongMessageInfo {
    return nil
}
```

**文件**: `pigeon/src/protocol/pdu/http/submit_response.go`

```go
// Copyright (c) 2025 .
// All rights reserved.
//
// Author: yukun.xing <xingyukun@gmail.com>
// Date:   2025/01/15

package http

import (
    "fmt"

    "pigeon/src/protocol/pdu/base"
    "pigeon/src/errors"
)

type SubmitResponse struct {
    account        string
    srcAddress     string
    status         int32
    sequenceNumber uint32
    messageID      string
}

func NewSubmitResponse(account string) *SubmitResponse {
    return &SubmitResponse{
        account: account,
    }
}

// 实现 base.Response 接口
func (r *SubmitResponse) GetAccount() string {
    return r.account
}

func (r *SubmitResponse) GetSrcAddress() string {
    return r.srcAddress
}

func (r *SubmitResponse) GetCommandId() uint32 {
    return 0
}

func (r *SubmitResponse) GetStatus() int32 {
    return r.status
}

func (r *SubmitResponse) GetSequenceNumber() uint32 {
    return r.sequenceNumber
}

func (r *SubmitResponse) SetAccount(account string) {
    r.account = account
}

func (r *SubmitResponse) SetSrcAddress(srcIPAddr string) {
    r.srcAddress = srcIPAddr
}

func (r *SubmitResponse) SetCommandId(commandID uint32) {
    // no-op for HTTP
}

func (r *SubmitResponse) SetStatus(status int32) {
    r.status = status
}

func (r *SubmitResponse) SetSequenceNumber(seqNum uint32) {
    r.sequenceNumber = seqNum
}

func (r *SubmitResponse) ToResponsePDU() interface{} {
    return r
}

func (r *SubmitResponse) ToString() string {
    return fmt.Sprintf("HTTPSubmitResp{account=%s, status=%d, message_id=%s}",
        r.account, r.status, r.messageID)
}

// 实现 base.SubmitResponse 接口
func (r *SubmitResponse) GetMessageID() string {
    return r.messageID
}

func (r *SubmitResponse) GetSubmitStatus() errors.SubmitResponseStatus {
    if r.status == int32(errors.ESME_ROK) {
        return errors.SubmitSuccess
    }
    return errors.SubmitFailed
}

func (r *SubmitResponse) SetMessageID(msgID string) {
    r.messageID = msgID
}
```

### 5.5 Factory扩展

**文件**: `pigeon/src/protocol/factory/server_factory.go`

```go
package factory

import (
    "errors"
    "fmt"

    "pigeon/src/models"
    "pigeon/src/protocol/server"
    "pigeon/src/protocol/server/smpp"
    "pigeon/src/protocol/server/http"  // 新增
)

func NewServer(
    protocolType models.ProtocolType,
    listenAddr string, submitWorkerPoolSize int) (server.Server, error) {

    switch protocolType {
    case models.SMPPV34ProtocolType:
        return smpp.NewServer(listenAddr, submitWorkerPoolSize)
    case models.HTTPV1ProtocolType:  // 新增
        return http.NewServer(listenAddr, submitWorkerPoolSize)
    default:
        errMsg := fmt.Sprintf("Unsupported server type: |%s|.", protocolType)
        return nil, errors.New(errMsg)
    }
}
```

### 5.6 Gateway Delivery集成

**文件**: `pigeon/src/gateway/delivery/gateway.go`

需要在创建server后设置usecase:

```go
func NewGatewayDelivery() (gatewayP.IDelivery, error) {
    // ... 现有代码 ...

    server, err := serverFactory.NewServer(
        d.protocolType,
        cfg.GetString("gateway.delivery.listen_addr"),
        cfg.GetInt("gateway.delivery.server_worker_pool_size"))
    if err != nil {
        return nil, errors.WithMessage(err, "Create server failed.")
    }
    d.server = server

    // 如果是HTTP server,设置usecase(用于认证)
    if d.protocolType == models.HTTPV1ProtocolType {
        if httpServer, ok := server.(interface{ SetUsecase(gateway.IUsecase) }); ok {
            httpServer.SetUsecase(usecase)
        }
    }

    // ... 现有代码 ...
}
```

## 6. 开发计划

### 第1步: 基础框架搭建
1. 扩展`models.ProtocolType`,添加`HTTPV1ProtocolType`
2. 创建目录结构:
   - `pigeon/src/protocol/server/http/`
   - `pigeon/src/protocol/pdu/http/`
3. 创建空的`http.Server`结构体,实现`server.Server`接口(空实现)
4. 扩展`server_factory.go`,添加HTTP分支
5. 创建HTTP配置文件`config/gateway/conf.http.toml`
6. 测试: 验证HTTP Gateway可以启动(虽然无功能)

### 第2步: HTTP PDU实现
1. 实现`http.SubmitRequest`,满足`base.SubmitRequest`接口
2. 实现`http.SubmitResponse`,满足`base.SubmitResponse`接口
3. 实现`http.SimpleMessage`,满足`base.Message`接口
4. 编写单元测试验证接口实现正确性

### 第3步: HTTP Server核心功能
1. 实现`server.go`的路由注册(使用Gin框架)
2. 实现`/health`健康检查接口
3. 实现`handleSubmitMessage`处理函数
4. 实现日志中间件
5. 测试: 发送HTTP请求,验证能够到达handler

### 第4步: Basic Auth认证
1. 实现`authMiddleware()`中间件
2. 实现`handleBasicAuth()`函数
3. 在Gateway Delivery中集成usecase(用于账号验证)
4. 测试: 验证正确的账号密码可以通过,错误的被拒绝

### 第5步: 端到端集成测试
1. 启动完整的Gateway服务(HTTP + usecase + repo)
2. 通过HTTP API提交短信
3. 验证消息进入dispatch队列
4. 验证数据库中有短信记录
5. 验证pigeon_web可以查询到消息状态

### 第6步: JWT认证支持(for pigeon_web)
1. 实现`handleJWTAuth()`函数
2. 解析JWT token
3. 验证签名和过期时间
4. 测试pigeon_web UI调用HTTP API

### 第7步: pigeon_web前端集成
1. 在pigeon_web中添加HTTP协议选项(取消disabled)
2. 在短信发送页面添加HTTP API调用
3. 测试pigeon_web -> HTTP Gateway -> 短信发送 -> 状态查询流程

### 第8步: 测试和文档
1. 编写完整的单元测试
2. 编写集成测试
3. 性能测试(目标: QPS > 1000)
4. 编写API使用文档
5. 编写部署文档

### 第9步: 代码Review和优化
1. 代码Review
2. 错误处理优化
3. 日志完善
4. 准备上线

## 7. 测试方案

### 7.1 单元测试

#### PDU接口测试
```go
// pigeon/src/protocol/pdu/http/submit_request_test.go
package http

import (
    "testing"
    "github.com/stretchr/testify/assert"
)

func TestSubmitRequest_Interfaces(t *testing.T) {
    req := NewSubmitRequest("test_account", "127.0.0.1", &SubmitMessageRequest{
        From:    "1234",
        To:      "+8613800138000",
        Content: "Hello",
        Encoding: "UCS2",
    })

    // 测试base.Request接口
    assert.Equal(t, "test_account", req.GetAccount())
    assert.Equal(t, "127.0.0.1", req.GetSrcAddress())
    assert.Equal(t, uint32(0), req.GetSequenceNumber())

    // 测试base.SubmitRequest接口
    srcAddr, err := req.GetSrcAddr()
    assert.NoError(t, err)
    assert.Equal(t, "1234", srcAddr.Addr)

    destAddr, err := req.GetDestAddr()
    assert.NoError(t, err)
    assert.Equal(t, "+8613800138000", destAddr.Addr)

    msg := req.GetMessage()
    assert.Equal(t, "Hello", string(msg.GetContent()))
}

func TestSubmitResponse_Interfaces(t *testing.T) {
    resp := NewSubmitResponse("test_account")
    resp.SetMessageID("msg_123")
    resp.SetStatus(0)

    assert.Equal(t, "msg_123", resp.GetMessageID())
    assert.Equal(t, int32(0), resp.GetStatus())
}
```

#### 认证中间件测试
```go
// pigeon/src/protocol/server/http/middleware_test.go
package http

import (
    "encoding/base64"
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/gin-gonic/gin"
    "github.com/stretchr/testify/assert"
)

func TestBasicAuth_Success(t *testing.T) {
    gin.SetMode(gin.TestMode)
    router := gin.New()

    // Mock server with auth middleware
    s := &httpServer{
        usecase: mockUsecase{}, // Mock usecase返回成功
    }

    router.GET("/test", s.authMiddleware(), func(c *gin.Context) {
        c.JSON(200, gin.H{"ok": true})
    })

    // 构造请求
    auth := base64.StdEncoding.EncodeToString([]byte("test:test123"))
    req := httptest.NewRequest("GET", "/test", nil)
    req.Header.Set("Authorization", "Basic "+auth)

    w := httptest.NewRecorder()
    router.ServeHTTP(w, req)

    assert.Equal(t, 200, w.Code)
}

func TestBasicAuth_InvalidPassword(t *testing.T) {
    gin.SetMode(gin.TestMode)
    router := gin.New()

    s := &httpServer{
        usecase: mockUsecase{}, // Mock usecase返回失败
    }

    router.GET("/test", s.authMiddleware(), func(c *gin.Context) {
        c.JSON(200, gin.H{"ok": true})
    })

    auth := base64.StdEncoding.EncodeToString([]byte("test:wrongpass"))
    req := httptest.NewRequest("GET", "/test", nil)
    req.Header.Set("Authorization", "Basic "+auth)

    w := httptest.NewRecorder()
    router.ServeHTTP(w, req)

    assert.Equal(t, 401, w.Code)
}
```

### 7.2 集成测试

#### 端到端消息提交测试
```go
// pigeon/src/protocol/server/http/integration_test.go
package http

import (
    "bytes"
    "encoding/json"
    "net/http"
    "testing"

    "github.com/stretchr/testify/assert"
)

func TestSubmitMessage_E2E(t *testing.T) {
    // 1. 启动HTTP Gateway
    // 2. 准备测试数据
    reqBody := map[string]interface{}{
        "from":    "1234",
        "to":      "+8613800138000",
        "content": "Test message",
    }
    bodyBytes, _ := json.Marshal(reqBody)

    // 3. 发送HTTP请求
    req, _ := http.NewRequest("POST", "http://localhost:8080/api/v1/messages",
        bytes.NewReader(bodyBytes))
    req.Header.Set("Authorization", "Basic dGVzdDp0ZXN0MTIz")
    req.Header.Set("Content-Type", "application/json")

    client := &http.Client{}
    resp, err := client.Do(req)
    assert.NoError(t, err)
    defer resp.Body.Close()

    // 4. 验证响应
    assert.Equal(t, 200, resp.StatusCode)

    var result map[string]interface{}
    json.NewDecoder(resp.Body).Decode(&result)

    assert.Equal(t, float64(0), result["code"])
    assert.NotNil(t, result["data"])
    data := result["data"].(map[string]interface{})
    assert.NotEmpty(t, data["message_id"])

    // 5. 验证数据库中有记录
    // 6. 验证消息进入dispatch队列
}
```

### 7.3 压力测试

使用`wrk`工具测试:

```bash
# 准备测试脚本
cat > submit.lua <<'EOF'
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
wrk.headers["Authorization"] = "Basic dGVzdDp0ZXN0MTIz"
wrk.body = '{"from":"1234","to":"+8613800138000","content":"Load test"}'
EOF

# 执行压力测试
wrk -t 4 -c 100 -d 30s -s submit.lua http://localhost:8080/api/v1/messages

# 预期目标:
# - QPS > 1000
# - 平均延迟 < 50ms
# - 99%延迟 < 200ms
```

## 8. 注意事项

### 8.1 安全性
1. **认证强度**:
   - 强制使用HTTPS(生产环境)
   - interface_password最少6位
   - 考虑添加IP白名单验证

2. **输入验证**:
   - 手机号格式验证(E.164)
   - 短信内容长度限制
   - 防止SQL注入(使用ORM)

3. **错误信息**:
   - 不要泄露敏感信息
   - 认证失败统一返回"invalid credentials"

### 8.2 性能考虑
1. **并发处理**:
   - Gin框架自带连接池
   - 使用goroutine pool处理submit请求
   - 避免在handler中执行耗时操作

2. **数据库优化**:
   - account_id添加索引
   - message_id添加索引
   - 避免在请求路径中查询大量数据

3. **队列性能**:
   - Redis pipeline批量写入
   - 异步处理,快速返回响应

### 8.3 运维考虑
1. **监控指标**:
   - HTTP请求QPS
   - 请求响应时间(P50/P95/P99)
   - 认证失败率
   - 队列长度

2. **日志规范**:
   - 每个请求记录完整链路日志
   - 包含account_id, message_id, 耗时
   - 敏感信息脱敏(password)

3. **健康检查**:
   - `/health`检查服务存活
   - 可扩展检查数据库/Redis连接

## 9. 后续扩展

### 9.1 可选功能(暂不实现,未来可能需要)
- Webhook推送状态报告给外部客户端
- 外部客户端查询消息状态API
- HTTP长短信支持
- 速率限制和IP白名单
- 批量发送接口

### 9.2 未来规划
- Channel Worker的HTTP Client实现(对接HTTP渠道商)
- MO消息接收
- WebSocket实时推送

## 10. 参考资料

### 10.1 技术栈
- Go 1.24.3
- Gin Web Framework v1.9+
- PostgreSQL 16+
- Redis 8.0+

### 10.2 相关文档
- Gin框架文档: https://gin-gonic.com/docs/
- RESTful API设计最佳实践
- JWT RFC7519

---

**文档版本历史**:
- v1.0 (2025-01-15): 初始版本,完成详细设计
