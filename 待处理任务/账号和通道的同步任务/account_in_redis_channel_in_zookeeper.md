# Account in Redis & Channel in ZooKeeper

### Account
#### key
i:account:account_in
其中，account_in 是 AccountID，也就用这个作为帐户来连接。
如果不管通道选择的话，你可以只管到 "max_deliver_resend_count"
#### value
```json
{
  "unique_id": "",
  "updated_at": "0001-01-01T00:00:00Z",
  "created_at": "0001-01-01T00:00:00Z",
  "enabled": false,
  "account_id": "account_in",
  "password": "password123",
  "sender_id": "111111",
  "valid_ips": "0.0.0.0",
  "is_banned": false,
  "max_connection_count": 10,
  "max_deliver_resend_count": 3,
  "protocol_type": "",
  "signatures": [
    "可发签名",
    "ValidSignature"
  ],
  "whitelisted": false,
  "censor_words": [
    "evil",
    "forbidden"
  ],
  "templates": [
    "Your verification code is {code}",
    "Hello {name}"
  ],
  "allowed_countries": null,
  "allow_content_types": null,
  "pool_weights": {
    "pool1": 0.7,
    "pool3": 0.3
  },
  "number_frequency_limit_info": {
    "frequency_limit": 5,
    "frequency_period": "1h"
  },
  "account_frequency_limit_info": {
    "frequency_limit": 5,
    "frequency_period": "1h"
  }
}
```

### Channel
#### 节点
例如，ChannelID 为 channel_001 的通道信息在：
/pigeon/channel_worker/jobs/channel_001

#### 数据
```json
{
"channel_id": "channel_001",
"provider_id": "provider_cmcc",
"is_direct": true,
"protocol": "SMPP_V32",
"country": "CN",
"operator": "China_Mobile",
"signature": "[CMCC]",
"allow_message_types": ["SMS"],
"allow_content_types": ["OTP", "Notification"],
"path": "172.27.10.192",
"port": 2776,
"account": "account_out",
"password": "password123",
"default_encoding": 1,
"sender_id": "CMCC_SENDER",
"error_codes": null,
"sender_id_len_limit": 11,
"content_bytes_limit": 160,
"rate_limit": 10000,
"max_connection": 2,
"day_send_count_limit": 100000,
"is_enabled": true,
"is_online": true,
"current_connection": 0
}
```


### A.1 Account字段对比

| 字段 | 文档要求 | pigeon_web实现 | Redis同步状态 | 问题 |
|-----|---------|---------------|--------------|------|
| account_id | ✅ | ✅ | ✅ | 无 |
| password | ✅ | ✅ | ✅ | 无 |
| sender_id | ✅ | ⚠️ 迁移到独立表 | ❌ 空字符串 | 需决策 |
| valid_ips | ✅ | ✅ | ✅ | 无 |
| is_banned | ✅ | ✅ | ✅ | 无 |
| max_connection_count | ✅ | ✅ | ✅ | 无 |
| max_deliver_resend_count | ✅ | ✅ | ✅ | 无 |
| protocol_type | ✅ | ✅ | ✅ | 无 |
| signatures | ✅ | ✅ | ✅ | 无 |
| whitelisted | ✅ | ✅ | ✅ | 无 |
| censor_words | ✅ | ✅ | ✅ | 无 |
| templates | ✅ | ✅ | ✅ | 无 |
| unique_id | ✅ | ✅ | ❌ 硬编码空值 | **Bug** |     随机数值
| enabled | ✅ | ✅ | ❌ 硬编码true | **Bug** |       需要（true）
| created_at | ✅ | ✅ | ✅ | 无 |
| updated_at | ✅ | ✅ | ✅ | 无 |

先空置
| pool_weights | ✅ | ❌ | ❌ 空对象 | 缺失 |
| number_frequency_limit_info | ✅ | ❌ | ❌ 空对象 | 缺失 |
| account_frequency_limit_info | ✅ | ❌ | ❌ 空对象 | 缺失 |
| allowed_countries | ✅ | ❌ | ❌ 空数组 | 缺失 |
| allow_content_types | ✅ | ❌ | ❌ 空数组 | 缺失 |

### A.2 Channel字段对比

| 字段 | 文档要求 | pigeon_web字段 | 前端表单 | 问题 |
|-----|---------|---------------|---------|------|
| channel_id | ✅ | channel_id | ✅ | 无 |
NO | provider_id | ✅ | provider_id | ❌ | 前端缺失 |    
NO | is_direct | ✅ | is_direct | ❌ | 前端缺失 |       
YES | protocol | ✅ | protocol | ❌ | 前端缺失 |     
NO | country | ✅ | country | ❌ | 前端缺失 |
NO | operator | ✅ | operator | ❌ | 前端缺失 |
TBD| signature | ✅ | signature | ❌ | 前端缺失 |
NO | allow_message_types | ✅ | allow_message_types | ❌ | 前端缺失 |
NO | allow_content_types | ✅ | allow_content_types | ❌ | 前端缺失 |
YES | path | ✅ | path | ❌ | 前端缺失 |
YES | port | ✅ | port | ❌ | 前端缺失 |
YES | account | ✅ | upstream_account | ❌ | 字段名映射 + 前端缺失 |
YES | password | ✅ | password | ❌ | 前端缺失 |
TBD | default_encoding | ✅ | default_encoding | ❌ | 前端缺失 |
| sender_id | ✅ | sender_id | ✅ | 无 |
NO | error_codes | ✅ | ❌ 可用channel_config | ❌ | 需决策存储方式 |
NO | sender_id_len_limit | ✅ | sender_id_len_limit | ❌ | 前端缺失 |
| content_bytes_limit | ✅ | content_bytes_limit | ❌ | 前端缺失 |
YES | rate_limit | ✅ | rate_limit | ❌ | 前端缺失 |
YES(default 1) | max_connection | ✅ | max_connection | ❌ | 前端缺失 |
NO | day_send_count_limit | ✅ | day_send_count_limit | ❌ | 前端缺失 |
YES| is_enabled | ✅ | is_enabled | ❌ | 前端缺失 |
NO| is_online | ✅ | is_online | ❌ | 前端缺失 |
NO| current_connection | ✅ | cur_connection | ❌ | 字段名映射 + 前端缺失 |