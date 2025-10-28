# Test Status 字段删除完整计划

## 任务概述
删除 pigeon_web 项目中所有与 test_status、test_time、test_error_message 相关的代码和数据库字段。

## 修改范围

### 一、前端修改 (frontend/src/)

#### 1. 已完成的修改 ✅
- [x] 删除 `TestStatusCell.tsx` 组件文件
- [x] `api/channelApi.ts`: 删除 TestStatus 枚举和类型定义
- [x] `api/channelApi.ts`: 从 Channel 和 ChannelListItem 接口中删除 test_status, test_time, test_error_message 字段
- [x] `api/channelApi.ts`: 从 ChannelFilterParams 删除 test_status 字段
- [x] `api/channelApi.ts`: 从 ChannelStatistics 删除 channels_by_test_status 字段
- [x] `api/channelApi.ts`: 从 getChannels 查询中删除 test_status 参数
- [x] `api/channelApi.ts`: 从 getAllChannelIds 查询中删除 test_status 参数
- [x] `pages/ChannelManagement/components/ChannelTable.tsx`: 删除 TestStatusCell 导入和"检测状态"列
- [x] `pages/ChannelManagement/components/channelFilterConfig.ts`: 删除 TestStatus 定义和 test_status 字段
- [x] `pages/ChannelManagement/components/ChannelSearchFilter.tsx`: 删除测试状态筛选器
- [x] `pages/ChannelManagement/ChannelListPage.tsx`: 从 buildQueryParams 删除 test_status
- [x] `pages/ChannelManagement/components/ChannelDetailModal.tsx`: 删除测试状态显示和相关常量
- [x] `store/slices/channelSlice.ts`: 删除 TestStatus 导入和 test_status 字段

#### 2. 已完成的修改 ✅ (2024-10-27)

##### 2.1 ChannelAdvancedFilter.tsx
- [x] 第121行: 删除预设条件中的 `test_status: 'abnormal'` → 改为 `silent_days_min: 7`
- [x] 第204行: 删除快捷筛选中的 `test_status: 'abnormal'` → 改为 `silent_days_min: 7`
- [x] 第331-332行: 删除测试状态筛选器控件
- [x] 第394行: 从条件判断中删除 `currentFilters.test_status`
- [x] 第409-413行: 删除测试状态标签显示
- [x] 第135-141行: 删除未使用的testStatusOptions变量定义

##### 2.2 BatchExportModal.tsx
- [x] 第64行: 从导出字段列表删除 `{ value: 'test_status', label: 'Test Status', required: false }`

##### 2.3 ChannelSortSelector.tsx
- [x] 第32-33行: 删除测试时间排序选项 (test_time_desc和test_time_asc)

### 二、后端修改 (app/)

#### 1. Schema 修改 ✅

##### 1.1 app/api/v1/channels/schema/channel.py
- [x] 删除 test_status 字段定义 (约58-61行)
- [x] 删除 test_time 字段定义 (约62行)
- [ ] ⏳ 还有3处test_status字段定义需要删除(在不同的Schema类中)
- [ ] ⏳ 还有by_test_status统计字段需要删除

#### 2. Model 修改 ✅

##### 2.1 app/models/customers/channel.py
- [x] 删除 TestStatus 枚举类定义 (约23-28行)
- [x] 删除 test_status 列定义 (约106-107行)
- [x] 删除 test_time 列定义 (约108行)
- [x] 删除 test_error_message 列定义 (约109行)
- [x] 修改 is_healthy 属性,改为检查connection_status
- [x] 删除 is_testing 属性
- [x] 修改 needs_attention 属性,改为检查silent_days和connection_status
- [x] 从 to_dict 方法删除 test_status, test_time, test_error_message

##### 2.2 app/models/customers/__init__.py
- [x] 从导入列表删除 TestStatus
- [x] 从 __all__ 列表删除 'TestStatus'

#### 3. Service 修改

##### 3.1 app/services/channels/channel_service.py
- [ ] 搜索所有 test_status、test_time、test_error_message 的引用
- [ ] 删除相关的查询条件和更新逻辑
- [ ] 检查统计相关方法,删除 channels_by_test_status 的统计

#### 4. Route 修改

##### 4.1 app/api/v1/channels/route/channel_list.py
- [ ] 检查列表查询中是否有 test_status 筛选逻辑
- [ ] 检查统计接口是否返回 test_status 相关数据

##### 4.2 app/api/v1/channels/route/channel_batch.py
- [ ] 检查批量导出是否包含 test_status 字段

##### 4.3 app/api/v1/channels/route/channel_advanced_query.py
- [ ] 检查高级查询预设中是否有 test_status 条件

##### 4.4 app/api/v1/channels/route/channel_test.py
- [ ] 这个文件可能已经废弃或需要重构,检查是否还在使用

### 三、数据库修改 (sql/)

#### 1. Schema 定义

##### 1.1 sql/modules/channels.sql
- [ ] 删除 channels 表的 test_status 列定义
- [ ] 删除 channels 表的 test_time 列定义
- [ ] 删除 channels 表的 test_error_message 列定义

##### 1.2 sql/modules/base.sql
- [ ] 检查是否有 test_status 枚举类型定义,如有则删除

#### 2. Mock 数据

##### 2.1 sql/mock_data/channels.sql
- [ ] 删除 INSERT 语句中的 test_status、test_time、test_error_message 字段和值

#### 3. 初始化脚本

##### 3.1 sql/pigeon_web.sql (汇总脚本)
- [ ] 确保与 modules/channels.sql 保持一致

### 四、验证步骤

#### 1. 前端验证
- [ ] 运行 `npm run build`,确保没有 TypeScript 错误
- [ ] 检查是否有 test_status 相关的编译警告

#### 2. 后端验证
- [ ] 搜索整个后端代码确认没有遗漏:
  ```bash
  grep -r "test_status\|test_time\|test_error_message\|TestStatus" app/
  ```

#### 3. 数据库验证
- [ ] 搜索 SQL 文件确认没有遗漏:
  ```bash
  grep -r "test_status\|test_time\|test_error_message" sql/
  ```

#### 4. 功能测试
- [ ] 启动前端,访问通道管理页面
- [ ] 检查表格显示正常,没有"检测状态"列
- [ ] 检查筛选器正常工作,没有测试状态选项
- [ ] 检查通道详情模态框正常显示
- [ ] 检查导出功能正常工作

## 执行顺序

1. 先完成前端剩余修改
2. 再完成后端修改
3. 最后修改数据库脚本
4. 运行构建验证
5. 功能测试

## 注意事项

1. 所有修改要保持代码格式一致
2. 删除字段后要检查周边逻辑是否受影响
3. 特别注意条件判断和循环中的字段引用
4. 修改完成后要运行 `npm run build` 确保前端无错误
5. 数据库脚本修改后,实际数据库不需要立即迁移(因为是初始化脚本)
