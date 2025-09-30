# 📋 **Pigeon SMS系统ID映射关系详细报告**

## 📊 **报告概述**

本报告详细分析了Pigeon SMS系统中`sms.short_messages`和`sms.delivers`两个核心表中所有ID字段的创建、更新和关联机制，并通过一个完整的长短信处理示例来展示整个ID生命周期管理。

---

## 🔧 **1. ID创建机制分析**

### **1.1 MessageID生成器 (`protocol/utils/message_id_generator.go`)**

```go
type MessageID struct {
    prefix      string    // 通道/网关前缀 (8位)
    timeStr     string    // 时间戳 (10位: mmddhhmmss)
    sequenceNum int32     // 序列号 (8位: 00000001-99999999)
}

// 格式: xxxxxxxx-mmddhhmmss-yyyyyyyy
// 示例: GATEWAY1-250930143822-00001234
```

**生成策略**:
- **线程安全**: 使用`atomic.Int32`保证并发安全
- **唯一性**: 时间戳+自增序列号确保唯一性
- **循环重置**: 序列号超过99999999时重置为1

### **1.2 分段消息ID生成 (`base/utils/long_message_key.go`)**

```go
func NewSegMessageID(parentMsgID string, segNum int) string {
    return fmt.Sprintf("%s_%d", parentMsgID, segNum)
}

// 示例: GATEWAY1-250930143822-00001234_1
//       GATEWAY1-250930143822-00001234_2
```

---

## 🗄️ **2. 数据库表结构分析**

### **2.1 sms.short_messages表ID字段**

| 字段名 | 数据类型 | 说明 | 示例值 |
|--------|----------|------|--------|
| `message_id` | VARCHAR(255) PRIMARY KEY | 主消息ID | `GATEWAY1-250930143822-00001234` |
| `channel_msg_id` | VARCHAR(255) | 通道返回的消息ID | `CHNL001-20250930-98765432` |
| `gateway_code` | VARCHAR(50) | 网关代码 | `GATEWAY1-250930143822-00001234` |

### **2.2 sms.delivers表ID字段**

| 字段名 | 数据类型 | 说明 | 示例值 |
|--------|----------|------|--------|
| `message_id` | VARCHAR(255) PRIMARY KEY | 与short_messages关联的主ID | `GATEWAY1-250930143822-00001234` |
| `channel_msg_id` | VARCHAR(255) | 通道消息ID(来自运营商) | `CHNL001-20250930-98765432` |
| `gateway_msg_id` | VARCHAR(255) | 网关消息ID(发给客户端) | `GATEWAY1-250930143822-00001234` |

### **2.3 通道返回的消息ID详解**

#### **什么是"通道"？**

在pigeon系统中，**"通道"指的是SMS运营商或第三方短信服务提供商**，比如：
- 中国移动、联通、电信的SMPP接口
- 第三方短信平台（如阿里云、腾讯云SMS服务）
- 国际运营商接口

#### **为什么会有"通道返回的消息ID"？**

**原因**: 每个运营商都有自己的消息ID生成规则和格式

**流程解释**:
```
1. Pigeon生成内部ID: GATEWAY1-250930143822-00001234
2. 发送给运营商通道: "请发送这条短信"
3. 运营商接收后生成自己的ID: CHNL001-20250930-98765432
4. 运营商返回: "我已接收，我的消息ID是 CHNL001-20250930-98765432"
5. Pigeon保存: channel_msg_id = CHNL001-20250930-98765432
```

#### **具体代码体现**

在 `channel_worker/usecase/processor.go:315-325` 中：

```go
func (u *channelProcessorU) ReceiveSubmitResponse(
    sm *models.ShortMessage, status modelErr.SubmitResponseStatus) {

    if status == modelErr.SubmitSuccess {
        // 这里建立映射：运营商ID → pigeon内部ID
        u.cacheRepo.SetMsgIDMapping(
            u.channel.ChannelID,
            sm.ChannelMsgID,    // 运营商返回的ID
            sm.MessageID)       // pigeon内部ID
    }
}
```

#### **为什么需要保存运营商的ID？**

**关键原因**: **状态报告识别**

当运营商发送投递状态报告时，他们会说：
- "消息 `CHNL001-20250930-98765432` 已投递成功"
- 而不会说 "消息 `GATEWAY1-250930143822-00001234` 已投递成功"

因为运营商不知道pigeon内部的ID格式。

#### **实际例子对比**

| 系统 | ID格式 | 示例 | 说明 |
|------|--------|------|------|
| **Pigeon内部** | `前缀-时间戳-序列号` | `GATEWAY1-250930143822-00001234` | 统一格式，便于追踪 |
| **中国移动** | `运营商前缀+数字` | `CMCC20250930001234567` | 移动内部格式 |
| **阿里云SMS** | `bizId格式` | `ALY123456789^1234567890` | 阿里云格式 |
| **国际运营商** | `各自标准` | `INTL-GB-20250930-789` | 国际标准格式 |

#### **映射关系的重要性**

```
Pigeon发送时:
message_id: GATEWAY1-250930143822-00001234
    ↓ 发送给运营商
运营商返回:
channel_msg_id: CHNL001-20250930-98765432

状态报告时:
运营商发送: "CHNL001-20250930-98765432 已投递"
    ↓ pigeon查找映射
pigeon找到: GATEWAY1-250930143822-00001234
    ↓ 通知客户端
客户端收到: "GATEWAY1-250930143822-00001234 已投递"
```

**总结**: `channel_msg_id` 就是**运营商在接收到pigeon的短信发送请求后，由运营商自己生成并返回给pigeon的消息标识ID**。这个ID是运营商后续发送状态报告时用来标识消息的唯一凭证。

---

## 🔄 **3. ID关联机制详解**

### **3.1 ID映射缓存机制**

**建立映射** (`channel_worker/usecase/processor.go:323-324`):
```go
u.cacheRepo.SetMsgIDMapping(
    u.channel.ChannelID, sm.ChannelMsgID, sm.MessageID)
```

**查找映射** (`channel_worker/usecase/processor.go:405-406`):
```go
msgID, err := u.cacheRepo.GetMsgIDMapping(
    u.channel.ChannelID, deliver.ChannelMsgID)
```

### **3.2 关联关系图**

```
sms.short_messages                    sms.delivers
┌─────────────────┐                  ┌─────────────────┐
│ message_id      │◄────────────────►│ message_id      │
│ channel_msg_id  │                  │ channel_msg_id  │
│ gateway_code    │                  │ gateway_msg_id  │
└─────────────────┘                  └─────────────────┘
         ▲                                    ▲
         └────────── 缓存映射 ─────────────────┘
```

---

## 📝 **4. 完整长短信处理示例**

### **4.1 场景设定**

**用户操作**: 发送一条长短信，客户端分成4个片段发送给Pigeon
**Pigeon处理**: 合并4个片段为1条完整消息
**通道限制**: 根据通道能力拆分为5个片段发送
**结果**: 5个片段都收到投递回执

### **4.2 详细处理流程**

#### **阶段1: 客户端分段发送 (4个片段)**

**步骤1**: 客户端发送4个分段消息到Gateway

```
片段1: message_id = "GATEWAY1-250930143822-00001234_1"
片段2: message_id = "GATEWAY1-250930143822-00001234_2"
片段3: message_id = "GATEWAY1-250930143822-00001234_3"
片段4: message_id = "GATEWAY1-250930143822-00001234_4"
```

**数据存储** (`sms.short_messages`):
```sql
INSERT INTO sms.short_messages (
    message_id,
    gateway_code,
    "gateway_segment_info.is_parent",
    "gateway_segment_info.parent_message_id",
    "gateway_segment_info.reference_id",
    "gateway_segment_info.total_segments",
    "gateway_segment_info.segment_num",
    content
) VALUES
('GATEWAY1-250930143822-00001234_1', 'GATEWAY1-250930143822-00001234', false, '', 12345, 4, 1, '内容片段1'),
('GATEWAY1-250930143822-00001234_2', 'GATEWAY1-250930143822-00001234', false, '', 12345, 4, 2, '内容片段2'),
('GATEWAY1-250930143822-00001234_3', 'GATEWAY1-250930143822-00001234', false, '', 12345, 4, 3, '内容片段3'),
('GATEWAY1-250930143822-00001234_4', 'GATEWAY1-250930143822-00001234', false, '', 12345, 4, 4, '内容片段4');
```

#### **阶段2: Gateway长短信合并**

**步骤2**: Gateway检测到长短信，触发合并逻辑 (`gateway/usecase/long_message.go:209-242`)

**合并过程**:
1. **生成新的父消息ID**:
   ```go
   msgID := protocolUtils.MessageIDGenerator.Generate("GATEWAY1")
   // 结果: "GATEWAY1-250930143824-00001235"
   ```

2. **创建父消息记录**:
   ```sql
   INSERT INTO sms.short_messages (
       message_id,
       gateway_code,
       "gateway_segment_info.is_parent",
       "gateway_segment_info.sub_message_ids",
       "gateway_segment_info.total_segments",
       "gateway_segment_info.reference_id",
       content
   ) VALUES (
       'GATEWAY1-250930143824-00001235',
       'GATEWAY1',
       true,
       '["GATEWAY1-250930143822-00001234_1","GATEWAY1-250930143822-00001234_2","GATEWAY1-250930143822-00001234_3","GATEWAY1-250930143822-00001234_4"]',
       4,
       12345,
       '内容片段1内容片段2内容片段3内容片段4'
   );
   ```

3. **更新子消息关联**:
   ```sql
   UPDATE sms.short_messages SET
       "gateway_segment_info.parent_message_id" = 'GATEWAY1-250930143824-00001235'
   WHERE message_id IN (
       'GATEWAY1-250930143822-00001234_1',
       'GATEWAY1-250930143822-00001234_2',
       'GATEWAY1-250930143822-00001234_3',
       'GATEWAY1-250930143822-00001234_4'
   );
   ```

#### **阶段3: Channel Worker拆分发送 (5个片段)**

**步骤3**: Channel Worker接收到合并消息，根据通道限制拆分 (`channel_worker/usecase/processor.go:198-244`)

**拆分过程**:
1. **生成分段消息ID**:
   ```go
   // 父消息ID: GATEWAY1-250930143824-00001235
   subMsg1.MessageID = "GATEWAY1-250930143824-00001235_1"
   subMsg2.MessageID = "GATEWAY1-250930143824-00001235_2"
   subMsg3.MessageID = "GATEWAY1-250930143824-00001235_3"
   subMsg4.MessageID = "GATEWAY1-250930143824-00001235_4"
   subMsg5.MessageID = "GATEWAY1-250930143824-00001235_5"
   ```

2. **生成新的引用ID**:
   ```go
   referenceID := utils.NewLongMessageReferenceID() // 例如: 54321
   ```

3. **创建子消息记录**:
   ```sql
   INSERT INTO sms.short_messages (
       message_id,
       channel_msg_id,
       "channel_segment_info.is_parent",
       "channel_segment_info.parent_message_id",
       "channel_segment_info.reference_id",
       "channel_segment_info.total_segments",
       "channel_segment_info.segment_num",
       content
   ) VALUES
   ('GATEWAY1-250930143824-00001235_1', '', false, 'GATEWAY1-250930143824-00001235', 54321, 5, 1, '拆分内容1'),
   ('GATEWAY1-250930143824-00001235_2', '', false, 'GATEWAY1-250930143824-00001235', 54321, 5, 2, '拆分内容2'),
   ('GATEWAY1-250930143824-00001235_3', '', false, 'GATEWAY1-250930143824-00001235', 54321, 5, 3, '拆分内容3'),
   ('GATEWAY1-250930143824-00001235_4', '', false, 'GATEWAY1-250930143824-00001235', 54321, 5, 4, '拆分内容4'),
   ('GATEWAY1-250930143824-00001235_5', '', false, 'GATEWAY1-250930143824-00001235', 54321, 5, 5, '拆分内容5');
   ```

4. **更新父消息信息**:
   ```sql
   UPDATE sms.short_messages SET
       "channel_segment_info.is_parent" = true,
       "channel_segment_info.sub_message_ids" = '["GATEWAY1-250930143824-00001235_1","GATEWAY1-250930143824-00001235_2","GATEWAY1-250930143824-00001235_3","GATEWAY1-250930143824-00001235_4","GATEWAY1-250930143824-00001235_5"]',
       "channel_segment_info.total_segments" = 5,
       "channel_segment_info.reference_id" = 54321
   WHERE message_id = 'GATEWAY1-250930143824-00001235';
   ```

#### **阶段4: 发送到运营商并建立映射**

**步骤4**: 向运营商发送5个片段，收到Submit Response后建立ID映射

**运营商返回的Channel Message IDs**:
```
CHNL001-20250930-98765431 → GATEWAY1-250930143824-00001235_1
CHNL001-20250930-98765432 → GATEWAY1-250930143824-00001235_2
CHNL001-20250930-98765433 → GATEWAY1-250930143824-00001235_3
CHNL001-20250930-98765434 → GATEWAY1-250930143824-00001235_4
CHNL001-20250930-98765435 → GATEWAY1-250930143824-00001235_5
```

**建立缓存映射** (`channel_worker/usecase/processor.go:323-324`):
```go
// 为每个片段建立映射
u.cacheRepo.SetMsgIDMapping("CHNL001", "CHNL001-20250930-98765431", "GATEWAY1-250930143824-00001235_1")
u.cacheRepo.SetMsgIDMapping("CHNL001", "CHNL001-20250930-98765432", "GATEWAY1-250930143824-00001235_2")
u.cacheRepo.SetMsgIDMapping("CHNL001", "CHNL001-20250930-98765433", "GATEWAY1-250930143824-00001235_3")
u.cacheRepo.SetMsgIDMapping("CHNL001", "CHNL001-20250930-98765434", "GATEWAY1-250930143824-00001235_4")
u.cacheRepo.SetMsgIDMapping("CHNL001", "CHNL001-20250930-98765435", "GATEWAY1-250930143824-00001235_5")
```

**更新short_messages表**:
```sql
UPDATE sms.short_messages SET
    channel_msg_id = 'CHNL001-20250930-98765431',
    status = 'ChannelSendSuccess'
WHERE message_id = 'GATEWAY1-250930143824-00001235_1';

-- 对其他4个片段执行类似更新...
```

#### **阶段5: 接收投递回执并创建Deliver记录**

**步骤5**: 运营商发送5个投递回执，Channel Worker处理 (`channel_worker/usecase/processor.go:403-427`)

**回执处理过程**:

1. **片段1回执处理**:
   ```go
   // 收到回执: channel_msg_id = "CHNL001-20250930-98765431"
   // 查找映射
   msgID, err := u.cacheRepo.GetMsgIDMapping("CHNL001", "CHNL001-20250930-98765431")
   // 结果: msgID = "GATEWAY1-250930143824-00001235_1"

   // 设置deliver字段
   deliver.MessageID = "GATEWAY1-250930143824-00001235_1"
   deliver.ChannelMsgID = "CHNL001-20250930-98765431"
   deliver.GatewayMsgID = "GATEWAY1-250930143824-00001235_1"
   ```

2. **创建Deliver记录**:
   ```sql
   INSERT INTO sms.delivers (
       message_id,
       channel_id,
       channel_msg_id,
       gateway_msg_id,
       gateway_code,
       account_id,
       deliver_type,
       receipt_code,
       content,
       status
   ) VALUES (
       'GATEWAY1-250930143824-00001235_1',
       'CHNL001',
       'CHNL001-20250930-98765431',
       'GATEWAY1-250930143824-00001235_1',
       'DELIVERED',
       'ACCT001',
       'DeliverReceipt',
       '000',
       'id:CHNL001-20250930-98765431 submit date:2409301438 done date:2409301439 stat:DELIVRD err:000',
       'ChannelReceived'
   );
   ```

3. **为其余4个片段创建类似的Deliver记录**...

#### **阶段6: 长短信子片段处理特殊逻辑**

**步骤6**: Deliver Worker处理长短信子片段回执 (`deliver_worker/usecase/usecase.go:238-276`)

**特殊处理逻辑**:

1. **子片段Gateway ID映射**:
   ```go
   // 对于子片段 GATEWAY1-250930143824-00001235_1
   parentMsgID, segNum, err := utils.ParseSegMessageID("GATEWAY1-250930143824-00001235_1")
   // parentMsgID = "GATEWAY1-250930143824-00001235"
   // segNum = 1

   // 获取父消息的Gateway分段信息
   parentSM := getShortMessageByMsgID("GATEWAY1-250930143824-00001235")
   segInfo := parentSM.GatewaySegmentInfo

   // 设置正确的Gateway Message ID
   deliver.GatewayMsgID = segInfo.SubMesaageageIDs[segNum-1]
   // 结果: "GATEWAY1-250930143822-00001234_1"
   ```

2. **最终Deliver记录更新**:
   ```sql
   UPDATE sms.delivers SET
       gateway_msg_id = 'GATEWAY1-250930143822-00001234_1'
   WHERE message_id = 'GATEWAY1-250930143824-00001235_1';
   ```

---

## 📊 **5. 完整ID映射表**

### **5.1 最终数据状态**

#### **short_messages表 (10条记录)**

| message_id | channel_msg_id | gateway_code | 说明 |
|------------|----------------|--------------|------|
| `GATEWAY1-250930143822-00001234_1` | - | `GATEWAY1-250930143822-00001234` | 客户端片段1 |
| `GATEWAY1-250930143822-00001234_2` | - | `GATEWAY1-250930143822-00001234` | 客户端片段2 |
| `GATEWAY1-250930143822-00001234_3` | - | `GATEWAY1-250930143822-00001234` | 客户端片段3 |
| `GATEWAY1-250930143822-00001234_4` | - | `GATEWAY1-250930143822-00001234` | 客户端片段4 |
| `GATEWAY1-250930143824-00001235` | - | `GATEWAY1` | 合并后的父消息 |
| `GATEWAY1-250930143824-00001235_1` | `CHNL001-20250930-98765431` | `GATEWAY1` | 通道片段1 |
| `GATEWAY1-250930143824-00001235_2` | `CHNL001-20250930-98765432` | `GATEWAY1` | 通道片段2 |
| `GATEWAY1-250930143824-00001235_3` | `CHNL001-20250930-98765433` | `GATEWAY1` | 通道片段3 |
| `GATEWAY1-250930143824-00001235_4` | `CHNL001-20250930-98765434` | `GATEWAY1` | 通道片段4 |
| `GATEWAY1-250930143824-00001235_5` | `CHNL001-20250930-98765435` | `GATEWAY1` | 通道片段5 |

#### **delivers表 (5条记录)**

| message_id | channel_msg_id | gateway_msg_id | 说明 |
|------------|----------------|----------------|------|
| `GATEWAY1-250930143824-00001235_1` | `CHNL001-20250930-98765431` | `GATEWAY1-250930143822-00001234_1` | 回执1 |
| `GATEWAY1-250930143824-00001235_2` | `CHNL001-20250930-98765432` | `GATEWAY1-250930143822-00001234_2` | 回执2 |
| `GATEWAY1-250930143824-00001235_3` | `CHNL001-20250930-98765433` | `GATEWAY1-250930143822-00001234_3` | 回执3 |
| `GATEWAY1-250930143824-00001235_4` | `CHNL001-20250930-98765434` | `GATEWAY1-250930143822-00001234_4` | 回执4 |
| `GATEWAY1-250930143824-00001235_5` | `CHNL001-20250930-98765435` | `GATEWAY1-250930143822-00001234_1` | 回执5(映射到片段1) |

### **5.2 关键关联关系**

```
两表关联: delivers.message_id ←→ short_messages.message_id

ID层次结构:
客户端层面: GATEWAY1-250930143822-00001234_{1,2,3,4}
  ↓ (合并)
系统内部: GATEWAY1-250930143824-00001235
  ↓ (拆分)
通道层面: GATEWAY1-250930143824-00001235_{1,2,3,4,5}
  ↓ (回执)
回执关联: 通过message_id关联，gateway_msg_id指向原始客户端片段
```

---

## 🎯 **6. 核心发现与总结**

### **6.1 ID管理的关键特点**

1. **三层ID体系**:
   - **Client Layer**: 客户端原始分段ID
   - **System Layer**: 系统内部合并后的完整消息ID
   - **Channel Layer**: 根据通道能力重新拆分的ID

2. **双向映射机制**:
   - **Cache映射**: `channel_msg_id` ↔ `message_id`
   - **数据库关联**: `delivers.message_id` ↔ `short_messages.message_id`

3. **长短信特殊处理**:
   - **Gateway分段**: 客户端长短信合并处理
   - **Channel分段**: 根据通道限制重新拆分
   - **回执映射**: 回执通过复杂逻辑映射回原始客户端片段

### **6.2 数据一致性保证**

1. **原子性操作**: 使用数据库事务确保多条记录同时成功
2. **缓存同步**: ID映射同时更新缓存和数据库
3. **容错机制**: 通过waiting list处理回执延迟到达

### **6.3 性能优化设计**

1. **ID生成器**: 使用原子操作避免锁竞争
2. **缓存优先**: 回执处理优先查询缓存映射
3. **批量处理**: 支持批量创建和更新减少数据库压力

这套ID管理机制确保了从客户端分段发送到运营商投递再到回执反馈的完整链路追踪，支持复杂的长短信合并拆分场景，同时保证了高性能和数据一致性。

---

**报告生成时间**: 2025-09-30
**分析深度**: 完整源码分析
**覆盖范围**: Gateway、Channel Worker、Deliver Worker全链路
**示例完整性**: 包含4→1→5长短信完整处理流程